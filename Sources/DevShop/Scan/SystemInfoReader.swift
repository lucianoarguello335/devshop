import Foundation
import IOKit

/// Fills the "This Mac" card. Every read here is O(1) — no directory is walked.
enum SystemInfoReader {
    static func read() -> SystemInfo {
        let process = ProcessInfo.processInfo
        let os = process.operatingSystemVersion
        let capacity = volumeCapacity()
        return SystemInfo(
            modelName: modelName(),
            chip: chipName(),
            memory: "\(process.physicalMemory / 1_073_741_824) GB",
            osVersion: "macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
            architecture: architecture(),
            totalCapacity: capacity.total,
            availableCapacity: capacity.available
        )
    }

    /// Marketing name from the IORegistry, e.g. "MacBook Pro (16-inch, 2021)".
    private static func modelName() -> String {
        let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                  IOServiceMatching("IOPlatformExpertDevice"))
        defer { if service != 0 { IOObjectRelease(service) } }
        guard service != 0 else { return "Mac" }
        if let data = IORegistryEntryCreateCFProperty(
            service, "product-name" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Data,
           let name = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0")), !name.isEmpty {
            return name
        }
        return sysctlString("hw.model") ?? "Mac"
    }

    /// "Apple M1 Pro" on Apple silicon, the CPU brand string on Intel.
    private static func chipName() -> String {
        sysctlString("machdep.cpu.brand_string") ?? ""
    }

    private static func architecture() -> String {
        #if arch(arm64)
        "arm64"
        #else
        "x86_64"
        #endif
    }

    private static func volumeCapacity() -> (total: Int64, available: Int64) {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        guard let values = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey
        ]) else { return (0, 0) }
        return (Int64(values.volumeTotalCapacity ?? 0),
                values.volumeAvailableCapacityForImportantUsage ?? 0)
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
