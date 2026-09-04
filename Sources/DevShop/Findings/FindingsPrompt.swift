import Foundation

/// Builds a briefing an AI agent can act on to fix what the scan found.
///
/// The value is in the specifics: an agent given "Ruby is out of date" guesses, while one
/// given the exact version, its path, the manager that owns it and what else is installed
/// alongside can reason about blast radius. So every finding carries the tools it points at,
/// and the machine and toolchain context are stated up front.
///
/// DevShop never changes anything itself, so the prompt asks for commands rather than
/// actions and insists on verification and rollback for each one.
enum FindingsPrompt {
    static func build(findings: [Finding],
                      tools: [DetectedTool],
                      homebrew: EnvironmentScanner.HomebrewSummary,
                      system: SystemInfo,
                      sizes: [String: Int64],
                      now: Date = .now) -> String {
        var out: [String] = []
        out.append(header(findings: findings, now: now))
        out.append(machine(system))
        out.append(toolchain(tools: tools, homebrew: homebrew))
        out.append(findingsSection(findings, tools: tools, sizes: sizes))
        out.append(request(findings: findings))
        out.append(constraints())
        return out.joined(separator: "\n\n")
    }

    // MARK: - Sections

    private static func header(findings: [Finding], now: Date) -> String {
        """
        # Diagnose and fix my macOS development environment

        You are helping me repair issues on my Mac's development environment. The findings \
        below were produced by DevShop, a read-only scanner that inspects the filesystem \
        directly — it reads Homebrew's Cellar and Caskroom, application bundles, and the \
        version directories under nvm, pyenv and rbenv. It never runs package managers and \
        never changes anything, so treat every finding as an observation, not an action \
        already taken.

        Scan taken \(now.formatted(date: .abbreviated, time: .shortened)). \
        \(findings.count) finding\(findings.count == 1 ? "" : "s"): \(findings.tally).
        """
    }

    private static func machine(_ system: SystemInfo) -> String {
        var lines = ["## Machine"]
        lines.append("- \(system.hardwareLine)")
        if !system.chipLine.isEmpty { lines.append("- \(system.chipLine)") }
        lines.append("- \(system.osLine)")
        if system.totalCapacity > 0 {
            lines.append("- Disk: \(ByteFormat.full(system.usedCapacity)) used, "
                       + "\(ByteFormat.full(system.availableCapacity)) free")
        }
        return lines.joined(separator: "\n")
    }

    /// What manages what. An agent proposing `brew upgrade` needs to know a runtime is
    /// actually owned by rbenv, and that three versions of it are installed side by side.
    private static func toolchain(tools: [DetectedTool],
                                  homebrew: EnvironmentScanner.HomebrewSummary) -> String {
        var lines = ["## Toolchain and how it is managed"]
        if homebrew.isInstalled {
            lines.append("- Homebrew: \(homebrew.formulaCount) formulae, "
                       + "\(homebrew.caskCount) casks")
            if !homebrew.staleFormulae.isEmpty {
                lines.append("  - \(homebrew.staleFormulae.count) formulae keep more than one "
                           + "version directory: \(homebrew.staleFormulae.prefix(10).joined(separator: ", "))")
            }
        }

        // Runtimes that exist more than once are the usual source of "it works in one shell
        // but not another", so they are spelled out rather than summarised.
        let installed = tools.filter { $0.status != .missing }
        let grouped = Dictionary(grouping: installed) { $0.definition.id }
        for (_, group) in grouped.sorted(by: { $0.key < $1.key }) where group.count > 1 {
            guard let first = group.first else { continue }
            let versions = group.map { "\($0.subtitle) at \(Probes.abbreviate($0.path ?? "—"))" }
            lines.append("- \(first.name) is installed \(group.count) times:")
            lines += versions.map { "  - \($0)" }
        }

        let managers = installed
            .filter { $0.definition.category == .pkg }
            .map { "\($0.name) (\($0.subtitle))" }
            .sorted()
        if !managers.isEmpty {
            lines.append("- Package and version managers present: \(managers.joined(separator: ", "))")
        }

        let missingNotable = tools
            .filter { $0.status == .missing }
            .map(\.name)
            .sorted()
            .prefix(12)
        if !missingNotable.isEmpty {
            lines.append("- Not installed (relevant if a fix suggests one): "
                       + missingNotable.joined(separator: ", "))
        }
        return lines.joined(separator: "\n")
    }

