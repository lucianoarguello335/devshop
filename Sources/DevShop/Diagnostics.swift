import Foundation

/// A headless dump of what the probes found, for verifying detection without opening a
/// window. Run with `DEVSHOP_DUMP=1 ./DevShop.app/Contents/MacOS/DevShop`.
///
/// Sizes are skipped here — measuring is the expensive pass and belongs to Refresh.
enum Diagnostics {
    static var isRequested: Bool {
        ProcessInfo.processInfo.environment["DEVSHOP_DUMP"] == "1"
    }

    /// `String(format:)` pads by byte, which mangles the "·" separators.
    private static func pad(_ text: String, _ width: Int) -> String {
        text.count >= width ? text + " " : text + String(repeating: " ", count: width - text.count)
    }

    static func run() async {
        let result = await EnvironmentScanner().scan(catalog: Catalog.all)
        let findings = FindingsEngine.evaluate(tools: result.tools,
                                               homebrew: result.homebrew,
                                               config: result.shellConfig)
        let info = SystemInfoReader.read()

        print("\(info.hardwareLine) · \(info.chipLine) · \(info.osLine)")
        print("catalog \(Catalog.all.count) definitions -> \(result.tools.count) tiles")
        print("homebrew: \(result.homebrew.formulaCount) formulae, "
            + "\(result.homebrew.caskCount) casks, "
            + "\(result.homebrew.staleFormulae.count) with old versions")
        print("health \(findings.healthScore) · \(findings.tally)\n")

        for category in ToolCategory.allCases {
            let members = result.tools.filter { $0.category == category }
            guard !members.isEmpty else { continue }
            print("\(category.title) (\(members.count))")
            for tool in members.sorted(by: { $0.name < $1.name }) {
                let path = tool.path.map(Probes.abbreviate) ?? "—"
                print("  " + pad(tool.name, 26) + pad(tool.subtitle, 34) + path)
            }
            print("")
        }

        let config = result.shellConfig
        print("Terminal Config (\(config.meta)) · shell \(config.shell)")
        print("  terminals: " + config.terminals
            .map { "\($0.name) \($0.versionLine)" }.joined(separator: ", "))
        for file in config.filesRead {
            print("  read " + pad(file.file, 34) + "\(file.line) lines · \(file.stage.label)")
        }
        for kind in ConfigEntryKind.allCases {
            let members = config.entries.filter { $0.kind == kind }
            guard !members.isEmpty else { continue }
            print("  \(kind.groupTitle) (\(members.count))")
            for entry in members {
                let marks = (entry.isSecret ? " [secret]" : "")
                    + (entry.isDuplicated ? " [x\(entry.origins.count)]" : "")
                print("     " + pad(entry.name, 30)
                    + pad(String(entry.displayValue.prefix(44)), 46)
                    + (entry.lastOrigin?.location ?? "") + marks)
            }
        }
        if !config.staleFiles.isEmpty { print("  stale: \(config.staleFiles.joined(separator: ", "))") }
        print("")

        print("Contents")
        for tool in result.tools where !tool.children.isEmpty {
            let sources = tool.children.map { child -> String in
                if child.appBundlePath != nil { return "app-icon" }
                return child.iconSlug != nil ? "brand" : "monogram"
            }
            let tally = Dictionary(grouping: sources, by: { $0 })
                .map { "\($0.value.count) \($0.key)" }.sorted().joined(separator: ", ")
            print("  \(tool.name): \(tool.children.count) items — \(tally)")
            for child in tool.children.sorted(by: { $0.name < $1.name }).prefix(6) {
                let icon = child.appBundlePath != nil ? "app-icon"
                    : (child.iconSlug.flatMap { IconStoreProbe.has($0) ? "brand" : nil } ?? "monogram")
                print("     \(pad(child.name, 28))\(pad(child.version, 16))\(icon)")
            }
        }
        print("")

        if ProcessInfo.processInfo.environment["DEVSHOP_DUMP_SETUP"] == "1" {
            let cache = SizeCache.load()
            print(SetupExport.json(.init(tools: result.tools, findings: findings,
                                         homebrew: result.homebrew, system: info,
                                         sizes: cache.bytesByToolID,
                                         measuredAt: cache.measuredAt,
                                         applications: result.applications,
                                         shellConfig: result.shellConfig)))
            return
        }

        if ProcessInfo.processInfo.environment["DEVSHOP_DUMP_PROMPT"] == "1" {
            let cache = SizeCache.load()
            print(FindingsPrompt.build(findings: findings, tools: result.tools,
                                       homebrew: result.homebrew, system: info,
                                       sizes: cache.bytesByToolID,
                                       config: result.shellConfig))
            return
        }

        print("Findings (\(findings.count))")
        for finding in findings {
            print("  [\(finding.tier.label)] \(finding.title)")
            print("      \(finding.detail)")
        }
    }
}
