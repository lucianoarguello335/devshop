import Foundation

/// A terminal emulator installed on this Mac.
///
/// Kept separate from `InstalledApplication` because the interesting facts are different:
/// what matters here is where the app keeps its own settings, not when its bundle was last
/// modified.
struct TerminalApp: Sendable, Identifiable, Equatable {
    /// The bundle identifier, which is also the selection id.
    var id: String
    var name: String
    var version: String?
    var build: String?
    var path: String
    /// Where this terminal keeps its own configuration, abbreviated with `~`. Only paths
    /// that exist are listed.
    var configPaths: [String] = []
    var website: String?
    /// Brand colour for the tile fallback, without the leading `#`.
    var colorHex: String = "8e8e93"
    /// Simple Icons slug, used when no bundle icon can be read.
    var iconSlug: String?

    var bundleIdentifier: String { id }

    /// `1.2.3 (456)`, matching how the inspector shows Xcode.
    var versionLine: String {
        switch (version, build) {
        case let (version?, build?) where build != version: "\(version) (\(build))"
        case let (version?, _): version
        default: "—"
        }
    }

    /// First letter, for the tile when no icon can be read at all.
    var monogram: String { String(name.prefix(1)).uppercased() }
}
