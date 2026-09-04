import Foundation

/// How healthy the environment is, derived from the score.
///
/// The label and the ring colour both come from this one place, so the caption can never
/// contradict what the ring is showing — the ring used to be hardcoded green while the text
/// underneath read "Needs attention".
enum HealthStatus: Sendable, CaseIterable {
    case healthy
    case mostlyHealthy
    case needsAttention
    case problems

    init(score: Int) {
        switch score {
        case 90...: self = .healthy
        case 70..<90: self = .mostlyHealthy
        case 50..<70: self = .needsAttention
        default: self = .problems
        }
    }

    var label: String {
        switch self {
        case .healthy: "Healthy"
        case .mostlyHealthy: "Mostly healthy"
        case .needsAttention: "Needs attention"
        case .problems: "Problems found"
        }
    }

    /// The same green / yellow / orange / red the findings use, so the ring reads with the
    /// severity language already established elsewhere in the window.
    var hex: String {
        switch self {
        case .healthy: "30d158"
        case .mostlyHealthy: "ffd60a"
        case .needsAttention: "ff9f0a"
        case .problems: "ff453a"
        }
    }
}
