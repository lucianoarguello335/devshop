import Foundation

/// An application bundle found in /Applications.
struct InstalledApplication: Sendable, Equatable, Identifiable {
    var id: String { path }
    var name: String
    var version: String?
    var build: String?
    var bundleIdentifier: String?
    var path: String
    var modifiedAt: Date?
    /// `user` for anything installed, `system` for what macOS ships with.
    var source: Source

    enum Source: String, Sendable, Codable {
        case user, system
    }
}

/// Lists what is installed in /Applications.
///
/// Sizes are deliberately not measured here. Walking 115 bundles — Xcode alone is several
/// gigabytes — would take far longer than the rest of the scan, and the export is built
/// synchronously when the button is pressed. Everything read here is one property-list read
/// and one stat per bundle.
enum ApplicationsReader {
    /// Finder's "Applications" is a merged view of two directories, which is why it shows
    /// FaceTime and Font Book next to everything you installed. Both are read so the export
    /// matches what you see there, tagged so the two can be told apart.
    static let roots: [(path: String, source: InstalledApplication.Source)] = [
        ("/Applications", .user),
        ("/System/Applications", .system)
    ]

    static func scan() -> [InstalledApplication] {
        roots.flatMap { root -> [InstalledApplication] in
            let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
            return names.filter { $0.hasSuffix(".app") }.map { entry in
                let path = "\(root.path)/\(entry)"
                let info = infoPlist(at: path)
                return InstalledApplication(
                    name: entry.replacingOccurrences(of: ".app", with: ""),
                    version: info?["CFBundleShortVersionString"] as? String,
                    build: info?["CFBundleVersion"] as? String,
                    bundleIdentifier: info?["CFBundleIdentifier"] as? String,
                    path: path,
                    modifiedAt: modificationDate(of: path),
                    source: root.source
                )
            }
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func infoPlist(at bundlePath: String) -> [String: Any]? {
        guard let data = FileManager.default.contents(atPath: bundlePath + "/Contents/Info.plist"),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil)
        else { return nil }
        return plist as? [String: Any]
    }

    private static func modificationDate(of path: String) -> Date? {
        try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date
    }
}
