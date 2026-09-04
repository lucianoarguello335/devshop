import Foundation

/// Persists the last size measurement so launch is instant.
///
/// Sizes only change when the user asks for them, so the cache is the source of truth
/// between refreshes and `measuredAt` drives the "Last fetch N min ago" label.
struct SizeCache: Codable, Sendable {
    var measuredAt: Date
    var bytesByToolID: [String: Int64]

    static let empty = SizeCache(measuredAt: .distantPast, bytesByToolID: [:])

    var isEmpty: Bool { bytesByToolID.isEmpty }

    static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("DevShop/sizes.json")
    }

    static func load() -> SizeCache {
        guard let data = try? Data(contentsOf: fileURL),
              let cache = try? JSONDecoder().decode(SizeCache.self, from: data) else {
            return .empty
        }
        return cache
    }

    func save() {
        let url = Self.fileURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
