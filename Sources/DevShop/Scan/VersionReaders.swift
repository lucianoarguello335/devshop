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
