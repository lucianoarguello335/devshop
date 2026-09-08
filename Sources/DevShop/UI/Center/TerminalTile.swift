import SwiftUI

/// One terminal emulator, in the row beneath the Terminal Config section title.
///
/// Small on purpose: this row answers "what can open a shell on this Mac", which is context
/// for the entries below it rather than the subject of the section.
struct TerminalTile: View {
    let terminal: TerminalApp
    let isSelected: Bool
    let theme: DevTheme
    let select: () -> Void

    @State private var isHovering = false

    private var tint: Color { Color(hex: terminal.colorHex) }
    private static let iconSize: CGFloat = 26

    var body: some View {
        Button(action: select) {
            HStack(spacing: 9) {
                icon
                VStack(alignment: .leading, spacing: 1) {
                    Text(terminal.name)
                        .font(.system(size: 11.5, weight: .semibold))
                        .lineLimit(1)
                    Text(terminal.version ?? "—")
                        .font(.system(size: 10))
                        .monospacedDigit()
                        .foregroundStyle(theme.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background)
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? DevTheme.accent : .clear, lineWidth: 2)
            }
            .offset(y: isHovering ? -2 : 0)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(Probes.abbreviate(terminal.path))
        .animation(.spring(duration: 0.18, bounce: 0.15), value: isHovering)
        .animation(.easeOut(duration: 0.18), value: isSelected)
        .accessibilityLabel("\(terminal.name) \(terminal.versionLine)")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    /// The app's own icon is always right and always available — the bundle is on disk. The
    /// brand mark and the monogram only stand in for a terminal whose icon cannot be read.
    @ViewBuilder
    private var icon: some View {
        if let image = AppIconLoader.icon(atBundlePath: terminal.path, points: Self.iconSize) {
            image.resizable()
                .interpolation(.high)
                .frame(width: Self.iconSize, height: Self.iconSize)
        } else if let slug = terminal.iconSlug, IconStore.has(slug) {
            IconChip(slug: slug, symbol: "terminal.fill", colorHex: terminal.colorHex,
                     isMissing: false, size: Self.iconSize, theme: theme)
        } else {
            Text(terminal.monogram)
                .font(.system(size: Self.iconSize * 0.42, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: Self.iconSize, height: Self.iconSize)
                .background(tint.opacity(0.9), in: .rect(cornerRadius: Self.iconSize * 0.26))
        }
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(surface(isHovering ? theme.cardHover : theme.card))
    }

    private func surface(_ fill: Color) -> AnyShapeStyle {
        isSelected
            ? AnyShapeStyle(fill.shadow(.drop(color: DevTheme.accent.opacity(0.2),
                                              radius: 6, y: 3)))
            : AnyShapeStyle(fill.shadow(.drop(color: theme.cardShadow,
                                              radius: theme.cardShadowRadius, y: 1)))
    }
}
