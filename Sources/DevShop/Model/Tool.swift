import Foundation

/// A catalog entry: something DevShop knows how to look for.
struct ToolDefinition: Sendable, Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var category: ToolCategory
    /// Simple Icons slug. `nil`, or a slug with no downloaded mark, falls back to `symbol`.
    var icon: String?
    /// SF Symbol used when there is no brand mark.
    var symbol: String
    /// Brand color as a six-digit hex string, without the leading `#`.
    var color: String
    var website: String?
    var rules: [DetectionRule]
    /// Shown on "Not Installed" tiles in place of a version.
    var missingNote: String?

    enum CodingKeys: String, CodingKey {
        case id, name, category, icon, symbol, color, website, rules, missingNote
    }
}

enum ToolStatus: String, Sendable, Codable {
    case ok
    case warn
    case missing

    var label: String {
        switch self {
        case .ok: "Installed"
        case .warn: "Installed · needs attention"
        case .missing: "Not installed"
        }
    }

    var hex: String {
        switch self {
        case .ok: "30d158"
        case .warn: "ff9f0a"
        case .missing: "8e8e93"
        }
    }
}

/// A catalog entry after the scan: found or not, with whatever the probes could read.
struct DetectedTool: Sendable, Identifiable, Equatable {
    /// Unique per tile. A version manager produces one tile per installed version, so the
    /// key carries the version: `lang.ruby@3.3.0`.
    var id: String
    var definition: ToolDefinition
    var status: ToolStatus
    /// Secondary line under the name, e.g. `3.11.6 · pyenv`.
    var subtitle: String
    /// Absolute path on disk, already expanded. `nil` when not installed.
    var path: String?
    /// Which mechanism installed it, shown in the inspector's Managed row.
    var managedBy: String
    /// Directory measured by the size pass. `nil` means the tool has no measurable footprint
    /// of its own (a system binary, or a shim that points elsewhere).
    var measurableRoot: String?
    /// True when `measurableRoot` is a single executable in a shared bin directory rather
    /// than a directory of its own. The measurement is real but partial: it covers the
    /// binary, not the libraries it shares with everything else in that prefix.
    var measuresBinaryOnly: Bool = false
    /// What lives inside this tile — the formulae in the Cellar, the casks in the Caskroom,
    /// the globally installed npm packages. Empty for anything that is not a container.
    var children: [ToolChild] = []

    var name: String { definition.name }
    var category: ToolCategory {
        status == .missing ? .notInstalled : definition.category
    }
}
