import AppKit
import SwiftUI

/// The right column: everything known about whatever is selected, plus the read-only
/// actions. Three kinds of thing can be selected — a tool, a startup directive, or a
/// terminal — and each gets its own branch over the same shared row and card helpers.
struct InspectorView: View {
    @Bindable var model: AppModel
    @Environment(\.theme) private var theme
    @State private var didCopy = false
    @State private var copyResetTask: Task<Void, Never>?
    /// Merged hook rows in the resolved PATH lists that the user opened.
    @State private var expandedHookRuns: Set<String> = []
    /// Commands whose Nested login PATH the user opened although it matches Login terminal.
    @State private var expandedNestedPaths: Set<String> = []

    private var tool: DetectedTool? { model.selectedTool }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("INSPECTOR")
                .font(.system(size: 10.5, weight: .semibold))
                .kerning(0.5)
                .foregroundStyle(theme.muted)

            switch model.selection {
            case .tool:
                if let tool { toolBody(tool) } else { placeholder }
            case .configEntry:
                if let entry = model.selectedConfigEntry { entryBody(entry) } else { placeholder }
            case .resolvedCommand:
                if let resolution = model.selectedResolvedCommand {
                    resolvedBody(resolution)
                } else {
                    placeholder
                }
            case .terminal:
                if let terminal = model.selectedTerminal {
                    terminalBody(terminal)
                } else {
                    placeholder
                }
            case nil:
                placeholder
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(theme.sidebar)
        .onChange(of: model.selection) { _, _ in
            copyResetTask?.cancel()
            didCopy = false
        }
    }

    private var placeholder: some View {
        VStack {
            Spacer()
            Text("Scanning…")
                .font(.system(size: 12))
                .foregroundStyle(theme.muted)
                .frame(maxWidth: .infinity)
            Spacer()
        }
    }

    @ViewBuilder
    private func toolBody(_ tool: DetectedTool) -> some View {
        header(tool)
        statusPill(tool)
        details(tool)
        actions(tool)
        if tool.children.isEmpty {
            shareOfCategory(tool)
            Spacer(minLength: 0)
            findings(tool)
        } else {
            // A container's contents are far more useful here than a share bar, so they take
            // the space instead and stretch to fill the column.
            contents(tool)
        }
    }

    // MARK: - Sections

    private func header(_ tool: DetectedTool) -> some View {
        HStack(spacing: 12) {
            IconChip(tool: tool, size: 52, theme: theme)
            VStack(alignment: .leading, spacing: 1) {
                Text(tool.name)
                    .font(.system(size: 17, weight: .bold))
                    .kerning(-0.34)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(tool.subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.muted)
                    .lineLimit(2)
            }
        }
    }

    private func statusPill(_ tool: DetectedTool) -> some View {
        Text(tool.status.label)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(tool.status == .missing ? theme.muted : Color(hex: tool.status.hex))
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(pillBackground(tool.status), in: .rect(cornerRadius: 8))
    }

    private func pillBackground(_ status: ToolStatus) -> Color {
        switch status {
        case .ok: Color(hex: "30d158").opacity(0.16)
        case .warn: Color(hex: "ff9f0a").opacity(0.18)
        case .missing: theme.fill
        }
    }

