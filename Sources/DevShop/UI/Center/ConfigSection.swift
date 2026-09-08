import SwiftUI

/// The "Terminal Config" section of the centre column: what opens a shell on this Mac, and
/// every unique thing the shell does before the first prompt.
///
/// Always a list, whatever the grid/list switch says. A directive is a name, a value and a
/// file reference — three pieces of text of very different lengths — and there is no useful
/// square to put that in.
struct ConfigSection: View {
    @Bindable var model: AppModel
    @Environment(\.theme) private var theme

    private let terminalColumns = [GridItem(.adaptive(minimum: 132, maximum: 220), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            header
            if !model.shellConfig.terminals.isEmpty { terminals }
            ForEach(model.configGroups) { group in
                VStack(alignment: .leading, spacing: 4) {
                    ConfigGroupHeader(kind: group.kind,
                                      count: group.entries.count,
                                      isExpanded: model.isExpanded(group.kind),
                                      theme: theme) {
                        model.toggleConfigGroup(group.kind)
                    }
                    if model.isExpanded(group.kind) {
                        VStack(spacing: 2) {
                            ForEach(group.entries) { entry in
                                ConfigEntryRow(
                                    entry: entry,
                                    isSelected: model.selection == .configEntry(entry.id),
                                    findingTier: model.findingTier(for: entry),
                                    theme: theme) {
                                        model.select(entry)
                                    }
                                    .equatable()
                            }
                        }
                        .transition(.opacity)
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.collapsedConfigKinds)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Text("Terminal Config")
                .font(.system(size: 15, weight: .semibold))
                .kerning(-0.22)
            Text(model.configMeta)
                .font(.system(size: 11))
                .foregroundStyle(theme.muted)
                .contentTransition(.numericText())
            Spacer(minLength: 12)
            Text(model.shellConfig.shell)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(theme.muted)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(theme.tagBackground, in: .rect(cornerRadius: 6))
                .help("The login shell this chain belongs to")
        }
    }

    private var terminals: some View {
        LazyVGrid(columns: terminalColumns, alignment: .leading, spacing: 8) {
            ForEach(model.shellConfig.terminals) { terminal in
                TerminalTile(terminal: terminal,
                             isSelected: model.selection == .terminal(terminal.id),
                             theme: theme) {
                    model.select(terminal)
                }
            }
        }
    }
}

/// A group's title row. Clicking anywhere on it collapses or expands the group, so the
/// chevron is an affordance rather than the only target.
///
/// The info button sits immediately after the count, where the eye already is once it has
/// read the title. It is a real button rather than a bare glyph carrying a `.help`: a plain
/// `Image` gives macOS a glyph-shaped tracking area that a hover barely lands on, and a
/// tooltip is invisible to anyone whose instinct is to click. The click opens a popover, and
/// the tooltip is kept as well for anyone who does hover.
private struct ConfigGroupHeader: View {
    let kind: ConfigEntryKind
    let count: Int
    let isExpanded: Bool
    let theme: DevTheme
    let toggle: () -> Void

    @State private var isHovering = false
    @State private var isExplaining = false

    var body: some View {
        HStack(spacing: 6) {
            Button(action: toggle) {
                HStack(spacing: 6) {
                    SFIcon(symbol: "chevron.right", size: 8, weight: .bold)
                        .foregroundStyle(theme.muted)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 9)
                    SFIcon(symbol: kind.symbol, size: 9, weight: .semibold)
                        .foregroundStyle(Color(hex: kind.accentHex))
                    Text(kind.groupTitle.uppercased())
                        .font(.system(size: 10.5, weight: .semibold))
                        .kerning(0.5)
                        .foregroundStyle(theme.muted)
                    Text("\(count)")
                        .font(.system(size: 10.5))
                        .monospacedDigit()
                        .foregroundStyle(theme.faint)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Collapse \(kind.groupTitle)" : "Expand \(kind.groupTitle)")
            .accessibilityLabel("\(kind.groupTitle), \(count) entries")
            .accessibilityValue(isExpanded ? "expanded" : "collapsed")
            .accessibilityHint("Shows or hides this group")

            info

            // The rest of the row still toggles the group. A Spacer alone takes no hits, so
            // the remainder is a clear rectangle that does.
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(.rect)
                .onTapGesture(perform: toggle)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(height: 22)
        .background(isHovering ? theme.fill : .clear, in: .rect(cornerRadius: 6))
        .onHover { isHovering = $0 }
        .padding(.top, 4)
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
    }

    private var info: some View {
        Button { isExplaining.toggle() } label: {
            SFIcon(symbol: "info.circle", size: 10.5)
                .foregroundStyle(isExplaining ? DevTheme.accent : theme.faint)
                // A 16pt square gives the pointer something to land on. Without it the
                // tracking area is the glyph's own outline and the tooltip rarely fires.
                .frame(width: 16, height: 16)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(kind.explanation)
        .accessibilityLabel("About \(kind.groupTitle)")
        .accessibilityValue(kind.explanation)
        .popover(isPresented: $isExplaining, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    SFIcon(symbol: kind.symbol, size: 10, weight: .semibold)
                        .foregroundStyle(Color(hex: kind.accentHex))
                    Text(kind.groupTitle.uppercased())
                        .font(.system(size: 10.5, weight: .semibold))
                        .kerning(0.5)
                        .foregroundStyle(theme.muted)
                }
                Text(kind.explanation)
                    .font(.system(size: 11.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(width: 270, alignment: .leading)
        }
    }
}

/// One directive. `Equatable` and used through `.equatable()` for the same reason `ToolTile`
/// is: seventy rows should not all re-run their bodies when one of them is selected.
struct ConfigEntryRow: View, Equatable {
    let entry: ConfigEntry
    let isSelected: Bool
    let findingTier: FindingTier?
    let theme: DevTheme
    let select: () -> Void

    @State private var isHovering = false

    nonisolated static func == (a: ConfigEntryRow, b: ConfigEntryRow) -> Bool {
        a.entry == b.entry
            && a.isSelected == b.isSelected
            && a.findingTier == b.findingTier
            && a.theme == b.theme
    }

    private var tint: Color { Color(hex: entry.kind.accentHex) }

    var body: some View {
        Button(action: select) {
            HStack(spacing: 9) {
                SFIcon(symbol: entry.kind.symbol, size: 9.5, weight: .semibold)
                    .foregroundStyle(tint)
                    .frame(width: 20, height: 20)
                    .background(tint.opacity(0.16), in: .rect(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(entry.name)
                            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if let findingTier { FindingBadge(tier: findingTier, size: 9) }
                        if entry.isSecret { secretTag }
                        if entry.isDuplicated { duplicateTag }
                    }
                    Text(entry.summary)
                        .font(.system(size: 10.5))
                        .foregroundStyle(theme.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(entry.lastOrigin?.location ?? "")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(theme.faint)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .frame(maxWidth: 190, alignment: .trailing)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(background)
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? DevTheme.accent : .clear, lineWidth: 1.5)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.16), value: isSelected)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private var secretTag: some View {
        tag("SECRET", color: Color(hex: FindingTier.error.hex))
    }

    /// How many times the directive is declared. Only shown above one, so a plain row stays
    /// plain.
    private var duplicateTag: some View {
        tag("\u{00d7}\(entry.origins.count)", color: theme.muted)
    }

    private func tag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .kerning(0.27)
            .foregroundStyle(color)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(theme.tagBackground, in: .rect(cornerRadius: 4))
    }

    @ViewBuilder
    private var background: some View {
        if isSelected || isHovering {
            RoundedRectangle(cornerRadius: 8).fill(isSelected ? theme.card : theme.fill)
        } else {
            Color.clear
        }
    }

    private var accessibilityDescription: String {
        var parts = [entry.kind.inspectorLabel, entry.name]
        if !entry.isSecret { parts.append(entry.displayValue) }
        if let location = entry.lastOrigin?.location { parts.append("from \(location)") }
        if let findingTier { parts.append("has \(findingTier.label.lowercased())") }
        return parts.joined(separator: ", ")
    }
}
