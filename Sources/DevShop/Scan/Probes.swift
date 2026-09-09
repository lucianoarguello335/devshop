import Foundation

/// Pure filesystem lookups. Nothing here spawns a process or touches the network.
enum Probes {
    static let home = FileManager.default.homeDirectoryForCurrentUser.path

    /// Directories searched for executables, in precedence order. This mirrors a typical
    /// login PATH without reading the user's shell configuration.
    static let binSearchPaths: [String] = [
        "/opt/homebrew/bin",
        "/opt/homebrew/sbin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
        "/usr/sbin",
        "/sbin",
        "~/.cargo/bin",
        "~/.local/bin",
        "~/.rbenv/shims",
        "~/.pyenv/shims",
        "~/.jenv/shims",
        "/Library/Developer/CommandLineTools/usr/bin",
        "/opt/local/bin"
    ]

    /// Expands a leading `~` and normalises the result. Paths in the catalog are written
    /// with `~` so the JSON stays machine-independent.
    static func expand(_ path: String) -> String {
        guard path.hasPrefix("~") else { return path }
        return home + String(path.dropFirst())
    }

    static func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: expand(path))
    }

    static func isDirectory(_ path: String) -> Bool {
        var dir: ObjCBool = false
        let found = FileManager.default.fileExists(atPath: expand(path), isDirectory: &dir)
        return found && dir.boolValue
    }

    /// True for a symlink itself, without following it. `attributesOfItem` does not
    /// resolve the link, which is exactly the distinction `isDirectory` cannot make.
    static func isSymbolicLink(_ path: String) -> Bool {
        let attributes = try? FileManager.default.attributesOfItem(atPath: expand(path))
        return attributes?[.type] as? FileAttributeType == .typeSymbolicLink
    }

    /// Immediate subdirectory names, sorted, hidden entries dropped. Returns `[]` for a
    /// path that does not exist — an unreadable directory is not an error here.
    ///
    /// Symlinks are skipped even when they point at a directory. Several casks stage a
    /// `latest` link beside the real version directory; counting it made the cask look
    /// like it had two versions installed and made `latest` sort last, which is what the
    /// version pass then reported.
    static func subdirectories(of path: String) -> [String] {
        let full = expand(path)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: full) else { return [] }
        return names
            .filter { !$0.hasPrefix(".") }
            .filter { isDirectory(full + "/" + $0) && !isSymbolicLink(full + "/" + $0) }
            .sorted()
    }

    /// First bin directory holding one of `names`. Symlinks are resolved so a Homebrew
    /// shim reports its real Cellar location.
    static func findExecutable(_ names: [String]) -> String? {
        for dir in binSearchPaths {
            for name in names {
                let candidate = expand(dir) + "/" + name
                if FileManager.default.isExecutableFile(atPath: candidate) {
                    return resolve(candidate)
                }
            }
        }
        return nil
    }

    /// Follows symlinks to the real file, keeping the original path if resolution fails.
    static func resolve(_ path: String) -> String {
        let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        return url.path
    }

    /// `CFBundleShortVersionString`, falling back to `CFBundleVersion`.
    static func appVersion(at bundlePath: String) -> String? {
        let plist = expand(bundlePath) + "/Contents/Info.plist"
        guard let data = FileManager.default.contents(atPath: plist),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = info as? [String: Any] else { return nil }
        return dict["CFBundleShortVersionString"] as? String ?? dict["CFBundleVersion"] as? String
    }

    /// Build number, shown alongside the version for Xcode: `26.6 (17F115)`.
    static func appBuild(at bundlePath: String) -> String? {
        let plist = expand(bundlePath) + "/Contents/Info.plist"
        guard let data = FileManager.default.contents(atPath: plist),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = info as? [String: Any] else { return nil }
        return dict["CFBundleVersion"] as? String
    }

    /// Replaces the home directory with `~` so the inspector shows short paths.
    static func abbreviate(_ path: String) -> String {
        path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
