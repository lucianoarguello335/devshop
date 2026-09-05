import Foundation

/// Exactly what a grid tile or a table row draws, and nothing else.
///
/// Tiles used to be handed the whole `DetectedTool` and then read the bytes, the finding tier
/// and the abbreviated path back out of the model inside their own body. That made every tile
/// depend on the whole model: one size flush — and there is one every 250ms while measuring —
/// re-evaluated all of them. It also dragged `DetectedTool.children` into the diff, so SwiftUI
/// deep-compared hundreds of `ToolChild` values to decide whether the Homebrew tile had changed.
///
/// Building this once per rebuild instead keeps a tile's inputs small, equatable and cheap to
/// compare, which is what lets `.equatable()` skip the ones that did not change.
struct TileData: Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    /// Secondary line under the name, e.g. `3.11.6 · pyenv`.
    var subtitle: String
    /// The bare version number, or `nil` when nothing on disk states one.
    var version: String?
    /// `path`, already run through `Probes.abbreviate`. `nil` when the tool has no path.
    var displayPath: String?
    var managedBy: String
    var status: ToolStatus
    /// Simple Icons slug for the brand mark, when the catalog names one.
    var iconSlug: String?
    /// SF Symbol drawn when there is no brand mark.
    var symbol: String
    /// Brand colour as a six-digit hex string, without the leading `#`.
    var colorHex: String
    var bytes: Int64
    /// Most severe finding touching this tool, if any.
    var findingTier: FindingTier?

    var isMissing: Bool { status == .missing }

    init(tool: DetectedTool, bytes: Int64, findingTier: FindingTier?) {
        self.id = tool.id
        self.name = tool.name
        self.subtitle = tool.subtitle
        self.version = tool.version
        self.displayPath = tool.path.map(Probes.abbreviate)
        self.managedBy = tool.managedBy
        self.status = tool.status
        self.iconSlug = tool.definition.icon
        self.symbol = tool.definition.symbol
        self.colorHex = tool.definition.color
        self.bytes = bytes
        self.findingTier = findingTier
    }
}
