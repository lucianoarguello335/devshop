import Foundation

/// The "This Mac" card. Everything here is a cheap read — no directory walking.
struct SystemInfo: Sendable, Equatable {
    var modelName: String
    var chip: String
    var memory: String
    var osVersion: String
    var architecture: String
    var totalCapacity: Int64
    var availableCapacity: Int64

    var usedCapacity: Int64 { max(0, totalCapacity - availableCapacity) }

    var hardwareLine: String { modelName }
    var chipLine: String { [chip, memory].filter { !$0.isEmpty }.joined(separator: " · ") }
    var osLine: String { "\(osVersion) · \(architecture)" }

    static let unknown = SystemInfo(
        modelName: "Mac", chip: "", memory: "", osVersion: "macOS",
        architecture: "", totalCapacity: 0, availableCapacity: 0
    )
}
