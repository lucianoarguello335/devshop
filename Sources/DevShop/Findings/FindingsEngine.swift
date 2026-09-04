import Foundation

/// Derives what needs attention from the scan result.
///
/// Every rule is computable offline from what the probes already read — no network call,
/// no `brew outdated`, no version server.
enum FindingsEngine {
    static func evaluate(tools: [DetectedTool],
                         homebrew: EnvironmentScanner.HomebrewSummary,
                         now: Date = .now) -> [Finding] {
        var findings: [Finding] = []
        findings += merge(runtimeEOL(tools: tools, now: now))
        findings += staleHomebrewVersions(tools: tools, homebrew: homebrew)
        findings += shadowedRuntimes(tools: tools)
        findings += duplicateManagedVersions(tools: tools)
        findings += rosettaWithoutIntelDependency(tools: tools)
        findings += xcodeToolchainMismatch(tools: tools)
        findings += noContainerRuntime(tools: tools)
        return findings.sorted { ($0.tier, $0.title) < ($1.tier, $1.title) }
    }

    /// Two installs of the same release line (Ruby 3.3.0 and 3.3.6) describe one problem,
    /// so they collapse into a single row that points at both tiles.
    private static func merge(_ findings: [Finding]) -> [Finding] {
        var order: [String] = []
        var byTitle: [String: Finding] = [:]
        for finding in findings {
            if var existing = byTitle[finding.title] {
                existing.toolIDs += finding.toolIDs
                byTitle[finding.title] = existing
            } else {
                order.append(finding.title)
                byTitle[finding.title] = finding
            }
        }
        return order.compactMap { byTitle[$0] }
    }

    // MARK: - Rules

    /// A runtime whose support window closes within a year, or has already closed.
    private static func runtimeEOL(tools: [DetectedTool], now: Date) -> [Finding] {
        var out: [Finding] = []
        for tool in tools where tool.status != .missing {
            let numbers = EOLTable.numbers(in: tool.subtitle)
            guard let major = numbers.first else { continue }

            var deadline: DateComponents?
            var line = ""
            switch tool.definition.id {
            case "lang.node":
                deadline = EOLTable.node[major]
                line = "Node.js \(major)"
            case "lang.python":
                guard numbers.count > 1 else { continue }
                let key = "\(major).\(numbers[1])"
                deadline = EOLTable.python[key]
                line = "Python \(key)"
            case "lang.ruby":
                guard numbers.count > 1 else { continue }
                let key = "\(major).\(numbers[1])"
                deadline = EOLTable.ruby[key]
                line = "Ruby \(key)"
            default:
                continue
            }
            guard let deadline, let months = EOLTable.monthsUntil(deadline, from: now) else { continue }

            if months < 0 {
                out.append(Finding(
                    id: "eol.\(line)",
                    tier: .error,
                    title: "\(line) is past end of life",
                    detail: "Security support ended \(-months) month\(-months == 1 ? "" : "s") ago. "
                          + "Managed by \(tool.managedBy) — a newer line can be installed alongside.",
                    scope: "\(tool.definition.category.title) · \(tool.name)",
                    toolIDs: [tool.id]))
            } else if months <= 12 {
                out.append(Finding(
                    id: "eol.\(line)",
                    tier: months <= 3 ? .error : .warning,
                    title: "\(line) reaches end of life in \(months) month\(months == 1 ? "" : "s")",
                    detail: "Managed by \(tool.managedBy) — a newer line can be installed alongside.",
                    scope: "\(tool.definition.category.title) · \(tool.name)",
                    toolIDs: [tool.id]))
            }
        }
        return out
    }

    /// Old Cellar version directories that `brew cleanup` would reclaim.
    private static func staleHomebrewVersions(
        tools: [DetectedTool],
        homebrew: EnvironmentScanner.HomebrewSummary
    ) -> [Finding] {
        guard homebrew.staleFormulae.count > 1 else { return [] }
        let names = homebrew.staleFormulae.prefix(3).joined(separator: ", ")
        let more = homebrew.staleFormulae.count > 3 ? " and \(homebrew.staleFormulae.count - 3) more" : ""
        return [Finding(
            id: "brew.stale",
            tier: .warning,
            title: "\(homebrew.staleFormulae.count) Homebrew formulae keep old versions",
            detail: "\(names)\(more) each have more than one version directory in the Cellar. "
                  + "`brew cleanup` reclaims the older copies.",
            scope: "Homebrew · Formulae",
            toolIDs: tools.filter { $0.definition.id == "brew.formulae" }.map(\.id))]
    }

