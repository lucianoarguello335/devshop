import Foundation

/// Measures how much disk each detected tool occupies.
///
/// This is the only expensive thing DevShop does, so it runs on demand — the first launch
/// and then every time the user presses Refresh. Roots are walked concurrently and results
/// stream back one at a time, which is what lets the bars fill in progressively instead of
/// appearing all at once at the end.
actor SizeMeasurer {
    struct Measurement: Sendable, Equatable {
        var toolID: String
        /// Allocated bytes on disk.
        var bytes: Int64
    }

    /// Emits one measurement per tool, in completion order.
    func measure(_ tools: [DetectedTool]) -> AsyncStream<Measurement> {
        let jobs = Self.jobs(in: tools)
        return AsyncStream { continuation in
            let task = Task.detached(priority: .utility) {
                await withTaskGroup(of: (ids: [String], bytes: Int64)?.self) { group in
                    // Bounded concurrency: more than this and the walkers contend for I/O.
                    let limit = 6
                    var index = 0
                    func addNext(_ group: inout TaskGroup<(ids: [String], bytes: Int64)?>) {
                        guard index < jobs.count else { return }
                        let job = jobs[index]
                        index += 1
                        group.addTask {
                            guard !Task.isCancelled else { return nil }
                            return (job.ids, Self.allocatedSize(ofDirectory: job.path))
                        }
                    }
                    for _ in 0..<min(limit, jobs.count) { addNext(&group) }
                    for await result in group {
                        if let result {
                            for id in result.ids {
                                continuation.yield(Measurement(toolID: id, bytes: result.bytes))
                            }
                        }
                        addNext(&group)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// One walk per distinct directory, carrying every id that wants its result.
    ///
    /// The same path is reachable from more than one tile — the Homebrew tile lists all the
    /// formulae and casks, and the Formulae and Casks tiles list them again — so walking
    /// per id measured about 40% of the Cellar twice. Grouping by path removes that without
    /// changing what any tile displays.
    private static func jobs(in tools: [DetectedTool]) -> [(path: String, ids: [String])] {
        var order: [String] = []
        var idsByPath: [String: [String]] = [:]

        func add(id: String, path: String) {
            if idsByPath[path] == nil {
                idsByPath[path] = []
                order.append(path)
            }
            idsByPath[path]?.append(id)
        }

        for tool in tools {
            if let root = tool.measurableRoot { add(id: tool.id, path: root) }
            for child in tool.children { add(id: child.id, path: child.path) }
        }
        return order.map { ($0, idsByPath[$0] ?? []) }
    }

    /// Recursive allocated size. Uses `totalFileAllocatedSize`, which is what Finder
    /// reports, and stays on one volume so a mounted image under a scanned directory is
    /// not counted.
    nonisolated static func allocatedSize(ofDirectory path: String) -> Int64 {
        let url = URL(fileURLWithPath: path)
        let keys: Set<URLResourceKey> = [
            .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
            .isRegularFileKey, .isDirectoryKey, .volumeIdentifierKey
        ]

        guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
        if values.isRegularFile == true {
            return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        guard values.isDirectory == true else { return 0 }

        let rootVolume = values.volumeIdentifier
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsPackageDescendants],
            errorHandler: { _, _ in true }   // unreadable entries are skipped, not fatal
        ) else { return 0 }

        var total: Int64 = 0
        var checkedCancellation = 0
        for case let child as URL in enumerator {
            checkedCancellation += 1
            if checkedCancellation % 512 == 0, Task.isCancelled { return total }
            guard let v = try? child.resourceValues(forKeys: keys) else { continue }
            if let volume = v.volumeIdentifier, let rootVolume,
               !volume.isEqual(rootVolume) {
                enumerator.skipDescendants()
                continue
            }
            if v.isRegularFile == true {
                total += Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
            }
        }
        return total
    }
}

// MARK: - Formatting

enum ByteFormat {
    /// Compact form used on tiles and bars: `466M`, `7.5G`.
    static func compact(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_000_000_000
        if gb >= 1 { return String(format: "%.1fG", gb) }
        let mb = Double(bytes) / 1_000_000
        if mb >= 1 { return "\(Int(mb.rounded()))M" }
        let kb = Double(bytes) / 1_000
        if kb >= 1 { return "\(Int(kb.rounded()))K" }
        return "0B"
    }

    /// Long form used by the inspector: `466 MB`, `7.50 GB`, `45 KB`.
    static func full(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_000_000_000
        if gb >= 1 { return String(format: "%.2f GB", gb) }
        let mb = Double(bytes) / 1_000_000
        if mb >= 1 { return "\(Int(mb.rounded())) MB" }
        let kb = Double(bytes) / 1_000
        if kb >= 1 { return "\(Int(kb.rounded())) KB" }
        return "\(bytes) bytes"
    }
}
