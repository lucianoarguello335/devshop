import SwiftUI

/// One tool in the centre grid.
///
/// `Equatable`, and used through `.equatable()`, so a selection change or one of the size
/// flushes that land every 250ms while measuring only re-runs the bodies of the tiles that
/// actually changed. The theme is passed in rather than read from the environment for the same
/// reason: it has to take part in the comparison for that skipping to stay correct.
struct ToolTile: View, Equatable {
    let tile: TileData
    let maximumBytes: Int64
    let isSelected: Bool
    let theme: DevTheme
    let select: () -> Void

    @State private var isHovering = false

    nonisolated static func == (a: ToolTile, b: ToolTile) -> Bool {
        a.tile == b.tile
            && a.maximumBytes == b.maximumBytes
            && a.isSelected == b.isSelected
            && a.theme == b.theme
    }

    private var isMissing: Bool { tile.isMissing }
    private var brand: Color { Color(hex: tile.colorHex) }
    private var statusColor: Color { Color(hex: tile.status.hex) }

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 9) {
                    IconChip(tile: tile, size: 30, theme: theme)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(tile.name)
                                .font(.system(size: 12.5, weight: .semibold))
                                .lineLimit(1)
                            if let findingTier = tile.findingTier {
                                FindingBadge(tier: findingTier, size: 9.5)
                            }
                        }
                        Text(tile.subtitle)
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
                    MeterBar(fraction: maximumBytes > 0 && tile.bytes > 0
                             ? max(0.06, Double(tile.bytes) / Double(maximumBytes)) : 0,
                             color: isMissing ? theme.muted : brand)
                        .frame(height: 4)
                    Text(tile.bytes > 0 ? ByteFormat.compact(tile.bytes) : "—")
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
        var parts = [tile.name, tile.subtitle, tile.status.label]
        if let findingTier = tile.findingTier { parts.append("has \(findingTier.label.lowercased())") }
        return parts.joined(separator: ", ")
    }

    /// The card, its border and its shadow in one fill.
    ///
    /// The shadow used to be a `.shadow(...)` modifier on the whole tile, which rasterises the
    /// tile offscreen before drawing it. At a hundred-odd tiles that was a hundred-odd extra
    /// render passes per frame; as part of the fill style it costs nothing extra.
    @ViewBuilder
    private var background: some View {
        if isMissing {
            RoundedRectangle(cornerRadius: 10)
                .fill(surface(theme.fill))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(theme.hairline, lineWidth: 0.5)
                }
        } else {
            RoundedRectangle(cornerRadius: 10)
                .fill(surface(isHovering ? theme.cardHover : theme.card))
        }
    }

    /// A missing tile carries no shadow of its own, but a selected one still glows.
    private func surface(_ fill: Color) -> AnyShapeStyle {
        if isSelected {
            return AnyShapeStyle(fill.shadow(
                .drop(color: DevTheme.accent.opacity(0.2), radius: 6, y: 3)))
        }
        if isMissing { return AnyShapeStyle(fill) }
        return AnyShapeStyle(fill.shadow(
            .drop(color: theme.cardShadow, radius: theme.cardShadowRadius, y: 1)))
    }
}
