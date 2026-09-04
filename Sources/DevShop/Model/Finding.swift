import Foundation

enum FindingTier: String, Sendable, Codable, Comparable {
    case error, warning, info

    var label: String {
        switch self {
        case .error: "Error"
        case .warning: "Warning"
        case .info: "Info"
        }
    }

    var hex: String {
        switch self {
        case .error: "ff453a"
        case .warning: "ff9f0a"
        case .info: "0a84ff"
        }
    }

    /// Badge shown beside a tool's name. Each tier gets its own shape as well as its own
    /// colour, so the severity is legible without relying on colour perception.
    var badgeSymbol: String {
        switch self {
        case .error: "exclamationmark.octagon.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .info: "info.circle.fill"
        }
    }

    /// Points subtracted from the health score.
    var penalty: Int {
        switch self {
        case .error: 15
        case .warning: 5
        case .info: 1
        }
    }

    private var order: Int {
        switch self {
        case .error: 0
        case .warning: 1
        case .info: 2
        }
    }

    static func < (a: FindingTier, b: FindingTier) -> Bool { a.order < b.order }
}

struct Finding: Sendable, Identifiable, Equatable {
    var id: String
    var tier: FindingTier
    var title: String
    var detail: String
    /// Breadcrumb, e.g. `Languages & Runtimes · Node.js`.
    var scope: String
    /// Ids of the `DetectedTool`s this finding belongs to, so the inspector can filter.
    var toolIDs: [String]
}

extension Array where Element == Finding {
    /// "1 error · 2 warnings · 1 note" — the summary the design uses in three places.
    var tally: String {
        let counts: [(Int, String, String)] = [
            (filter { $0.tier == .error }.count, "error", "errors"),
            (filter { $0.tier == .warning }.count, "warning", "warnings"),
            (filter { $0.tier == .info }.count, "note", "notes")
        ]
        let parts = counts.filter { $0.0 > 0 }.map { "\($0.0) \($0.0 == 1 ? $0.1 : $0.2)" }
        return parts.isEmpty ? "nothing needs attention" : parts.joined(separator: " · ")
    }

    /// 100 minus the weighted penalties, clamped to 0...100.
    var healthScore: Int {
        Swift.max(0, Swift.min(100, 100 - reduce(0) { $0 + $1.tier.penalty }))
    }
}
