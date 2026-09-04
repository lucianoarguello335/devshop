import Foundation

/// End-of-life dates for the runtime lines DevShop tracks.
///
/// Bundled deliberately: the app makes no network requests, so this table is the honest
/// source. Refresh it when the release schedules move.
enum EOLTable {
    /// major version -> end of security support
    static let node: [Int: DateComponents] = [
        18: .init(year: 2025, month: 4), 20: .init(year: 2026, month: 4),
        22: .init(year: 2027, month: 4), 24: .init(year: 2028, month: 4)
    ]
    static let python: [String: DateComponents] = [
        "3.8": .init(year: 2024, month: 10), "3.9": .init(year: 2025, month: 10),
        "3.10": .init(year: 2026, month: 10), "3.11": .init(year: 2027, month: 10),
        "3.12": .init(year: 2028, month: 10), "3.13": .init(year: 2029, month: 10)
    ]
    static let ruby: [String: DateComponents] = [
        "3.0": .init(year: 2024, month: 4), "3.1": .init(year: 2025, month: 3),
        "3.2": .init(year: 2026, month: 3), "3.3": .init(year: 2027, month: 3)
    ]

    /// Months from now until `components`, or `nil` when the date is unknown.
    static func monthsUntil(_ components: DateComponents, from now: Date = .now) -> Int? {
        var c = components
        c.day = c.day ?? 1
        guard let date = Calendar.current.date(from: c) else { return nil }
        return Calendar.current.dateComponents([.month], from: now, to: date).month
    }

    /// Leading numeric components of a version string: "v22.19.0 · nvm" -> [22, 19, 0].
    static func numbers(in text: String) -> [Int] {
        let scalars = text.drop { !$0.isNumber }
        let head = scalars.prefix { $0.isNumber || $0 == "." }
        return head.split(separator: ".").compactMap { Int($0) }
    }
}
