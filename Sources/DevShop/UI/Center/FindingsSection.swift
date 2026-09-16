import SwiftUI

/// One finding, used both in the centre column and, more compactly, in the inspector.
struct FindingRow: View {
    let finding: Finding
    var compact: Bool = false
    /// Shows the checkmark that hides this finding until the next Refresh.
    var onDismiss: (() -> Void)? = nil
    @Environment(\.theme) private var theme
    @State private var isHoveringDismiss = false

    private var tint: Color { Color(hex: finding.tier.hex) }

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            RoundedRectangle(cornerRadius: 2)
                .fill(tint)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(finding.title)
                    .font(.system(size: compact ? 11.5 : 12.5, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                Text(finding.detail)
                    .font(.system(size: compact ? 10.5 : 11))
                    .foregroundStyle(theme.faint)
                    .fixedSize(horizontal: false, vertical: true)
                if !compact {
                    Text(finding.scope)
                        .font(.system(size: 10.5))
                        .foregroundStyle(theme.muted)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(finding.tier.label): \(finding.title). \(finding.detail)")
            HStack(spacing: 5) {
                Text(finding.tier.label.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .kerning(0.27)
                    .foregroundStyle(tint)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(theme.tagBackground, in: .rect(cornerRadius: 5))
                    .accessibilityHidden(true)
                if let onDismiss {
                    dismissButton(onDismiss)
                }
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(tint.opacity(theme.tierWash), in: .rect(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(tint.opacity(0.25), lineWidth: 0.5)
        }
        .accessibilityElement(children: .contain)
    }

    /// Sized to match the tier tag beside it.
    private func dismissButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            SFIcon(symbol: "checkmark", size: 8.5, weight: .bold)
                .foregroundStyle(isHoveringDismiss ? tint : theme.muted)
                .frame(width: 17, height: 15)
                .background(theme.tagBackground.opacity(isHoveringDismiss ? 1 : 0.6),
                            in: .rect(cornerRadius: 5))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHoveringDismiss = $0 }
        .help("Dismiss until the next Refresh")
        .accessibilityLabel("Dismiss finding")
        .accessibilityHint("Hides this finding until the next Refresh")
    }
}

/// The "Findings" section of the centre column.
struct FindingsSection: View {
    let findings: [Finding]
    let summary: String
    let dismissedCount: Int
    let copyPrompt: () -> Void
    let dismiss: (String) -> Void
    let dismissAll: () -> Void
    let restoreDismissed: () -> Void
    @Environment(\.theme) private var theme
    @State private var isHovering = false
    @State private var isHoveringRestore = false
    @State private var isHoveringClear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text("Findings")
                    .font(.system(size: 15, weight: .semibold))
                    .kerning(-0.22)
                Text(summary)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.muted)
                if dismissedCount > 0 {
                    restoreButton
                }
                Spacer(minLength: 12)
                if !findings.isEmpty { clearAllButton }
                copyButton
            }
            VStack(spacing: 6) {
                ForEach(findings) { finding in
                    FindingRow(finding: finding) { dismiss(finding.id) }
                }
            }
        }
    }

    private var restoreButton: some View {
        Button(action: restoreDismissed) {
            Text("Show \(dismissedCount) dismissed")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DevTheme.accent)
                .underline(isHoveringRestore)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHoveringRestore = $0 }
        .help("Bring back the findings you dismissed")
    }

    /// Quieter than Copy AI prompt: it removes things rather than acting on them, so it reads
    /// as secondary, and it is undone by "Show N dismissed".
    private var clearAllButton: some View {
        Button(action: dismissAll) {
            HStack(spacing: 5) {
                SFIcon(symbol: "checkmark", size: 9, weight: .bold)
                Text("Clear all")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(isHoveringClear ? theme.text : theme.muted)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(theme.fill.opacity(isHoveringClear ? 1 : 0.6), in: .rect(cornerRadius: 6))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHoveringClear = $0 }
        .help("Dismiss every finding until the next Refresh")
        .accessibilityLabel("Clear all findings")
        .accessibilityHint("Hides every finding until the next Refresh")
    }

    /// Sits on the same line as the title and lines up with the tier tags down the right
    /// edge of the rows below it.
    private var copyButton: some View {
        Button(action: copyPrompt) {
            HStack(spacing: 5) {
                SFIcon(symbol: "sparkles", size: 10, weight: .semibold)
                Text("Copy AI prompt")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(DevTheme.accent)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(DevTheme.accent.opacity(isHovering ? 0.22 : 0.14),
                        in: .rect(cornerRadius: 6))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("Copy a prompt to send your AI agent for diagnosing and fixing findings")
        .accessibilityLabel("Copy AI prompt")
        .accessibilityHint("Copies a briefing describing every finding for an AI agent to act on")
    }
}
