import Foundation

/// Enumerates what lives inside a container tile.
///
/// Everything here is a directory listing plus, at most, one small file read for a version
/// string. No package manager is ever invoked.
enum ChildReaders {
    /// Brand marks whose Simple Icons slug differs from the package name. Anything not
    /// listed falls back to a normalised match, then to a monogram.
    private static let slugAliases: [String: String] = [
        "node": "nodedotjs", "nodejs": "nodedotjs",
        "visual-studio-code": "vscodium", "python@3.13": "python", "python@3.12": "python",
        "openjdk": "openjdk", "gh": "github", "git-lfs": "gitlfs",
        "postgresql@17": "postgresql", "postgresql@16": "postgresql", "postgresql@14": "postgresql",
        "mongodb-community": "mongodb", "kubernetes-cli": "kubernetes",
        "awscli": "amazonwebservices", "google-cloud-sdk": "googlecloud",
        "gcloud-cli": "googlecloud",
        "docker": "docker", "podman": "podman", "rust": "rust", "ruby": "ruby",
        "go": "go", "deno": "deno", "bun": "bun", "php": "php", "lua": "lua",
        // The CLI is not named after the product it belongs to.
        "codex": "openai", "chatgpt": "openai", "claude-code": "claude",
        "claude-squad": "claude", "vlc": "vlcmediaplayer", "code": "vscodium",
        "gemini-cli": "googlegemini", "ollama": "ollama", "1password-cli": "1password"
    ]

    static func children(for tool: DetectedTool, brew: HomebrewReader) -> [ToolChild] {
        switch tool.definition.id {
        case "pkg.homebrew": return formulae(brew) + casks(brew)
        case "brew.formulae": return formulae(brew)
        case "brew.casks": return casks(brew)
        case "brew.taps": return taps(brew)
        case "pkg.npm": return npmGlobals()
        case "pkg.pip": return pipPackages()
        case "ide.vscodeext": return vsCodeExtensions()
        case "pkg.nvm": return managed(.nvm, parent: tool.id)
        case "pkg.pyenv": return managed(.pyenv, parent: tool.id)
        case "pkg.rbenv": return managed(.rbenv, parent: tool.id)
        default: return []
        }
    }

    // MARK: - Homebrew

    private static func formulae(_ brew: HomebrewReader) -> [ToolChild] {
        brew.formulae.map { name, installed in
            ToolChild(id: "brew.formulae/\(name)",
                      token: name,
                      name: name,
                      version: installed.version,
                      path: installed.path,
                      appBundlePath: nil,
                      iconSlug: slug(for: name),
                      color: tint(for: name))
        }
    }

    private static func casks(_ brew: HomebrewReader) -> [ToolChild] {
        brew.casks.map { token, installed in
            // A cask usually stages the real .app, whose own icon and name beat anything
            // that could be guessed from the token.
            let bundle = appBundle(inside: installed.path) ?? installedApplication(named: token)
            let display = bundle.map {
                ($0 as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")
            }
            return ToolChild(id: "brew.casks/\(token)",
                             token: token,
                             name: display ?? token,
                             version: marketingVersion(installed.version),
                             path: installed.path,
                             appBundlePath: bundle,
                             iconSlug: bundle == nil ? slug(for: token) : nil,
                             color: tint(for: token))
        }
    }

    private static func taps(_ brew: HomebrewReader) -> [ToolChild] {
        let root = brew.prefix + "/Library/Taps"
        return Probes.subdirectories(of: root).flatMap { org in
            Probes.subdirectories(of: "\(root)/\(org)").map { repo in
                let short = repo.replacingOccurrences(of: "homebrew-", with: "")
                return ToolChild(id: "brew.taps/\(org)/\(repo)",
                                 token: "\(org)/\(short)",
                                 name: "\(org)/\(short)",
                                 version: "tap",
                                 path: "\(root)/\(org)/\(repo)",
                                 appBundlePath: nil,
                                 iconSlug: org == "homebrew" ? "homebrew" : nil,
                                 color: tint(for: org))
            }
        }
    }

    /// The first `.app` staged inside a Caskroom version directory.
    private static func appBundle(inside path: String) -> String? {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: path) else { return nil }
        if let app = names.first(where: { $0.hasSuffix(".app") }) {
            return path + "/" + app
        }
        return nil
    }

