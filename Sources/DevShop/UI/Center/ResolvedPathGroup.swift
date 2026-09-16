import SwiftUI

/// Which executable each common command runs, per shell context. Sits above the directive
/// groups because it answers the question those groups only hint at.
struct ResolvedPathGroup: View {
    @Bindable var model: AppModel
    @Environment(\.theme) private var theme

    static let title = "Resolved PATH"
    /// The two lines the inspector opens with; `explanation` carries the rest.
    static let shortExplanation =
        "Which file runs when you type a command, worked out from the startup files without "
      + "running them."
    static let explanation =
        "Which file runs when you type a command, worked out from the startup files without "
      + "running them. A new Terminal window and a shell started inside another one \u{2014} an "
      + "editor's terminal, tmux \u{2014} can land on different copies. UNSURE means a hook runs "
      + "ahead of that directory, so its output could win instead."

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ConfigGroupHeader(title: Self.title,
                              symbol: "point.topleft.down.to.point.bottomright.curvepath.fill",
                              accentHex: "0a84ff",
                              explanation: Self.explanation,
                              count: model.resolvedCommands.count,
                              isExpanded: model.isResolvedPathShown,
                              theme: theme) {
                model.toggleResolvedPathGroup()
            }
            if model.isResolvedPathShown {
                // A picker whose two sides show the same rows looks broken. When nothing
                // differs, that is the answer, so it is said instead.
                if anyDiffers {
                    Picker("Context", selection: $model.resolvedPathContext) {
                        ForEach(ShellContext.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.small)
                    .help(model.resolvedPathContext.explanation)
                    .padding(.horizontal, 6)
                    .padding(.bottom, 2)
                } else if !allUncertain {
                    sameEverywhereLine
                }

                // "Same" and "unsure" side by side read as a contradiction, so when every row
                // is unsure the one banner carries both halves.
                if allUncertain { uncertaintyBanner }

                VStack(spacing: 2) {
                    ForEach(model.resolvedCommands) { resolution in
                        ResolvedCommandRow(
                            resolution: resolution,
                            context: context,
                            isSelected: model.selection == .resolvedCommand(resolution.command),
                            findingTier: model.findingTier(for: resolution),
                            marksUncertainty: !allUncertain,
                            theme: theme) {
                                model.select(.resolvedCommand(resolution.command))
                            }
                            .equatable()
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.isResolvedPathShown)
    }

    /// Judged on every command, not just the ones a search left, so typing does not make the
    /// picker appear and disappear.
    private var anyDiffers: Bool { model.shellConfig.pathResolution.commands.contains(where: \.differs) }

    private var context: ShellContext { anyDiffers ? model.resolvedPathContext : .loginTerminal }

    /// When every row is unsure, a mark on each row says nothing. One line says it once.
    private var allUncertain: Bool {
        !model.resolvedCommands.isEmpty && model.resolvedCommands.allSatisfy {
            $0.hit(in: context)?.isUncertain ?? true
        }
    }

    private var sameEverywhereLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            SFIcon(symbol: "checkmark.circle.fill", size: 10, weight: .semibold)
                .foregroundStyle(Color(hex: "30d158"))
            Text("Same in a new Terminal window and in nested shells (editor terminals, tmux).")
                .font(.system(size: 11))
                .foregroundStyle(theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .help(ShellContext.nestedLogin.explanation)
        .accessibilityElement(children: .combine)
    }

    private var uncertaintyBanner: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            SFIcon(symbol: "exclamationmark.triangle.fill", size: 10, weight: .semibold)
                .foregroundStyle(Color(hex: FindingTier.warning.hex))
            Text(anyDiffers
                 ? "Hooks run ahead of every directory below, so any of these can differ from "
                 + "what your shell runs. Select a row to see which hooks."
                 : "The files give the same result in a new Terminal window and in nested "
                 + "shells, but hooks run ahead of every directory below, so your shell may "
                 + "differ. Select a row to see which hooks.")
                .font(.system(size: 11))
                .foregroundStyle(theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: FindingTier.warning.hex).opacity(0.08), in: .rect(cornerRadius: 8))
        .padding(.horizontal, 6)
        .accessibilityElement(children: .combine)
    }
}

