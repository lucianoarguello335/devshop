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
struct MeterBar: View {
    let fraction: Double
    let color: Color
    var trackColor: Color?
    @Environment(\.theme) private var theme

    var body: some View {
        GeometryReader { proxy in
            let clamped = min(1, max(0, fraction))
            ZStack(alignment: .leading) {
                Capsule().fill(trackColor ?? theme.track)
                Capsule()
                    .fill(color)
                    .frame(width: proxy.size.width * clamped)
            }
        }
        .animation(.spring(duration: 0.9, bounce: 0.05), value: fraction)
    }
}
