import Foundation

/// A machine-readable snapshot of everything the scan found.
///
/// Exports the complete scan rather than what happens to be on screen, so the file means the
/// same thing regardless of the search field or which panels were toggled off when it was
/// copied. Keys are sorted and the output is indented so two exports — from different
/// machines, or the same machine months apart — diff cleanly.
enum SetupExport {
    static let schemaVersion = 1

    // MARK: - Shape

    struct Document: Encodable {
        var schemaVersion: Int
        var exportedAt: Date
        var machine: Machine
        var summary: Summary
        var categories: [Category]
        var findings: [Finding]
        /// Every bundle in /Applications, whether or not DevShop recognises it as a dev
        /// tool. Sizes are omitted — measuring them would stall the export.
        var applications: [Application]
        /// What the login shell loads at startup. Secret values are exported masked, never
        /// raw — an export is the most likely thing to be pasted somewhere public.
        var terminalConfig: TerminalConfig
    }

    struct TerminalConfig: Encodable {
        var shell: String
        var files: [File]
        var entries: [Entry]
        var terminals: [Terminal]
        var staleFiles: [String]
        var writableFiles: [String]

        struct File: Encodable {
            var path: String
            var lines: Int
            var stage: String
        }

        struct Entry: Encodable {
            var id: String
            var kind: String
            var name: String
            var value: String
            var isSecret: Bool
            var declaredIn: [String]
        }

        struct Terminal: Encodable {
            var name: String
            var version: String?
            var build: String?
            var bundleIdentifier: String
            var path: String
            var configPaths: [String]
        }
    }

    struct Machine: Encodable {
        var model: String
        var chip: String
        var memory: String
        var os: String
        var architecture: String
        var diskTotalBytes: Int64
        var diskUsedBytes: Int64
        var diskFreeBytes: Int64
    }

    struct Summary: Encodable {
        var healthScore: Int
        var healthStatus: String
        var toolsInstalled: Int
        var toolsMissing: Int
        var applicationCount: Int
        /// Excludes what macOS ships with, which is the number worth comparing.
        var applicationsInstalled: Int
        var developmentBytes: Int64
        /// `nil` when sizes have never been measured, which is why every `sizeBytes` would
        /// read zero.
        var sizesMeasuredAt: Date?
        var homebrew: Homebrew
        var categoryBytes: [String: Int64]
    }

    struct Homebrew: Encodable {
        var installed: Bool
        var formulae: Int
        var casks: Int
        var formulaeKeepingOldVersions: [String]
    }

    struct Category: Encodable {
        var id: String
        var title: String
        var toolCount: Int
        var totalBytes: Int64
        var tools: [Tool]
    }

    struct Tool: Encodable {
        var id: String
        var name: String
        var status: String
        var version: String
        var path: String?
        var managedBy: String
        var sizeBytes: Int64
        var website: String?
        var contents: [Item]?
    }

    struct Item: Encodable {
        var id: String
        var name: String
        var version: String
        var path: String
        var sizeBytes: Int64
    }

    struct Application: Encodable {
        var name: String
        var version: String?
        var build: String?
        var bundleIdentifier: String?
        var path: String
        var modifiedAt: Date?
        var source: String
    }

    struct Finding: Encodable {
        var id: String
        var tier: String
        var title: String
        var detail: String
        var scope: String
        var toolIDs: [String]
    }

    // MARK: - Building

    struct Input {
        var tools: [DetectedTool]
        var findings: [DevShop.Finding]
        var homebrew: EnvironmentScanner.HomebrewSummary
        var system: SystemInfo
        var sizes: [String: Int64]
        var measuredAt: Date
        var applications: [InstalledApplication]
        var shellConfig: ShellConfigSnapshot = .empty
    }

    static func json(_ input: Input, now: Date = .now) -> String {
        let document = document(input, now: now)
        let encoder = JSONEncoder()
        // Sorted keys and indentation make the file diffable; unescaped slashes keep the
        // paths readable, which is most of what anyone reads this for.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(document),
              let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }

