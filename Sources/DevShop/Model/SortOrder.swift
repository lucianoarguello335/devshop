import Foundation

/// Column the centre list is ordered by. The grid uses the same ordering, so switching
/// views never reshuffles anything.
enum SortField: String, Sendable, CaseIterable, Identifiable {
    case name, version, location, managedBy, size

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: "Name"
        case .version: "Version"
        case .location: "Location"
        case .managedBy: "Managed by"
        case .size: "Size"
        }
    }
}

struct ToolSort: Sendable, Equatable {
    var field: SortField = .name
    var ascending: Bool = true

    /// Clicking the active column flips it; clicking another switches to it. Size starts
    /// descending, because "biggest first" is what anyone asking about size wants.
    mutating func toggle(_ field: SortField) {
        if self.field == field {
            ascending.toggle()
        } else {
            self.field = field
            ascending = field != .size
        }
    }

    func compare(_ a: DetectedTool, _ b: DetectedTool, bytes: (DetectedTool) -> Int64) -> Bool {
        let result: Bool
        switch field {
        case .name:
            result = a.name.localizedStandardCompare(b.name) == .orderedAscending
        case .version:
            // Sort by what the column shows. Tools with no readable version sort last in
            // ascending order rather than mixing in among the numbers.
            let x = a.version, y = b.version
            switch (x, y) {
            case (nil, nil): result = a.name.localizedStandardCompare(b.name) == .orderedAscending
            case (nil, _): result = false
            case (_, nil): result = true
            case let (x?, y?): result = x.localizedStandardCompare(y) == .orderedAscending
            }
        case .location:
            result = (a.path ?? "").localizedStandardCompare(b.path ?? "") == .orderedAscending
        case .managedBy:
            result = a.managedBy.localizedStandardCompare(b.managedBy) == .orderedAscending
        case .size:
            let x = bytes(a), y = bytes(b)
            // Ties fall back to the name so the order is stable between refreshes.
            result = x == y
                ? a.name.localizedStandardCompare(b.name) == .orderedAscending
                : x < y
        }
        return ascending ? result : !result
    }

    /// The same ordering applied to what is inside a container tile, so the inspector's
    /// Contents list agrees with the column header the user clicked. A child has no
    /// "managed by" of its own — it is whatever installed the parent — so that column
    /// falls back to the name.
    func compare(_ a: ToolChild, _ b: ToolChild, bytes: (ToolChild) -> Int64) -> Bool {
        let byName = a.name.localizedStandardCompare(b.name) == .orderedAscending
        let result: Bool
        switch field {
        case .name, .managedBy:
            result = byName
        case .version:
            // A child's version is never nil, but it can be empty or a placeholder like
            // "tap". Empty sorts last in ascending order, matching the tool rule above.
            switch (a.version.isEmpty, b.version.isEmpty) {
            case (true, true): result = byName
            case (true, false): result = false
            case (false, true): result = true
            case (false, false):
                result = a.version.localizedStandardCompare(b.version) == .orderedAscending
            }
        case .location:
            result = a.path.localizedStandardCompare(b.path) == .orderedAscending
        case .size:
            let x = bytes(a), y = bytes(b)
            result = x == y ? byName : x < y
        }
        return ascending ? result : !result
    }
}

/// How the centre column draws its tools.
enum ContentLayout: String, Sendable, CaseIterable {
    case grid, list

    var symbol: String {
        switch self {
        case .grid: "square.grid.2x2"
        case .list: "list.bullet"
        }
    }

    var label: String {
        switch self {
        case .grid: "Grid view"
        case .list: "List view"
        }
    }
}