    private func details(_ tool: DetectedTool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            detailRow("Location") {
                Text(tool.path.map(Probes.abbreviate) ?? "—")
                    .font(.system(size: 10.5, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            detailRow("Size") {
                Text(sizeText(tool))
                    .font(.system(size: 11.5))
                    .monospacedDigit()
            }
            detailRow("Managed") {
                Text(tool.managedBy).font(.system(size: 11.5))
            }
            detailRow("Category") {
                Text(tool.definition.category.inspectorLabel).font(.system(size: 11.5))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .devCard(theme)
    }

    private func detailRow(_ label: String,
                           @ViewBuilder value: () -> some View) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(theme.muted)
                .frame(width: 62, alignment: .leading)
            value()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func sizeText(_ tool: DetectedTool) -> String {
        let bytes = model.bytes(for: tool)
        if bytes > 0 {
            return tool.measuresBinaryOnly
                ? "\(ByteFormat.full(bytes)) · binary only"
                : ByteFormat.full(bytes)
        }
        if tool.status == .missing { return "—" }
        if tool.measurableRoot == nil { return "shared location" }
        return model.hasSizes ? "under 1 MB" : "not measured"
    }

    private func actions(_ tool: DetectedTool) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    guard let path = tool.path else { return }
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                } label: {
                    Text("Open in Finder")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .background(DevTheme.accent, in: .rect(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(tool.path == nil)
                .opacity(tool.path == nil ? 0.45 : 1)

                Button {
                    copy(tool.path ?? "")
                } label: {
                    Text(didCopy ? "Copied" : "Copy path")
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 13)
                        .frame(height: 30)
                        .devCard(theme, radius: 8)
                }
                .buttonStyle(.plain)
                .disabled(tool.path == nil)
                .opacity(tool.path == nil ? 0.45 : 1)
            }

            Button {
                guard let site = tool.definition.website, let url = URL(string: site) else { return }
                NSWorkspace.shared.open(url)
            } label: {
                HStack(spacing: 6) {
                    Text("Open official website")
                    SFIcon(symbol: "arrow.up.forward", size: 12).foregroundStyle(theme.muted)
                }
                .font(.system(size: 12, weight: .medium))
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .devCard(theme, radius: 8)
            }
            .buttonStyle(.plain)
            .disabled(tool.definition.website == nil)
            .opacity(tool.definition.website == nil ? 0.45 : 1)
        }
    }

    private func copy(_ text: String) {
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        withAnimation(.easeOut(duration: 0.15)) { didCopy = true }
        copyResetTask?.cancel()
        copyResetTask = Task {
            try? await Task.sleep(for: .milliseconds(1300))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.15)) { didCopy = false }
        }
    }

    private func shareOfCategory(_ tool: DetectedTool) -> some View {
        let bytes = model.bytes(for: tool)
        let categoryTotal = model.tools
            .filter { $0.category == tool.category }
            .reduce(Int64(0)) { $0 + model.bytes(for: $1) }
        let fraction = categoryTotal > 0 ? Double(bytes) / Double(categoryTotal) : 0

        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text("Share of disk")
                    .font(.system(size: 11.5, weight: .semibold))
                Spacer()
                Text(bytes > 0 ? "\(Int((fraction * 100).rounded()))%" : "—")
                    .font(.system(size: 10.5))
                    .monospacedDigit()
                    .foregroundStyle(theme.muted)
            }
            MeterBar(fraction: fraction,
                     color: tool.status == .missing
                     ? theme.muted : Color(hex: tool.definition.color))
                .frame(height: 7)
            Text(shareNote(tool, bytes: bytes, categoryTotal: categoryTotal))
                .font(.system(size: 10.5))
                .foregroundStyle(theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .devCard(theme)
    }

    private func shareNote(_ tool: DetectedTool, bytes: Int64, categoryTotal: Int64) -> String {
        guard bytes > 0 else {
            guard model.hasSizes else { return "Press Refresh to measure sizes" }
            return tool.measurableRoot == nil
                ? "Shares an install location with other tools, so no size is attributable to it"
                : "No measurable footprint"
        }
        let share = "\(ByteFormat.compact(bytes)) of \(ByteFormat.compact(categoryTotal)) "
                  + "in \(tool.definition.category.inspectorLabel.lowercased())"
        return tool.measuresBinaryOnly
            ? share + " — the executable only; its toolchain is shared"
            : share
    }

