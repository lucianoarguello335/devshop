import SwiftUI

/// The 64pt progress ring and its summary line.
struct HealthRing: View {
    let score: Int
    let status: HealthStatus
    let label: String
    let summary: String
    let isScanning: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(theme.fill, lineWidth: 7.2)
                Circle()
                    .trim(from: 0, to: isScanning ? 0 : Double(score) / 100)
                    .stroke(Color(hex: status.hex),
                            style: StrokeStyle(lineWidth: 7.2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(duration: 0.9, bounce: 0.1), value: score)
                    .animation(.easeInOut(duration: 0.3), value: isScanning)
                    .animation(.easeInOut(duration: 0.45), value: status)
                Text(isScanning ? "··" : "\(score)")
                    .font(.system(size: 19, weight: .semibold))
                    .kerning(-0.38)
                    .contentTransition(.numericText())
            }
            .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 12.5, weight: .semibold))
                Text(summary)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Environment health \(score) out of 100. \(label). \(summary)")
    }
}
