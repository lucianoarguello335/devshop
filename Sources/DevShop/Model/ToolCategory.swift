import Foundation

/// The panels of the window, in display order. `notInstalled` is derived: it collects
/// every catalog entry no probe could resolve.
enum ToolCategory: String, Codable, CaseIterable, Sendable, Identifiable {
    case lang
    case pkg
    case brew
    case sdk
    case ide
    case shell
    case notInstalled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lang: "Languages & Runtimes"
        case .pkg: "Package & Version Managers"
        case .brew: "Homebrew"
        case .sdk: "Dev Kits & SDKs"
        case .ide: "IDEs & Dev Tools"
        case .shell: "Shell & Core Tooling"
        case .notInstalled: "Not Installed"
        }
    }

    /// Short name used by the "Largest on disk" card.
    var shortTitle: String {
        switch self {
        case .lang: "Languages"
        case .pkg: "Package managers"
        case .brew: "Homebrew"
        case .sdk: "Dev kits"
        case .ide: "IDEs"
        case .shell: "Shell & core"
        case .notInstalled: "Not installed"
        }
    }

    /// Singular label shown in the inspector's Category row.
    var inspectorLabel: String {
        switch self {
        case .lang: "Language"
        case .pkg: "Package manager"
        case .brew: "Homebrew"
        case .sdk: "Dev kit / SDK"
        case .ide: "IDE / tool"
        case .shell: "Shell & core"
        case .notInstalled: "Not installed"
        }
    }

    /// SF Symbol shown in the sidebar's panel-toggle chip.
    var symbol: String {
        switch self {
        case .lang: "curlybraces"
        case .pkg: "shippingbox.fill"
        case .brew: "mug.fill"
        case .sdk: "cube.fill"
        case .ide: "macwindow"
        case .shell: "terminal.fill"
        case .notInstalled: "circle.dashed"
        }
    }

    /// Series color used by the "Largest on disk" card.
    var accentHex: String {
        switch self {
        case .lang: "f05138"
        case .pkg: "fbb040"
        case .brew: "f59e0b"
        case .sdk: "0a84ff"
        case .ide: "5e5ce6"
        case .shell: "30d158"
        case .notInstalled: "8e8e93"
        }
    }
}
