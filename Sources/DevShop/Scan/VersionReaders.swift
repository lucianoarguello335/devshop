import Foundation

/// Extracts version strings from the files a toolchain leaves on disk.
enum VersionReaders {
    /// One entry per installed version under a version manager's root.
    struct ManagedVersion: Sendable {
        var version: String
        var path: String
    }

    static func versions(for kind: VersionManagerKind) -> [ManagedVersion] {
        let root = Probes.expand(kind.root)
        switch kind {
        case .jvm:
            return Probes.subdirectories(of: root).compactMap { bundle in
                let path = root + "/" + bundle
                let version = jvmVersion(atBundle: path) ?? bundle
                return ManagedVersion(version: version, path: path)
            }
        case .xcodeToolchains:
            return Probes.subdirectories(of: root).map { name in
                ManagedVersion(version: name.replacingOccurrences(of: ".xctoolchain", with: ""),
                               path: root + "/" + name)
            }
        default:
            return Probes.subdirectories(of: root)
                .sorted(by: HomebrewReader.versionLess)
                .map { ManagedVersion(version: normalise($0), path: root + "/" + $0) }
        }
    }

    /// nvm names its directories `v22.19.0`; the rest use a bare number.
    private static func normalise(_ raw: String) -> String {
        raw.hasPrefix("v") && raw.dropFirst().first?.isNumber == true ? String(raw.dropFirst()) : raw
    }

    /// A JDK bundle carries its version in `Contents/Info.plist`.
    private static func jvmVersion(atBundle path: String) -> String? {
        let plist = path + "/Contents/Info.plist"
        guard let data = FileManager.default.contents(atPath: plist),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = info as? [String: Any] else { return nil }
        if let jvm = dict["JavaVM"] as? [String: Any],
           let version = jvm["JVMVersion"] as? String {
            return version
        }
        return dict["CFBundleShortVersionString"] as? String
    }