    /// Some casks install straight into /Applications and leave only a receipt behind.
    private static func installedApplication(named token: String) -> String? {
        let target = token.replacingOccurrences(of: "-", with: "")
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: "/Applications") else {
            return nil
        }
        let match = names.first { name in
            guard name.hasSuffix(".app") else { return false }
            let stripped = name.replacingOccurrences(of: ".app", with: "")
                .replacingOccurrences(of: " ", with: "")
                .lowercased()
            return stripped == target
        }
        return match.map { "/Applications/" + $0 }
    }

    // MARK: - Language package managers

    private static func npmGlobals() -> [ToolChild] {
        var roots = ["/opt/homebrew/lib/node_modules", "/usr/local/lib/node_modules"]
        let nvm = Probes.expand("~/.nvm/versions/node")
        roots += Probes.subdirectories(of: nvm).map { "\(nvm)/\($0)/lib/node_modules" }

        var seen = Set<String>()
        var out: [ToolChild] = []
        for root in roots {
            for name in Probes.subdirectories(of: root) where !name.hasPrefix(".") {
                // Scoped packages nest one level deeper: @scope/name.
                let entries = name.hasPrefix("@")
                    ? Probes.subdirectories(of: "\(root)/\(name)").map { "\(name)/\($0)" }
                    : [name]
                for entry in entries where !seen.contains(entry) {
                    seen.insert(entry)
                    let path = "\(root)/\(entry)"
                    out.append(ToolChild(id: "pkg.npm/\(entry)",
                                         token: entry,
                                         name: entry,
                                         version: packageJSONVersion(at: path) ?? "—",
                                         path: path,
                                         appBundlePath: nil,
                                         iconSlug: slug(for: entry),
                                         color: tint(for: entry)))
                }
            }
        }
        return out
    }

    private static func packageJSONVersion(at path: String) -> String? {
        guard let data = FileManager.default.contents(atPath: path + "/package.json"),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json["version"] as? String
    }

    private static func pipPackages() -> [ToolChild] {
        var roots: [String] = []
        let pyenv = Probes.expand("~/.pyenv/versions")
        for version in Probes.subdirectories(of: pyenv) {
            let lib = "\(pyenv)/\(version)/lib"
            roots += Probes.subdirectories(of: lib).map { "\(lib)/\($0)/site-packages" }
        }
        let brewLib = "/opt/homebrew/lib"
        roots += Probes.subdirectories(of: brewLib)
            .filter { $0.hasPrefix("python") }
            .map { "\(brewLib)/\($0)/site-packages" }

        var seen = Set<String>()
        var out: [ToolChild] = []
        for root in roots {
            // Each installed distribution leaves a `<name>-<version>.dist-info` directory.
            for entry in Probes.subdirectories(of: root) where entry.hasSuffix(".dist-info") {
                let stem = entry.replacingOccurrences(of: ".dist-info", with: "")
                let parts = stem.split(separator: "-")
                guard parts.count >= 2 else { continue }
                let name = parts.dropLast().joined(separator: "-")
                guard !seen.contains(name) else { continue }
                seen.insert(name)
                let packagePath = "\(root)/\(name.replacingOccurrences(of: "-", with: "_"))"
                out.append(ToolChild(id: "pkg.pip/\(name)",
                                     token: name,
                                     name: name,
                                     version: String(parts.last!),
                                     path: Probes.isDirectory(packagePath) ? packagePath : "\(root)/\(entry)",
                                     appBundlePath: nil,
                                     iconSlug: slug(for: name),
                                     color: tint(for: name)))
            }
        }
        return out
    }

    private static func vsCodeExtensions() -> [ToolChild] {
        let root = Probes.expand("~/.vscode/extensions")
        return Probes.subdirectories(of: root).compactMap { entry in
            guard let (identifier, version) = splitVersion(entry) else { return nil }
            let short = identifier.split(separator: ".").dropFirst().joined(separator: ".")
            return ToolChild(id: "ide.vscodeext/\(identifier)",
                             token: identifier,
                             name: short.isEmpty ? identifier : short,
                             version: version,
                             path: "\(root)/\(entry)",
                             appBundlePath: nil,
                             iconSlug: slug(for: short),
                             color: tint(for: identifier))
        }
    }

    private static func managed(_ kind: VersionManagerKind, parent: String) -> [ToolChild] {
        VersionReaders.versions(for: kind).map { version in
            ToolChild(id: "\(parent)/\(version.version)",
                      token: version.version,
                      name: version.version,
                      version: kind.managerName,
                      path: version.path,
                      appBundlePath: nil,
                      iconSlug: nil,
                      color: tint(for: version.version))
        }
    }

    /// Homebrew appends a build revision to some cask versions after a comma. Only the part
    /// a person would recognise is worth showing.
    private static func marketingVersion(_ raw: String) -> String {
        raw.split(separator: ",").first.map(String.init) ?? raw
    }

    /// Splits `publisher.name-1.2.3-darwin-arm64` into its identifier and version.
    ///
    /// The version is found by looking for the last dash followed by a digit, because both
    /// the identifier and the platform suffix contain dashes of their own.
    private static func splitVersion(_ entry: String) -> (String, String)? {
        var boundary: String.Index?
        var index = entry.startIndex
        while let dash = entry[index...].firstIndex(of: "-") {
            let after = entry.index(after: dash)
            if after < entry.endIndex, entry[after].isNumber { boundary = dash }
            guard after < entry.endIndex else { break }
            index = after
        }
        guard let boundary else { return nil }
        let identifier = String(entry[entry.startIndex..<boundary])
        let rest = entry[entry.index(after: boundary)...]
        // Drop the platform suffix that follows the version.
        let version = rest.split(separator: "-").first.map(String.init) ?? String(rest)
        return (identifier, version)
    }

    // MARK: - Presentation helpers

    /// Matches a package name to a bundled brand mark.
    ///
    /// Package names rarely equal the brand's Simple Icons slug, so several candidates are
    /// tried in descending confidence and the first one that actually ships with the app
    /// wins. Returning a slug with no mark behind it would just draw nothing.
    static func slug(for name: String) -> String? {
        for candidate in candidates(for: name) where IconStoreProbe.has(candidate) {
            return candidate
        }
        return nil
    }

    private static func candidates(for name: String) -> [String] {
        func normalise(_ value: String) -> String {
            value.lowercased().filter { $0.isLetter || $0.isNumber }
        }

        var out: [String] = []
        if let alias = slugAliases[name] { out.append(alias) }
        out.append(normalise(name))

        // A scoped npm package is published by the brand in its scope: @playwright/mcp.
        if name.hasPrefix("@"), let slash = name.firstIndex(of: "/") {
            out.append(normalise(String(name[name.index(after: name.startIndex)..<slash])))
        }
        // Tools are commonly the brand plus a qualifier — claude-code, docker-compose,
        // aws-cli. Dropping one trailing component finds the brand without inventing one.
        let parts = name.split(separator: "-")
        if parts.count > 1 {
            out.append(normalise(parts.dropLast().joined(separator: "-")))
        }
        return out
    }

    /// A stable colour per name, so a package keeps the same monogram tint between launches.
    static func tint(for name: String) -> String {
        let palette = ["0a84ff", "5e5ce6", "30d158", "ff9f0a", "ff453a",
                       "af52de", "64d2ff", "ff6482", "a2845e", "32ade6"]
        var hash: UInt64 = 5381
        for byte in name.utf8 { hash = (hash &* 33) &+ UInt64(byte) }
        return palette[Int(hash % UInt64(palette.count))]
    }
}