    private static func findingsSection(_ findings: [Finding],
                                        tools: [DetectedTool],
                                        sizes: [String: Int64]) -> String {
        var lines = ["## Findings"]
        for (index, finding) in findings.enumerated() {
            lines.append("")
            lines.append("### \(index + 1). [\(finding.tier.label.uppercased())] \(finding.title)")
            lines.append("- Area: \(finding.scope)")
            lines.append("- What the scanner saw: \(finding.detail)")

            let affected = finding.toolIDs.compactMap { id in
                tools.first { $0.id == id }
            }
            if affected.isEmpty { continue }
            lines.append("- Affected:")
            for tool in affected {
                var parts = ["\(tool.name) — \(tool.subtitle)"]
                if let path = tool.path { parts.append("at `\(Probes.abbreviate(path))`") }
                parts.append("managed by \(tool.managedBy)")
                if let bytes = sizes[tool.id], bytes > 0 {
                    parts.append("using \(ByteFormat.full(bytes))")
                }
                lines.append("  - \(parts.joined(separator: ", "))")

                // Contents matter for containers: "clean up Homebrew" is meaningless without
                // knowing which packages are actually big.
                let heaviest = tool.children
                    .filter { (sizes[$0.id] ?? 0) > 0 }
                    .sorted { (sizes[$0.id] ?? 0) > (sizes[$1.id] ?? 0) }
                    .prefix(5)
                for child in heaviest {
                    lines.append("    - contains \(child.name) \(child.version) "
                               + "(\(ByteFormat.full(sizes[child.id] ?? 0)))")
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func request(findings: [Finding]) -> String {
        let errors = findings.filter { $0.tier == .error }.count
        let urgency = errors > 0
            ? "Start with the \(errors) error\(errors == 1 ? "" : "s") — those are the ones "
            + "already causing a problem rather than warning about a future one."
            : "Nothing here is urgent, so optimise the order for least disruption."

        return """
        ## What I need from you

        \(urgency)

        For **each** finding above, work through:

        1. **Root cause** — what actually produced this state, not just a restatement of the \
        finding. If the scanner's reading could be a false positive, say so and tell me how \
        to confirm it.
        2. **Risk of fixing** — what could break, which projects or shells would notice, and \
        whether anything else depends on the current state.
        3. **Risk of leaving it** — be concrete about the consequence and the timescale. If \
        the honest answer is "almost none", say that instead of manufacturing urgency.
        4. **Blast radius** — global vs per-project, reversible vs not, and whether it \
        touches anything outside my home directory.

        Then give me:

        - An **ordered plan** across all findings, grouped so I can do it in one sitting, \
        with anything that must happen before something else called out explicitly.
        - **Exact commands** for each step, copy-pasteable, with the working directory when \
        it matters. No placeholders I have to guess at.
        - A **verification step** per fix — the specific command and the output that proves \
        it worked.
        - A **rollback** per fix, or an explicit note that a step cannot be undone.
        - Anything I should **back up or note down first**, especially version numbers that \
        projects may pin.

        Finally, tell me which findings you would **deliberately skip**, and why. I would \
        rather leave something alone than churn my environment for a marginal gain.
        """
    }

    private static func constraints() -> String {
        """
        ## Constraints

        - Do not assume you can run anything. Give me commands and I will run them.
        - Flag any command that deletes data, changes a global default, or needs `sudo` \
        before I reach it, and explain what it will affect.
        - This is Apple silicon with Homebrew at `/opt/homebrew`. Do not give me `/usr/local` \
        paths or Intel-only advice.
        - Runtimes are managed by version managers, not just Homebrew. Check which one owns a \
        tool before proposing an upgrade path.
        - Ask before removing any runtime version — a project may pin it even if nothing on \
        this machine shows that.
        - If a finding is better solved by changing how I work rather than by a command, say \
        so.
        """
    }
}
