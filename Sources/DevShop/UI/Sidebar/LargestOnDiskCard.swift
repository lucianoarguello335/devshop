import SwiftUI

/// The collapsible "Largest on disk" card: the four heaviest categories.
struct LargestOnDiskCard: View {
    let rows: [CategoryTotal]
    @Binding var isExpanded: Bool
    @Environment(\.theme) private var theme

    private var maximum: Int64 { max(1, rows.first?.bytes ?? 1) }

    var body: some View {
        if isExpanded {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text("Largest on disk")
                        .font(.system(size: 11.5, weight: .semibold))
                    Spacer(minLength: 0)
                    Button {
                        isExpanded = false
                    } label: {
                        SFIcon(symbol: "minus", size: 9, weight: .bold)
                            .foregroundStyle(theme.faint)
                            .frame(width: 18, height: 18)
                            .background(theme.fill, in: .rect(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Minimise largest on disk")
                }
                .padding(.bottom, 2)

                ForEach(rows) { row in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(hex: row.category.accentHex))
                            .frame(width: 7, height: 7)
                        Text(row.category.shortTitle)
                            .font(.system(size: 11))
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        MeterBar(fraction: Double(row.bytes) / Double(maximum),
                                 color: Color(hex: row.category.accentHex))
                            .frame(width: 44, height: 5)
                        Text(ByteFormat.compact(row.bytes))
                            .font(.system(size: 10))
                            .monospacedDigit()
                            .foregroundStyle(theme.muted)
                            .frame(width: 34, alignment: .trailing)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .devCard(theme)
        } else {
            Button {
                isExpanded = true
            } label: {
                HStack(spacing: 5) {
                    Text("Show Largest on disk")
                        .font(.system(size: 11.5, weight: .medium))
                    SFIcon(symbol: "chevron.right", size: 8, weight: .bold)
                }
                .foregroundStyle(DevTheme.accent)
                .padding(.horizontal, 4)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
        }
    }
}

/// A rounded track with a proportional fill. Used at three sizes across the window.
///
/// Drawn as a single animatable `Shape` rather than a `GeometryReader` over two capsules. A
/// meter appears on every tile, every table row, every package in the inspector and every row
/// of the card above, so the reader alone put well over a hundred layout-deferring containers
/// in the window — and the spring re-ran layout for each of them on every size flush.
struct MeterBar: View {
    let fraction: Double
    let color: Color
    var trackColor: Color?
    @Environment(\.theme) private var theme
    /// Off while sizes are streaming in: a flush lands every 250ms, and animating every bar
    /// through a 0.9s spring on each one keeps the whole window redrawing for minutes.
    @Environment(\.meterAnimated) private var animated

    var body: some View {
        MeterFill(fraction: min(1, max(0, fraction)))
            .fill(color)
            .background(Capsule().fill(trackColor ?? theme.track))
            .animation(animated ? .spring(duration: 0.9, bounce: 0.05) : nil, value: fraction)
    }
}

/// The filled portion, as a shape so the fraction animates in the render pass instead of
/// through a frame the layout system has to recompute.
private struct MeterFill: Shape {
    var fraction: Double

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let width = rect.width * fraction
        guard width > 0, rect.height > 0 else { return Path() }
        return Capsule().path(in: CGRect(x: rect.minX, y: rect.minY,
                                         width: width, height: rect.height))
    }
}
