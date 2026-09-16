import AppKit
import SwiftUI

/// One step in "why this copy wins": the slots of PATH up to the winner, with the runs that
/// say nothing on their own folded together.
enum SearchOrderItem: Equatable {
    /// Back-to-back hooks. Positions are 1-based and inclusive.
    case hooks(first: Int, steps: [PathStep])
    /// Directories searched before the winner. None of them holds the command, by definition
    /// of the first match winning, so no filesystem check is needed to say so.
    case searched(first: Int, dirs: [ResolvedDir])
    case winner(position: Int, dir: ResolvedDir)
    /// Everything after the winner, which the shell never reaches for this command.
    case notSearched(first: Int, slots: [PathSlot])

    var first: Int {
        switch self {
        case .hooks(let first, _), .searched(let first, _), .notSearched(let first, _): first
        case .winner(let position, _): position
        }
    }

    /// Builds the list for one context. Pure, so it is tested without a view.
    static func items(slots: [PathSlot], winner: ResolvedDir?) -> [SearchOrderItem] {
        let winnerIndex = winner.flatMap { dir in slots.firstIndex { $0.dirPath == dir.path } }
        let searchedSlots = winnerIndex.map { Array(slots[..<$0]) } ?? slots
        var items: [SearchOrderItem] = []

        for (index, slot) in searchedSlots.enumerated() {
            let position = index + 1
            switch (slot, items.last) {
            case (.hook(let step), .hooks(let first, let steps)?):
                items[items.count - 1] = .hooks(first: first, steps: steps + [step])
            case (.hook(let step), _):
                items.append(.hooks(first: position, steps: [step]))
            case (.dir(let dir), .searched(let first, let dirs)?):
                items[items.count - 1] = .searched(first: first, dirs: dirs + [dir])
            case (.dir(let dir), _):
                items.append(.searched(first: position, dirs: [dir]))
            }
        }
        if let winnerIndex, case .dir(let dir) = slots[winnerIndex] {
            items.append(.winner(position: winnerIndex + 1, dir: dir))
            let rest = Array(slots[(winnerIndex + 1)...])
            if !rest.isEmpty { items.append(.notSearched(first: winnerIndex + 2, slots: rest)) }
        }
        return items
    }
}

/// One typeface, five styles. Hierarchy comes from size, weight and colour — not from
/// switching between proportional and monospaced type, which made paths, names and
/// labels look like three different documents.
private enum Style {
    static let title = Font.system(size: 15, weight: .semibold)
    static let heading = Font.system(size: 12.5, weight: .semibold)
    static let body = Font.system(size: 12)
    static let caption = Font.system(size: 11)
    static let eyebrow = Font.system(size: 10, weight: .semibold)
}

/// The inspector for a Resolved PATH row: the answer first, what could change it second, and
/// the search order only as far as it explains the answer.
///
/// One typeface throughout (see `Style`), and orange only on warning icons, the callout's
/// title and its border. The first version mixed monospaced paths, proportional labels and
/// orange body text, which was hard to read at inspector width.
struct ResolvedCommandInspector<Footer: View>: View {
    let resolution: CommandResolution
    let paths: PathResolution
    @ViewBuilder let footer: () -> Footer

    @Environment(\.theme) private var theme
    @State private var expanded: Set<String> = []

    private let warning = Color(hex: FindingTier.warning.hex)