/// The catalog tool each command belongs to, so a Resolved PATH row carries the same brand
/// mark as that tool's tile instead of a generic terminal glyph.
enum CommandIcon {
    static let catalogIDs: [String: String] = [
        "python3": "lang.python", "python": "lang.python", "pip3": "pkg.pip",
        "node": "lang.node", "npm": "pkg.npm",
        "ruby": "lang.ruby", "gem": "pkg.gem",
        "java": "lang.java", "go": "lang.go", "cargo": "pkg.cargo",
        "swift": "lang.swift", "git": "shell.git"
    ]

    static func definition(for command: String) -> ToolDefinition? {
        guard let id = catalogIDs[command] else { return nil }
        return Catalog.all.first { $0.id == id }
    }

    /// The chip for a command, falling back to the terminal glyph for one the catalog lacks.
    @MainActor
    static func chip(for command: String, size: CGFloat, theme: DevTheme,
                     glow: Bool = false) -> IconChip {
        let tool = definition(for: command)
        return IconChip(slug: tool?.icon, symbol: tool?.symbol ?? "terminal.fill",
                        colorHex: tool?.color ?? "0a84ff", isMissing: false,
                        size: size, theme: theme, glow: glow)
    }
}

struct ResolvedCommandRow: View, Equatable {
    let resolution: CommandResolution
    let context: ShellContext
    let isSelected: Bool
    let findingTier: FindingTier?
    /// Off when the group already says every row is unsure.
    let marksUncertainty: Bool
    let theme: DevTheme
    let select: () -> Void

    @State private var isHovering = false

    nonisolated static func == (a: ResolvedCommandRow, b: ResolvedCommandRow) -> Bool {
        a.resolution == b.resolution && a.context == b.context && a.isSelected == b.isSelected
            && a.findingTier == b.findingTier && a.marksUncertainty == b.marksUncertainty
            && a.theme == b.theme
    }

    private var isUncertain: Bool { hit?.isUncertain == true }

    private var hit: CommandHit? { resolution.hit(in: context) }

    var body: some View {
        Button(action: select) {
            HStack(spacing: 9) {
                CommandIcon.chip(for: resolution.command, size: 20, theme: theme)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(resolution.command)
                            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                        if let findingTier { FindingBadge(tier: findingTier, size: 9) }
                        if resolution.differs {
                            tag("DIFFERS", color: Color(hex: FindingTier.warning.hex))
                        }
                        if isUncertain && marksUncertainty {
                            tag("UNSURE", color: Color(hex: FindingTier.warning.hex))
                        }
                    }
                    // An unsure answer is drawn fainter, so it does not read as a fact.
                    Text(hit?.path ?? "Not found in this context")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(isUncertain ? theme.faint : theme.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let hit, isUncertain, marksUncertainty {
                        Text("may be replaced by \(hit.hooksSummary)")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Color(hex: FindingTier.warning.hex))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(hit?.dir.shortSourceLabel ?? "")
                    .help(hit.map { "\($0.dir.sourceLabel) (\($0.dir.sourceFile))" } ?? "")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(theme.faint)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .frame(maxWidth: 190, alignment: .trailing)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background {
                if isSelected || isHovering {
                    RoundedRectangle(cornerRadius: 8).fill(isSelected ? theme.card : theme.fill)
                }
            }
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

    private func tag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .kerning(0.27)
            .foregroundStyle(color)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(theme.tagBackground, in: .rect(cornerRadius: 4))
    }

    private var accessibilityDescription: String {
        var parts = [resolution.command, hit.map { "runs \($0.path)" } ?? "not found"]
        if resolution.differs { parts.append("differs between shell contexts") }
        if let hit, hit.isUncertain { parts.append("unsure, may be replaced by \(hit.hooksSummary)") }
        if let findingTier { parts.append("has \(findingTier.label.lowercased())") }
        return parts.joined(separator: ", ")
    }
}
