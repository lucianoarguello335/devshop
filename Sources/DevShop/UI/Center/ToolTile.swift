import SwiftUI

/// One tool in the centre grid.
struct ToolTile: View {
    let tool: DetectedTool
    let bytes: Int64
    let maximumBytes: Int64
    let isSelected: Bool
    /// Most severe finding touching this tool, if any.
    let findingTier: FindingTier?
    let select: () -> Void

    @Environment(\.theme) private var theme
    @State private var isHovering = false

    private var isMissing: Bool { tool.status == .missing }
    private var brand: Color { Color(hex: tool.definition.color) }
    private var statusColor: Color { Color(hex: tool.status.hex) }

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 9) {
                    IconChip(tool: tool, size: 30, theme: theme)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(tool.name)
                                .font(.system(size: 12.5, weight: .semibold))
                                .lineLimit(1)
                            if let findingTier {
                                FindingBadge(tier: findingTier, size: 9.5)
                            }
                        }
                        Text(tool.subtitle)
                            .font(.system(size: 10.5))
                            .foregroundStyle(theme.muted)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Circle()
                        .fill(statusColor)
                        .frame(width: 7, height: 7)
                        .overlay {
                            Circle()
                                .stroke(statusColor.opacity(isMissing ? 0 : 0.17), lineWidth: 3)
                        }
                }
                HStack(spacing: 7) {
                    MeterBar(fraction: maximumBytes > 0 && bytes > 0
                             ? max(0.06, Double(bytes) / Double(maximumBytes)) : 0,
                             color: isMissing ? theme.muted : brand)
                        .frame(height: 4)
                    Text(bytes > 0 ? ByteFormat.compact(bytes) : "—")
                        .font(.system(size: 10))
                        .monospacedDigit()
                        .foregroundStyle(theme.muted)
                        .frame(minWidth: 34, alignment: .trailing)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background)
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? DevTheme.accent : .clear, lineWidth: 2)
            }
            .shadow(color: isSelected ? DevTheme.accent.opacity(0.2)
                    : (isMissing ? .clear : theme.cardShadow),
                    radius: isSelected ? 6 : theme.cardShadowRadius,
                    y: isSelected ? 3 : 1)
            .opacity(isMissing ? 0.85 : 1)
            .offset(y: isHovering ? -2 : 0)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.spring(duration: 0.18, bounce: 0.15), value: isHovering)
        .animation(.easeOut(duration: 0.18), value: isSelected)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private var accessibilityDescription: String {
        var parts = [tool.name, tool.subtitle, tool.status.label]
        if let findingTier { parts.append("has \(findingTier.label.lowercased())") }
        return parts.joined(separator: ", ")
    }

    @ViewBuilder
    private var background: some View {
        if isMissing {
            RoundedRectangle(cornerRadius: 10)
                .fill(theme.fill)
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(theme.hairline, lineWidth: 0.5)
                }
        } else {
            RoundedRectangle(cornerRadius: 10)
                .fill(isHovering ? theme.cardHover : theme.card)
        }
    }
}