    private static func document(_ input: Input, now: Date) -> Document {
        func bytes(_ id: String) -> Int64 { input.sizes[id] ?? 0 }

        let categories = ToolCategory.allCases.compactMap { category -> Category? in
            let members = input.tools
                .filter { $0.category == category }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            guard !members.isEmpty else { return nil }

            let tools = members.map { tool in
                let contents = tool.children
                    .sorted { bytes($0.id) == bytes($1.id)
                        ? $0.name.localizedStandardCompare($1.name) == .orderedAscending
                        : bytes($0.id) > bytes($1.id) }
                    .map { child in
                        Item(id: child.id,
                             name: child.name,
                             version: child.version,
                             path: Probes.abbreviate(child.path),
                             sizeBytes: bytes(child.id))
                    }
                return Tool(id: tool.id,
                            name: tool.name,
                            status: tool.status.rawValue,
                            version: tool.version ?? tool.subtitle,
                            path: tool.path.map(Probes.abbreviate),
                            managedBy: tool.managedBy,
                            sizeBytes: bytes(tool.id),
                            website: tool.definition.website,
                            contents: contents.isEmpty ? nil : contents)
            }
            return Category(id: category.rawValue,
                            title: category.title,
                            toolCount: tools.count,
                            totalBytes: tools.reduce(0) { $0 + $1.sizeBytes },
                            tools: tools)
        }

        var categoryBytes: [String: Int64] = [:]
        for category in categories { categoryBytes[category.id] = category.totalBytes }

        let summary = Summary(
            healthScore: input.findings.healthScore,
            healthStatus: String(describing: HealthStatus(score: input.findings.healthScore)),
            toolsInstalled: input.tools.count { $0.status != .missing },
            toolsMissing: input.tools.count { $0.status == .missing },
            applicationCount: input.applications.count,
            applicationsInstalled: input.applications.count { $0.source == .user },
            developmentBytes: input.sizes.values.reduce(0, +),
            sizesMeasuredAt: input.measuredAt == .distantPast ? nil : input.measuredAt,
            homebrew: Homebrew(installed: input.homebrew.isInstalled,
                               formulae: input.homebrew.formulaCount,
                               casks: input.homebrew.caskCount,
                               formulaeKeepingOldVersions: input.homebrew.staleFormulae),
            categoryBytes: categoryBytes
        )

        return Document(
            schemaVersion: schemaVersion,
            exportedAt: now,
            machine: Machine(model: input.system.modelName,
                             chip: input.system.chip,
                             memory: input.system.memory,
                             os: input.system.osVersion,
                             architecture: input.system.architecture,
                             diskTotalBytes: input.system.totalCapacity,
                             diskUsedBytes: input.system.usedCapacity,
                             diskFreeBytes: input.system.availableCapacity),
            summary: summary,
            categories: categories,
            findings: input.findings.map {
                Finding(id: $0.id, tier: $0.tier.rawValue, title: $0.title,
                        detail: $0.detail, scope: $0.scope, toolIDs: $0.toolIDs)
            },
            applications: input.applications.map {
                Application(name: $0.name, version: $0.version, build: $0.build,
                            bundleIdentifier: $0.bundleIdentifier, path: $0.path,
                            modifiedAt: $0.modifiedAt, source: $0.source.rawValue)
            },
            terminalConfig: terminalConfig(input.shellConfig)
        )
    }

    private static func terminalConfig(_ config: ShellConfigSnapshot) -> TerminalConfig {
        TerminalConfig(
            shell: config.shell,
            files: config.filesRead.map {
                .init(path: $0.file, lines: $0.line, stage: $0.stage.label)
            },
            entries: config.entries.map {
                // `displayValue`, never `rawValue`: a masked secret stays masked here. An
                // export is the most likely thing to be pasted into an issue or a chat.
                .init(id: $0.id,
                      kind: $0.kind.rawValue,
                      name: $0.name,
                      value: $0.displayValue,
                      isSecret: $0.isSecret,
                      declaredIn: $0.origins.map(\.location))
            },
            terminals: config.terminals.map {
                .init(name: $0.name, version: $0.version, build: $0.build,
                      bundleIdentifier: $0.bundleIdentifier, path: $0.path,
                      configPaths: $0.configPaths)
            },
            staleFiles: config.staleFiles,
            writableFiles: config.writableFiles)
    }
}