    /// What lives inside a container tile — the formulae in the Cellar, the casks in the
    /// Caskroom, the globally installed npm packages — heaviest first.
    private func contents(_ tool: DetectedTool) -> some View {
        let children = model.children(of: tool)
        let maximum = model.largestChildBytes(of: tool)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Contents")
                    .font(.system(size: 11.5, weight: .semibold))
                Text("\(children.count) items")
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme.muted)
                Spacer(minLength: 0)
                if model.hasSizes {
                    Text(ByteFormat.compact(children.reduce(0) { $0 + model.bytes(for: $1) }))
                        .font(.system(size: 10.5))
                        .monospacedDigit()
                        .foregroundStyle(theme.muted)
                }
            }
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(children) { child in
                        ChildRow(child: child,
                                 bytes: model.bytes(for: child),
                                 maximumBytes: maximum)
                    }
                }
                .padding(.trailing, 2)
            }
            .scrollIndicators(.never)
            .withoutScrollEdgeEffect()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .devCard(theme)
    }

    private func findings(_ tool: DetectedTool) -> some View {
        findingsCard(model.findings(for: tool),
                     emptyMessage: "No findings for \(tool.name) \u{2014} nothing needs attention.")
    }

    // MARK: - Config entry

    @ViewBuilder
    private func entryBody(_ entry: ConfigEntry) -> some View {
        entryHeader(entry)
        // The same sentence the group's info icon carries, from the same string, so landing
        // here from a finding explains the category as well as the entry.
        Text(entry.kind.explanation)
            .font(.system(size: 11))
            .foregroundStyle(theme.muted)
            .fixedSize(horizontal: false, vertical: true)
        kindPill(entry)
        entryDetails(entry)
        entryActions(entry)
        origins(entry)
        Spacer(minLength: 0)
        entryFindings(entry)
    }

    private func entryHeader(_ entry: ConfigEntry) -> some View {
        HStack(spacing: 12) {
            IconChip(slug: nil,
                     symbol: entry.kind.symbol,
                     colorHex: entry.kind.accentHex,
                     isMissing: false,
                     size: 52,
                     theme: theme,
                     glow: true)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name)
                    .font(.system(size: 14.5, weight: .bold, design: .monospaced))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .textSelection(.enabled)
                Text(entry.kind.inspectorLabel)
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.muted)
            }
        }
    }

    /// Which file in the chain it comes from. The stage matters more than the tier here:
    /// "System rc" tells you at a glance that this is not yours to edit.
    private func kindPill(_ entry: ConfigEntry) -> some View {
        let stage = entry.lastOrigin?.stage
        return Text(stage?.label ?? "Startup")
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(stage?.isUserOwned == false ? theme.muted : DevTheme.accent)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(stage?.isUserOwned == false
                        ? theme.fill : DevTheme.accent.opacity(0.14),
                        in: .rect(cornerRadius: 8))
    }

    private func entryDetails(_ entry: ConfigEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            detailRow("Value") { entryValue(entry) }
            detailRow("Set in") {
                Text(entry.lastOrigin?.location ?? "\u{2014}")
                    .font(.system(size: 10.5, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            detailRow("Declared") {
                Text(entry.isDuplicated
                     ? "\(entry.origins.count) times \u{2014} the last one wins"
                     : "once")
                    .font(.system(size: 11.5))
            }
            detailRow("Kind") {
                Text(entry.kind.inspectorLabel).font(.system(size: 11.5))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .devCard(theme)
    }

    /// A secret stays masked until it is asked for. There is no matching hide, because once
    /// a value has been on screen pretending otherwise buys nothing.
    @ViewBuilder
    private func entryValue(_ entry: ConfigEntry) -> some View {
        if entry.isSecret && !model.isRevealed(entry) {
            HStack(spacing: 8) {
                Text(entry.displayValue)
                    .font(.system(size: 10.5, design: .monospaced))
                Button("Reveal") { model.revealSecret(entry) }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(DevTheme.accent)
                    .help("Show the value stored in this file")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(entry.rawValue.isEmpty ? "\u{2014}" : entry.rawValue)
                .font(.system(size: 10.5, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func entryActions(_ entry: ConfigEntry) -> some View {
        let path = entry.lastOrigin.map { Probes.expand(unabbreviate($0.file)) }
        return HStack(spacing: 8) {
            Button {
                guard let path else { return }
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            } label: {
                Text("Reveal file")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
                    .background(DevTheme.accent, in: .rect(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .disabled(path == nil)
            .opacity(path == nil ? 0.45 : 1)

            Button {
                copy(model.value(of: entry))
            } label: {
                Text(didCopy ? "Copied" : "Copy value")
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 13)
                    .frame(height: 30)
                    .devCard(theme, radius: 8)
            }
            .buttonStyle(.plain)
            .help(entry.isSecret && !model.isRevealed(entry)
                  ? "Copies the masked value. Reveal it first to copy the real one."
                  : "Copy this value to the clipboard")
        }
    }

    /// Every place the directive is declared, in load order. This is the section that
    /// answers "why is this not what I set it to" — the last line here is the one that won.
    private func origins(_ entry: ConfigEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Declared in")
                    .font(.system(size: 11.5, weight: .semibold))
                Text(entry.isDuplicated ? "load order" : entry.lastOrigin?.stage.label ?? "")
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme.muted)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(entry.origins.enumerated()), id: \.offset) { index, origin in
                        OriginRow(origin: origin,
                                  isEffective: index == entry.origins.count - 1,
                                  showsEffective: entry.isDuplicated,
                                  redacted: entry.isSecret && !model.isRevealed(entry))
                    }
                }
                .padding(.trailing, 2)
            }
            .scrollIndicators(.never)
            .withoutScrollEdgeEffect()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .devCard(theme)
    }

    @ViewBuilder
    private func entryFindings(_ entry: ConfigEntry) -> some View {
        findingsCard(model.findings(for: entry),
                     emptyMessage: "No findings for \(entry.name) \u{2014} nothing needs attention.")
    }

    // MARK: - Resolved command

    @ViewBuilder
    private func resolvedBody(_ resolution: CommandResolution) -> some View {
        HStack(spacing: 12) {
            IconChip(slug: nil, symbol: "terminal.fill", colorHex: "0a84ff",
                     isMissing: false, size: 52, theme: theme, glow: true)
            VStack(alignment: .leading, spacing: 1) {
                Text(resolution.command)
                    .font(.system(size: 14.5, weight: .bold, design: .monospaced))
                    .textSelection(.enabled)
                Text(resolution.differs ? "Differs between shell contexts" : "Same in both contexts")
                    .font(.system(size: 11.5))
                    .foregroundStyle(resolution.differs ? Color(hex: FindingTier.warning.hex) : theme.muted)
            }
        }
        // Two lines here; the rest is on the tooltip and the group's info popover, so Runs and
        // Set by stay above the fold.
        Text(ResolvedPathGroup.shortExplanation)
            .font(.system(size: 11))
            .foregroundStyle(theme.muted)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .help(ResolvedPathGroup.explanation)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(ShellContext.allCases) { context in
                    contextPath(resolution, context: context)
                }
            }
        }
        Spacer(minLength: 0)
        findingsCard(model.findings(for: resolution),
                     emptyMessage: "No findings for \(resolution.command).")
    }

    private func contextPath(_ resolution: CommandResolution, context: ShellContext) -> some View {
        let hit = resolution.hit(in: context)
        let slots = model.shellConfig.pathResolution.path(for: context)?.slots ?? []
        let winnerIndex = hit.flatMap { hit in slots.firstIndex { $0.dirPath == hit.dir.path } }
        return VStack(alignment: .leading, spacing: 6) {
            Text(context.label)
                .font(.system(size: 11.5, weight: .semibold))
                .help(context.explanation)
            detailRow("Runs") {
                Text(hit?.path ?? "not found")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(hit?.isUncertain == true ? theme.muted : .primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            detailRow("Set by") {
                Text(hit?.dir.sourceLabel ?? "\u{2014}")
                    .font(.system(size: 10.5, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .help(hit?.dir.sourceFile ?? "")
            }
            if let hit, hit.isUncertain {
                detailRow("Unsure") {
                    let count = hit.hooksAhead.count
                    Text("\(count) hook\(count == 1 ? " runs" : "s run") ahead of this directory: "
                       + "\(hit.hooksSummary). Any of them could put a different "
                       + "\(resolution.command) first.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(hex: FindingTier.warning.hex))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            // Nested login repeats the Login terminal list with the inherited copies added. When
            // the answer is the same, that is twenty-odd rows saying nothing new.
            let key = resolution.command
            let isCollapsible = context == .nestedLogin && !resolution.differs
            if isCollapsible {
                Button {
                    if expandedNestedPaths.contains(key) { expandedNestedPaths.remove(key) }
                    else { expandedNestedPaths.insert(key) }
                } label: {
                    HStack(spacing: 6) {
                        SFIcon(symbol: "chevron.right", size: 7, weight: .bold)
                            .foregroundStyle(theme.muted)
                            .rotationEffect(.degrees(expandedNestedPaths.contains(key) ? 90 : 0))
                        Text("Same as Login terminal \u{00b7} show all \(slots.count)")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.muted)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            if !isCollapsible || expandedNestedPaths.contains(key) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(slotRuns(slots), id: \.start) { run in
                    switch run.kind {
                    case .dir(let dir):
                        dirRow(dir, position: run.start + 1, isWinner: run.start == winnerIndex)
                    case .hooks(let steps):
                        hookRunRow(steps, start: run.start, key: "\(context.rawValue).\(run.start)")
                    }
                }
            }
            }
        }
    }

    private struct SlotRun {
        enum Kind { case dir(ResolvedDir), hooks([PathStep]) }
        var start: Int
        var kind: Kind
    }

    /// Back-to-back hooks become one row. Nine "unknown output" lines in a row read as a
    /// broken list, and what matters is how many there are and where the directories start.
    private func slotRuns(_ slots: [PathSlot]) -> [SlotRun] {
        var runs: [SlotRun] = []
        for (index, slot) in slots.enumerated() {
            switch slot {
            case .dir(let dir):
                runs.append(SlotRun(start: index, kind: .dir(dir)))
            case .hook(let step):
                if case .hooks(let steps) = runs.last?.kind {
                    runs[runs.count - 1].kind = .hooks(steps + [step])
                } else {
                    runs.append(SlotRun(start: index, kind: .hooks([step])))
                }
            }
        }
        return runs
    }

    private func positionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9.5, design: .monospaced))
            .foregroundStyle(theme.faint)
            .frame(width: 30, alignment: .trailing)
    }

    /// A fixed width, so a long path cannot squeeze its source down to a sliver, and the
    /// sources line up in one column down the list.
    private func sourceText(_ text: String, help: String? = nil) -> some View {
        Text(text)
            .font(.system(size: 9.5, design: .monospaced))
            .foregroundStyle(theme.faint)
            .lineLimit(1)
            .truncationMode(.head)
            .frame(width: 92, alignment: .trailing)
            .help(help ?? text)
    }

    private func dirRow(_ dir: ResolvedDir, position: Int, isWinner: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            positionLabel("\(position)")
            Text(dir.path)
                .font(.system(size: 10.5, weight: isWinner ? .bold : .regular, design: .monospaced))
                .foregroundStyle(isWinner ? DevTheme.accent : .primary)
                .lineLimit(1)
                .truncationMode(.middle)
            if dir.isConditional {
                Text("if").font(.system(size: 9, weight: .bold)).foregroundStyle(theme.muted)
                    .help("Added inside a condition; it may not apply")
            }
            Spacer(minLength: 4)
            sourceText(dir.shortSourceLabel, help: "\(dir.sourceLabel) (\(dir.sourceFile))")
        }
    }

    @ViewBuilder
    private func hookRunRow(_ steps: [PathStep], start: Int, key: String) -> some View {
        let isOpen = expandedHookRuns.contains(key)
        let warning = Color(hex: FindingTier.warning.hex)
        Button {
            if isOpen { expandedHookRuns.remove(key) } else { expandedHookRuns.insert(key) }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                positionLabel(steps.count == 1 ? "\(start + 1)" : "\(start + 1)\u{2013}\(start + steps.count)")
                SFIcon(symbol: "chevron.right", size: 7, weight: .bold)
                    .foregroundStyle(warning)
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
                Text(steps.count == 1 ? "hook \u{00b7} unknown output"
                                      : "\(steps.count) hooks \u{00b7} unknown output")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(warning)
                    .lineLimit(1)
                    .fixedSize()
                    .layoutPriority(1)
                Spacer(minLength: 4)
                if steps.count == 1 { sourceText(steps[0].origin.location) }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(steps.map { $0.origin.text }.joined(separator: "\n"))
        .accessibilityLabel("\(steps.count) hooks with unknown output")
        .accessibilityValue(isOpen ? "expanded" : "collapsed")
        if isOpen {
            // In run order, which is the reverse of their order in PATH.
            ForEach(Array(steps.reversed().enumerated()), id: \.offset) { _, step in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    positionLabel("")
                    Text(step.hookName)
                        .font(.system(size: 10.5, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 4)
                    sourceText(step.origin.location)
                }
                .help(step.origin.text)
            }
        }
    }

    // MARK: - Terminal

    @ViewBuilder
    private func terminalBody(_ terminal: TerminalApp) -> some View {
        terminalHeader(terminal)
        terminalDetails(terminal)
        terminalActions(terminal)
        Spacer(minLength: 0)
        findingsCard(model.findings(for: terminal),
                     emptyMessage: "No findings for \(terminal.name).")
    }

    private func terminalHeader(_ terminal: TerminalApp) -> some View {
        HStack(spacing: 12) {
            if let icon = AppIconLoader.icon(atBundlePath: terminal.path, points: 52) {
                icon.resizable().interpolation(.high).frame(width: 52, height: 52)
            } else {
                IconChip(slug: terminal.iconSlug, symbol: "terminal.fill",
                         colorHex: terminal.colorHex, isMissing: false,
                         size: 52, theme: theme, glow: true)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(terminal.name)
                    .font(.system(size: 17, weight: .bold))
                    .kerning(-0.34)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text("Terminal emulator")
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.muted)
            }
        }
    }

    private func terminalDetails(_ terminal: TerminalApp) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            detailRow("Version") {
                Text(terminal.versionLine).font(.system(size: 11.5)).monospacedDigit()
            }
            detailRow("Bundle ID") {
                Text(terminal.bundleIdentifier)
                    .font(.system(size: 10.5, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            detailRow("Location") {
                Text(Probes.abbreviate(terminal.path))
                    .font(.system(size: 10.5, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            detailRow("Settings") {
                // Only paths that exist are listed, so an empty row means this terminal
                // keeps nothing of its own rather than that DevShop failed to look.
                Text(terminal.configPaths.isEmpty
                     ? "none found"
                     : terminal.configPaths.joined(separator: "\n"))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(terminal.configPaths.isEmpty ? theme.muted : theme.text)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .devCard(theme)
    }

    private func terminalActions(_ terminal: TerminalApp) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting(
                        [URL(fileURLWithPath: terminal.path)])
                } label: {
                    Text("Open in Finder")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .background(DevTheme.accent, in: .rect(cornerRadius: 8))
                }
                .buttonStyle(.plain)

                Button {
                    copy(terminal.path)
                } label: {
                    Text(didCopy ? "Copied" : "Copy path")
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 13)
                        .frame(height: 30)
                        .devCard(theme, radius: 8)
                }
                .buttonStyle(.plain)
            }

            Button {
                guard let site = terminal.website, let url = URL(string: site) else { return }
                NSWorkspace.shared.open(url)
            } label: {
                HStack(spacing: 6) {
                    Text("Open official website")
                    SFIcon(symbol: "arrow.up.forward", size: 12).foregroundStyle(theme.muted)
                }
                .font(.system(size: 12, weight: .medium))
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .devCard(theme, radius: 8)
            }
            .buttonStyle(.plain)
            .disabled(terminal.website == nil)
            .opacity(terminal.website == nil ? 0.45 : 1)
        }
    }

    // MARK: - Shared

    /// The findings card, shared by everything that is not a tool. The tool branch keeps its
    /// own copy because its empty message names the category as well.
    @ViewBuilder
    private func findingsCard(_ matches: [Finding], emptyMessage: String) -> some View {
        if matches.isEmpty {
            Text(emptyMessage)
                .font(.system(size: 11))
                .foregroundStyle(theme.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(12)
                .background(theme.fill, in: .rect(cornerRadius: 10))
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Findings")
                        .font(.system(size: 11.5, weight: .semibold))
                    Text("\(matches.tally) \u{00b7} this item")
                        .font(.system(size: 10.5))
                        .foregroundStyle(theme.muted)
                }
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(matches) { finding in
                            FindingRow(finding: finding, compact: true) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    model.dismissFinding(finding.id)
                                }
                            }
                        }
                    }
                }
                .scrollIndicators(.never)
                .withoutScrollEdgeEffect()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, minHeight: 110, alignment: .leading)
            .devCard(theme)
        }
    }

    /// Origins are stored abbreviated, the way everything user-facing in this app is, so
    /// they have to be turned back into a real path before Finder can be pointed at one.
    private func unabbreviate(_ path: String) -> String {
        path.hasPrefix("~") ? Probes.home + String(path.dropFirst()) : path
    }
}

/// One declaration of a directive: where it is, and the line as written.
private struct OriginRow: View {
    let origin: ConfigOrigin
    let isEffective: Bool
    /// Only worth marking which one wins when there is more than one.
    let showsEffective: Bool
    /// A secret's line holds the secret, so it is withheld along with the value.
    let redacted: Bool

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(origin.location)
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.head)
                Spacer(minLength: 4)
                if showsEffective && isEffective {
                    Text("WINS")
                        .font(.system(size: 8.5, weight: .bold))
                        .kerning(0.27)
                        .foregroundStyle(DevTheme.accent)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(DevTheme.accent.opacity(0.16), in: .rect(cornerRadius: 4))
                }
                Text(origin.stage.label)
                    .font(.system(size: 9.5))
                    .foregroundStyle(theme.faint)
            }
            Text(redacted ? "value withheld \u{2014} reveal it to see this line" : origin.text)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(redacted ? theme.faint : theme.muted)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.fill, in: .rect(cornerRadius: 7))
        .accessibilityElement(children: .combine)
    }
}

/// One package inside a container, with its real icon where one exists.

private struct ChildRow: View {
    let child: ToolChild
    let bytes: Int64
    let maximumBytes: Int64

    @Environment(\.theme) private var theme
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            ChildIcon(child: child, size: 20)
            VStack(alignment: .leading, spacing: 0) {
                Text(child.name)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(child.version)
                    .font(.system(size: 10))
                    .foregroundStyle(theme.muted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if bytes > 0 {
                MeterBar(fraction: maximumBytes > 0
                         ? max(0.05, Double(bytes) / Double(maximumBytes)) : 0,
                         color: Color(hex: child.color))
                    .frame(width: 30, height: 4)
                Text(ByteFormat.compact(bytes))
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(theme.muted)
                    .frame(width: 34, alignment: .trailing)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(isHovering ? theme.fill : .clear, in: .rect(cornerRadius: 6))
        .contentShape(.rect)
        .onHover { isHovering = $0 }
        .help(Probes.abbreviate(child.path))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(child.name) \(child.version)")
    }
}