    var body: some View {
        // One container, so `.id` and the parent's spacing apply to the whole inspector.
        VStack(alignment: .leading, spacing: 12) { content }
            .frame(maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var content: some View {
        header
        Text(ResolvedPathGroup.shortExplanation)
            .font(Style.caption)
            .foregroundStyle(theme.muted)
            .fixedSize(horizontal: false, vertical: true)
            .help(ResolvedPathGroup.explanation)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if resolution.differs { contextStrip } else { answerCard }
                if !hooks.isEmpty { uncertaintyCallout }
                ForEach(resolution.differs ? ShellContext.allCases : [.loginTerminal]) { context in
                    searchOrder(context)
                }
            }
            .padding(.bottom, 8)
        }
        Spacer(minLength: 0)
        footer()
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            CommandIcon.chip(for: resolution.command, size: 52, theme: theme, glow: true)
            VStack(alignment: .leading, spacing: 2) {
                Text(resolution.command)
                    .font(Style.title)
                    .textSelection(.enabled)
                Text(resolution.differs ? "Differs between shell contexts" : "Same in both contexts")
                    .font(Style.caption)
                    .foregroundStyle(resolution.differs ? warning : theme.muted)
            }
        }
    }

    // MARK: Answer

    /// One card when both contexts agree: that is the answer, stated once.
    private var answerCard: some View {
        let hit = resolution.hit(in: .loginTerminal)
        return VStack(alignment: .leading, spacing: 4) {
            Text("RUNS IN BOTH CONTEXTS")
                .font(Style.eyebrow)
                .kerning(0.5)
                .foregroundStyle(theme.muted)
            Text(hit?.path ?? "Not found on PATH")
                .font(Style.heading)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if let hit {
                Text(origin(of: hit.dir))
                    .font(Style.caption)
                    .foregroundStyle(theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.card, in: .rect(cornerRadius: 10))
    }

    /// Two columns when the contexts disagree, so the difference is the first thing seen.
    private var contextStrip: some View {
        let login = resolution.hit(in: .loginTerminal)
        let nested = resolution.hit(in: .nestedLogin)
        return Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
            GridRow {
                Text("")
                ForEach(ShellContext.allCases) { context in
                    Text(context.label.uppercased())
                        .font(Style.eyebrow)
                        .kerning(0.4)
                        .foregroundStyle(theme.muted)
                        .help(context.explanation)
                }
            }
            GridRow {
                stripLabel("Runs")
                stripPath(login?.path)
                stripPath(nested?.path)
            }
            GridRow {
                stripLabel("Set by")
                stripValue(login?.dir.shortSourceLabel)
                stripValue(nested?.dir.shortSourceLabel)
            }
            GridRow {
                stripLabel("Hooks first")
                stripValue(login.map { "\($0.hooksAhead.count)" })
                stripValue(nested.map { "\($0.hooksAhead.count)" })
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.card, in: .rect(cornerRadius: 10))
    }

    private func stripLabel(_ text: String) -> some View {
        Text(text).font(Style.caption).foregroundStyle(theme.muted)
    }

    private func stripPath(_ path: String?) -> some View {
        Text(path ?? "not found")
            .font(Style.body.weight(.semibold))
            .lineLimit(2)
            .truncationMode(.head)
            .help(path ?? "")
            .gridColumnAlignment(.leading)
    }

    private func stripValue(_ text: String?) -> some View {
        Text(text ?? "\u{2014}")
            .font(Style.body)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    private func origin(of dir: ResolvedDir) -> String {
        if dir.isFromPathHelper { return "from \(dir.sourceFile) (path_helper)" }
        if let setBy = dir.setBy { return "from \(setBy.location)" }
        return "from the system default PATH"
    }

    // MARK: Uncertainty

    /// Every hook ahead in either context, most likely first.
    private var hooks: [PathStep] {
        var out: [PathStep] = []
        for context in ShellContext.allCases {
            for step in resolution.hit(in: context)?.rankedHooks ?? [] where !out.contains(step) {
                out.append(step)
            }
        }
        return out
    }

    private var uncertaintyCallout: some View {
        let key = "hooks"
        let showsAll = expanded.contains(key)
        let listed = showsAll ? hooks : Array(hooks.prefix(3))
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                SFIcon(symbol: "exclamationmark.triangle.fill", size: 11, weight: .semibold)
                    .foregroundStyle(warning)
                Text("May differ from your shell")
                    .font(Style.heading)
            }
            Text("\(hooks.count) hook\(hooks.count == 1 ? " runs" : "s run") before this "
               + "directory is searched. Any of them could put a different "
               + "\(resolution.command) first.\(hooks.count > 1 ? " Most likely:" : "")")
                .font(Style.body)
                .foregroundStyle(theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(listed.enumerated()), id: \.offset) { _, step in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\u{2022}").foregroundStyle(theme.muted)
                        Text(name(of: step))
                            .font(Style.body.weight(.medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .layoutPriority(1)
                        Spacer(minLength: 6)
                        source(step.origin.location)
                    }
                    .help(step.origin.text)
                }
            }
            if hooks.count > 3 {
                toggle(key, closed: "Show all \(hooks.count)", open: "Show fewer")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(warning.opacity(0.07), in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10).strokeBorder(warning.opacity(0.22), lineWidth: 1)
        }
    }

    // MARK: Search order

    private func searchOrder(_ context: ShellContext) -> some View {
        let slots = paths.path(for: context)?.slots ?? []
        let hit = resolution.hit(in: context)
        let items = SearchOrderItem.items(slots: slots, winner: hit?.dir)
        return VStack(alignment: .leading, spacing: 6) {
            Divider().overlay(theme.hairline)
            Text(resolution.differs ? "Search order \u{00b7} \(context.label)"
                                    : "Search order for \(resolution.command)")
                .font(Style.heading)
                .padding(.top, 4)
                .help(context.explanation)
            VStack(alignment: .leading, spacing: 5) {
                ForEach(items, id: \.first) { item in
                    row(item, key: "\(context.rawValue).\(item.first)")
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ item: SearchOrderItem, key: String) -> some View {
        switch item {
        case .hooks(let first, let steps):
            expandableRow(key: key, position: range(first, steps.count),
                          title: steps.count == 1 ? "1 hook \u{00b7} unknown output"
                                                  : "\(steps.count) hooks \u{00b7} unknown output",
                          titleColor: warning) {
                // In run order, which is the reverse of their order in PATH.
                ForEach(Array(steps.reversed().enumerated()), id: \.offset) { _, step in
                    detailLine(name(of: step), source: step.origin.location, help: step.origin.text)
                }
            }
        case .searched(let first, let dirs):
            if dirs.count == 1, let dir = dirs.first {
                line(position: "\(first)") {
                    path(dir.path)
                    note("no \(resolution.command)")
                    Spacer(minLength: 6)
                    source(dir.shortSourceLabel, help: dir.sourceLabel)
                }
            } else {
                expandableRow(key: key, position: range(first, dirs.count),
                              title: "\(dirs.count) directories \u{00b7} no \(resolution.command)",
                              titleColor: theme.muted) {
                    ForEach(Array(dirs.enumerated()), id: \.offset) { _, dir in
                        detailLine(dir.path, source: dir.shortSourceLabel, help: dir.sourceLabel)
                    }
                }
            }
        case .winner(let position, let dir):
            line(position: "\(position)") {
                SFIcon(symbol: "checkmark.circle.fill", size: 10.5, weight: .semibold)
                    .foregroundStyle(DevTheme.accent)
                // Blue means "click me" everywhere else in the app, so the winner does what
                // it looks like: shows the executable in Finder.
                let executable = dir.path + "/" + resolution.command
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting(
                        [URL(fileURLWithPath: Probes.expand(executable))])
                } label: {
                    // The answer, so it gets the whole row: no source label beside it (the
                    // card above already names the file) and a second line if it needs one.
                    Text(executable)
                        .font(Style.body.weight(.semibold))
                        .foregroundStyle(DevTheme.accent)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .help("Show \(executable) in Finder")
                .accessibilityHint("Shows the file in Finder")
                Spacer(minLength: 0)
            }
        case .notSearched(_, let slots):
            expandableRow(key: key, position: "",
                          title: "\(slots.count) more after \u{00b7} not searched",
                          titleColor: theme.muted) {
                ForEach(Array(slots.enumerated()), id: \.offset) { _, slot in
                    switch slot {
                    case .dir(let dir):
                        detailLine(dir.path, source: dir.shortSourceLabel, help: dir.sourceLabel)
                    case .hook(let step):
                        detailLine(name(of: step), source: step.origin.location, help: step.origin.text)
                    }
                }
            }
        }
    }

    // MARK: Building blocks

    /// A hook with no recognisable name is named by what it does. Repeating its line on both
    /// sides of the row, as `~/.zshrc:5 \u{00b7} source` once did, says the same thing twice.
    private func name(of step: PathStep) -> String {
        step.hasRecognisableName ? step.hookName : step.hookKind
    }

    private func range(_ first: Int, _ count: Int) -> String {
        count == 1 ? "\(first)" : "\(first)\u{2013}\(first + count - 1)"
    }

    private func line(position: String, @ViewBuilder content: () -> some View) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(position)
                .font(Style.caption.monospacedDigit())
                .foregroundStyle(theme.muted)
                // Wide enough for a range like `10\u{2013}14`, which wrapped at 34.
                .frame(width: 46, alignment: .trailing)
            content()
        }
    }

    private func expandableRow(key: String, position: String, title: String, titleColor: Color,
                               @ViewBuilder details: () -> some View) -> some View {
        let isOpen = expanded.contains(key)
        return VStack(alignment: .leading, spacing: 3) {
            Button { flip(key) } label: {
                line(position: position) {
                    SFIcon(symbol: "chevron.right", size: 7.5, weight: .bold)
                        .foregroundStyle(titleColor)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                    Text(title)
                        .font(Style.body)
                        .foregroundStyle(titleColor == warning ? theme.text : titleColor)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityValue(isOpen ? "expanded" : "collapsed")
            if isOpen {
                VStack(alignment: .leading, spacing: 3) { details() }
                    .padding(.leading, 54)
            }
        }
    }

    private func detailLine(_ text: String, source label: String, help: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(text)
                .font(Style.body)
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(1)
            Spacer(minLength: 6)
            source(label, help: help)
        }
    }

    private func path(_ text: String) -> some View {
        Text(text)
            .font(Style.body)
            .lineLimit(1)
            .truncationMode(.middle)
            .layoutPriority(1)
    }

    /// "no python3" beside a searched directory. It shortens before the source does: the
    /// line number is the part worth keeping whole.
    private func note(_ text: String) -> some View {
        Text(text)
            .font(Style.caption)
            .foregroundStyle(theme.muted)
            .lineLimit(1)
            .truncationMode(.tail)
            .layoutPriority(-1)
    }

    private func source(_ text: String, help: String? = nil) -> some View {
        Text(text)
            .font(Style.caption)
            .foregroundStyle(theme.muted)
            .lineLimit(1)
            .truncationMode(.head)
            .layoutPriority(1)
            .help(help ?? text)
    }

    private func toggle(_ key: String, closed: String, open: String) -> some View {
        Button(expanded.contains(key) ? open : closed) { flip(key) }
            .buttonStyle(.plain)
            .font(Style.body.weight(.medium))
            .foregroundStyle(DevTheme.accent)
    }

    private func flip(_ key: String) {
        if expanded.contains(key) { expanded.remove(key) } else { expanded.insert(key) }
    }
}