    /// Reads a version out of a plain text file such as `~/.nvm/alias/default`.
    static func firstLine(ofFile path: String) -> String? {
        guard let data = FileManager.default.contents(atPath: Probes.expand(path)),
              let text = String(data: data, encoding: .utf8) else { return nil }
        let line = text.split(separator: "\n").first.map(String.init)
        return line?.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Single-tool readers
    //
    // Everything below stays filesystem-only, the same rule the rest of the scan follows.
    // Each reader knows the one file its tool writes its version into, so the Version
    // column can show a number instead of the word "installed".

    /// Only accepts something shaped like a version. `~/.sdkman/var/version` and friends
    /// are plain text files a failed download can fill with an HTML error page.
    static func plausible(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
              raw.count <= 24,
              raw.first?.isNumber == true || (raw.first == "v" && raw.dropFirst().first?.isNumber == true)
        else { return nil }
        let allowed = CharacterSet(charactersIn: "0123456789.-_+abcdefghijklmnopqrstuvwxyz")
        guard raw.lowercased().unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        return raw.hasPrefix("v") ? String(raw.dropFirst()) : raw
    }

    /// `"version"` out of a `package.json`. Used for npm, which ships its own manifest.
    static func packageJSONVersion(at path: String) -> String? {
        guard let data = FileManager.default.contents(atPath: Probes.expand(path)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return plausible(json["version"] as? String)
    }

    /// A Python distribution records its version in the directory name pip installs it
    /// under: `site-packages/poetry-2.2.0.dist-info`.
    static func distInfoVersion(package: String, inSitePackagesUnder root: String) -> String? {
        let full = Probes.expand(root)
        let fm = FileManager.default
        // `lib/python3.14/site-packages`, and the venv layouts that nest one level deeper.
        var candidates = [full, full + "/lib"]
        for lib in [full + "/lib", full + "/venv/lib"] where Probes.isDirectory(lib) {
            candidates += Probes.subdirectories(of: lib).map { lib + "/" + $0 + "/site-packages" }
        }
        for dir in candidates where Probes.isDirectory(dir) {
            guard let names = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for name in names where name.hasPrefix(package + "-") && name.hasSuffix(".dist-info") {
                let middle = name.dropFirst(package.count + 1).dropLast(".dist-info".count)
                if let version = plausible(String(middle)) { return version }
            }
        }
        return nil
    }

    /// nvm is a shell script; the version it prints for `nvm --version` is a literal in it.
    static func nvmVersion(root: String = "~/.nvm") -> String? {
        guard let data = FileManager.default.contents(atPath: Probes.expand(root) + "/nvm.sh"),
              let text = String(data: data, encoding: .utf8) else { return nil }
        guard let range = text.range(of: "nvm_echo '[0-9]+\\.[0-9]+\\.[0-9]+'",
                                     options: .regularExpression) else { return nil }
        return plausible(text[range].split(separator: "'").last.map(String.init))
    }

    /// Homebrew's version is the tag its checkout sits on. Reading the ref files is the
    /// filesystem equivalent of `git describe` for the simple case Homebrew always is:
    /// `stable` pointing straight at a release tag.
    static func homebrewVersion(prefix: String) -> String? {
        let git = prefix + "/.git"
        guard let head = firstLine(ofFile: git + "/HEAD") else { return nil }
        let ref = head.hasPrefix("ref: ") ? String(head.dropFirst(5)) : nil
        let sha = ref.flatMap { firstLine(ofFile: git + "/" + $0) } ?? head

        let tagsDir = git + "/refs/tags"
        let tags = (try? FileManager.default.contentsOfDirectory(atPath: tagsDir)) ?? []
        for tag in tags where firstLine(ofFile: tagsDir + "/" + tag) == sha {
            if let version = plausible(tag) { return version }
        }
        // No loose tag matches HEAD — fall back to the newest tag the checkout knows about.
        return tags.compactMap(plausible).max(by: HomebrewReader.versionLess)
    }

    /// The clang the toolchain actually ships, from the versioned resource directory it
    /// keeps its headers in. This is the compiler's own version, which is not the same
    /// number as the Command Line Tools package version.
    static func clangVersion(toolchainPrefix: String) -> String? {
        let dir = toolchainPrefix + "/usr/lib/clang"
        return Probes.subdirectories(of: dir)
            .compactMap(plausible)
            .max(by: HomebrewReader.versionLess)
    }

    /// A tool that ships a `<name>-config` script has its exact version baked into that
    /// script as a literal, because the script only echoes it back. `curl-config` says
    /// `echo libcurl 8.7.1` — which is worth reading first, since the man page macOS ships
    /// alongside curl lags the binary by a release.
    static func configScriptVersion(command: String, near path: String?) -> String? {
        guard let path else { return nil }
        let bin = (path as NSString).deletingLastPathComponent
        let script = "\(bin)/\(command)-config"
        guard let data = FileManager.default.contents(atPath: script),
              let text = String(data: data, encoding: .utf8) else { return nil }
        // Anchored on the tool's own name so a version belonging to something else the
        // script mentions is not picked up.
        for token in ["lib" + command, command] {
            let pattern = token + " [0-9]+(\\.[0-9]+)+"
            guard let range = text.range(of: pattern, options: .regularExpression) else { continue }
            if let version = plausible(text[range].split(separator: " ").last.map(String.init)) {
                return version
            }
        }
        return nil
    }

    /// Most Unix tools state their version in the header line of their own man page:
    ///
    ///     .TH curl 1 "March 12 2024" "curl 8.6.0" "curl Manual"
    ///     .TH BASH 1 "2006 September 28" "GNU Bash-3.2"
    ///
    /// That is a plain text file, so reading it stays inside the no-subprocess rule and
    /// covers the tools that state their version nowhere else — bash, curl and git among
    /// them. Compressed pages are skipped; nothing in the catalog needs one yet.
    static func manPageVersion(command: String, near path: String?) -> String? {
        var roots = ["/usr/share/man/man1",
                     "/Library/Developer/CommandLineTools/usr/share/man/man1"]
        if let path {
            // `<prefix>/bin/<command>` puts the page at `<prefix>/share/man/man1`.
            let bin = (path as NSString).deletingLastPathComponent
            let prefix = (bin as NSString).deletingLastPathComponent
            roots.insert(prefix + "/share/man/man1", at: 0)
        }
        for root in roots {
            guard let line = titleHeaderLine(atManPage: "\(root)/\(command).1") else { continue }
            if let version = version(inTitleHeader: line) { return version }
        }
        return nil
    }

    /// The `.TH` line, from the first few kilobytes. Man pages open with a comment block,
    /// so the header is never far in, and the body is not worth reading.
    private static func titleHeaderLine(atManPage path: String) -> String? {
        guard let data = FileManager.default.contents(atPath: path),
              let head = String(data: data.prefix(16_384), encoding: .utf8) else { return nil }
        return head.split(separator: "\n").first { $0.hasPrefix(".TH") }.map(String.init)
    }

    /// Picks the version out of a `.TH` line. The quoted fields after the name and section
    /// hold a date and a source string in either order, so this takes the first field that
    /// looks like a version. A date never does — `2025-07-22` and `March 12 2024` have no
    /// `<digits>.<digits>` in them.
    static func version(inTitleHeader line: String) -> String? {
        // groff escapes the dots in a version: `Git 2\&.50\&.1\&.428`.
        let cleaned = line.replacingOccurrences(of: "\\&", with: "")
        guard let range = cleaned.range(of: "[0-9]+(\\.[0-9]+)+", options: .regularExpression)
        else { return nil }
        // Apple's git page carries the full build string, `2.50.1.428.g0e8243`. Three
        // components is the version people recognise, and what `git --version` prints.
        let components = cleaned[range].split(separator: ".").prefix(3)
        return plausible(components.joined(separator: "."))
    }

    /// Several tools macOS ships state their version in the name of the directory they keep
    /// their libraries in — `/usr/share/zsh/5.9`, `/System/Library/Perl/5.34`. The newest
    /// such directory is the version in use.
    static func versionedSubdirectory(of path: String) -> String? {
        Probes.subdirectories(of: path)
            .compactMap(plausible)
            .max(by: HomebrewReader.versionLess)
    }

    /// The Swift compiler stamps its version into the header of every `.swiftinterface`
    /// it emits, so the shipped standard library states the toolchain's Swift version
    /// without anything having to be run.
    static func swiftVersion() -> String? {
        let prefixes = [
            "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain",
            "/Library/Developer/CommandLineTools"
        ]
        for prefix in prefixes {
            let macosx = prefix + "/usr/lib/swift/macosx"
            for module in Probes.subdirectories(of: macosx) where module.hasSuffix(".swiftmodule") {
                let dir = macosx + "/" + module
                let names = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
                for name in names.sorted() where name.hasSuffix(".swiftinterface") {
                    guard let version = swiftCompilerVersion(inInterfaceAt: dir + "/" + name)
                    else { continue }
                    return version
                }
            }
        }
        return nil
    }

    /// `// swift-compiler-version: Apple Swift version 6.3.3 (…)` → `6.3.3`.
    private static func swiftCompilerVersion(inInterfaceAt path: String) -> String? {
        guard let handle = FileManager.default.contents(atPath: path),
              let head = String(data: handle.prefix(512), encoding: .utf8),
              let range = head.range(of: "Swift version [0-9][0-9.]*", options: .regularExpression)
        else { return nil }
        return plausible(head[range].split(separator: " ").last.map(String.init))
    }

    /// A default gem records its version in the name of its gemspec:
    /// `specifications/default/bundler-1.17.2.gemspec`.
    static func defaultGemVersion(_ gem: String) -> String? {
        for root in ["/Library/Ruby/Gems"] {
            for series in Probes.subdirectories(of: root) {
                let dir = root + "/" + series + "/specifications/default"
                let names = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
                for name in names where name.hasPrefix(gem + "-") && name.hasSuffix(".gemspec") {
                    let middle = name.dropFirst(gem.count + 1).dropLast(".gemspec".count)
                    if let version = plausible(String(middle)) { return version }
                }
            }
        }
        return nil
    }

    /// RubyGems is not a default gem, so its version lives in a constant in `rubygems.rb`.
    static func rubyGemsVersion() -> String? {
        let base = "/System/Library/Frameworks/Ruby.framework/Versions"
        for series in Probes.subdirectories(of: base) {
            let file = "\(base)/\(series)/usr/lib/ruby/\(series).0/rubygems.rb"
            guard let data = FileManager.default.contents(atPath: file),
                  let text = String(data: data, encoding: .utf8),
                  let range = text.range(of: "VERSION = \"[0-9][0-9a-z.]*\"",
                                         options: .regularExpression) else { continue }
            if let version = plausible(text[range].split(separator: "\"").last.map(String.init)) {
                return version
            }
        }
        return nil
    }

    /// Xcode's Command Line Tools version, from the receipt Apple installs with them.
    static func commandLineToolsVersion() -> String? {
        let receipts = "/Library/Receipts/InstallHistory.plist"
        guard let data = FileManager.default.contents(atPath: receipts),
              let list = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let entries = list as? [[String: Any]] else { return nil }
        let cltEntries = entries.filter {
            ($0["displayName"] as? String)?.contains("Command Line Tools") == true
        }
        return cltEntries.last?["displayVersion"] as? String
    }
}