    /// The same runtime installed by two mechanisms, where PATH order decides which wins.
    private static func shadowedRuntimes(tools: [DetectedTool]) -> [Finding] {
        var out: [Finding] = []
        let pairs: [(runtime: String, manager: String, name: String)] = [
            ("lang.node", "pkg.nvm", "Node.js"),
            ("lang.python", "pkg.pyenv", "Python"),
            ("lang.ruby", "pkg.rbenv", "Ruby")
        ]
        for pair in pairs {
            let managed = tools.filter { $0.definition.id == pair.runtime && $0.status != .missing }
            let hasManager = tools.contains { $0.definition.id == pair.manager && $0.status != .missing }
            let brewCopy = managed.first { $0.managedBy.hasPrefix("Homebrew") }
            guard hasManager, let brewCopy, managed.count > 1 else { continue }
            out.append(Finding(
                id: "shadow.\(pair.runtime)",
                tier: .warning,
                title: "\(pair.name) is installed twice",
                detail: "A Homebrew copy sits alongside the version-managed one. "
                      + "Whichever bin directory comes first on PATH silently wins.",
                scope: "Languages & Runtimes · \(pair.name)",
                toolIDs: managed.map(\.id) + [brewCopy.id]))
        }
        return out
    }

    /// Several versions kept under one version manager.
    private static func duplicateManagedVersions(tools: [DetectedTool]) -> [Finding] {
        var byDefinition: [String: [DetectedTool]] = [:]
        for tool in tools where tool.status != .missing && tool.id.contains("@") {
            byDefinition[tool.definition.id, default: []].append(tool)
        }
        return byDefinition.compactMap { _, group in
            guard group.count >= 3, let first = group.first else { return nil }
            let versions = group.map { $0.subtitle.split(separator: " ").first.map(String.init) ?? "" }
            return Finding(
                id: "dupes.\(first.definition.id)",
                tier: .info,
                title: "\(group.count) \(first.name) versions installed",
                detail: "\(versions.joined(separator: ", ")) are all present. "
                      + "Older lines can be removed once no project pins them.",
                scope: "\(first.definition.category.title) · \(first.name)",
                toolIDs: group.map(\.id))
        }
    }

    /// Rosetta with nothing left that needs it.
    private static func rosettaWithoutIntelDependency(tools: [DetectedTool]) -> [Finding] {
        guard let rosetta = tools.first(where: { $0.definition.id == "shell.rosetta" }),
              rosetta.status != .missing else { return [] }
        return [Finding(
            id: "rosetta",
            tier: .info,
            title: "Rosetta 2 is still installed",
            detail: "x86_64 translation stays on disk once installed. Some casks still need it, "
                  + "so removing it is only safe when nothing Intel-only is left.",
            scope: "Shell & Core Tooling · Rosetta 2",
            toolIDs: [rosetta.id])]
    }

    /// Xcode present without Command Line Tools, or the two on different major versions.
    private static func xcodeToolchainMismatch(tools: [DetectedTool]) -> [Finding] {
        let xcode = tools.first { $0.definition.id == "sdk.xcode" && $0.status != .missing }
        let clt = tools.first { $0.definition.id == "sdk.clt" && $0.status != .missing }
        guard let xcode else { return [] }
        guard let clt else {
            return [Finding(
                id: "clt.missing",
                tier: .warning,
                title: "Command Line Tools are not installed",
                detail: "Xcode is present but /Library/Developer/CommandLineTools is missing. "
                      + "Tools that shell out to clang or git outside Xcode will not find them.",
                scope: "Dev Kits & SDKs · Command Line Tools",
                toolIDs: [xcode.id])]
        }
        let xcodeMajor = EOLTable.numbers(in: xcode.subtitle).first
        let cltMajor = EOLTable.numbers(in: clt.subtitle).first
        guard let xcodeMajor, let cltMajor, xcodeMajor != cltMajor else { return [] }
        return [Finding(
            id: "clt.mismatch",
            tier: .warning,
            title: "Command Line Tools are a different major version to Xcode",
            detail: "Xcode is \(xcodeMajor).x and the Command Line Tools are \(cltMajor).x. "
                  + "Builds outside Xcode may use an older clang than the IDE does.",
            scope: "Dev Kits & SDKs · Command Line Tools",
            toolIDs: [xcode.id, clt.id])]
    }

    /// No way to run a container.
    private static func noContainerRuntime(tools: [DetectedTool]) -> [Finding] {
        let runtimes = ["ide.docker", "ide.orbstack", "ide.podman", "ide.colima"]
        let installed = tools.filter { runtimes.contains($0.definition.id) && $0.status != .missing }
        guard installed.isEmpty else { return [] }
        return [Finding(
            id: "containers.none",
            tier: .info,
            title: "No container runtime is installed",
            detail: "Docker Desktop, OrbStack, Podman and Colima are all absent. "
                  + "Anything with a Dockerfile or a devcontainer will not run locally.",
            scope: "IDEs & Dev Tools · Containers",
            toolIDs: tools.filter { runtimes.contains($0.definition.id) }.map(\.id))]
    }
}

private func < (a: (FindingTier, String), b: (FindingTier, String)) -> Bool {
    a.0 == b.0 ? a.1 < b.1 : a.0 < b.0
}
