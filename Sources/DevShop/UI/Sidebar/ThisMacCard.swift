import SwiftUI

/// Hardware summary and the volume bar.
struct ThisMacCard: View {
    let info: SystemInfo
    let developmentBytes: Int64
    @Environment(\.theme) private var theme

    private var developmentFraction: Double {
        guard info.totalCapacity > 0 else { return 0 }
        return min(0.4, Double(developmentBytes) / Double(info.totalCapacity))
    }

    private var usedFraction: Double {
        guard info.totalCapacity > 0 else { return 0 }
        let used = Double(info.usedCapacity) / Double(info.totalCapacity)
        return max(0, used - developmentFraction)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("This Mac")
                    .font(.system(size: 11.5, weight: .semibold))
                    .fixedSize()
                Spacer(minLength: 0)
                Button {
                    NSWorkspace.shared.open(
                        URL(fileURLWithPath: "/System/Applications/Utilities/System Information.app"))
                } label: {
                    HStack(spacing: 3) {
                        Text("System Info")
                        SFIcon(symbol: "arrow.up.forward", size: 10.5, weight: .medium)
                    }
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(DevTheme.accent)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(DevTheme.accent.opacity(0.14), in: .rect(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 7)

            VStack(alignment: .leading, spacing: 1) {
                Text(info.hardwareLine)
                Text(info.chipLine)
                Text(info.osLine)
            }
            .font(.system(size: 11))
            .foregroundStyle(theme.faint)
            .lineLimit(1)
            .minimumScaleFactor(0.85)

            if info.totalCapacity > 0 {
                HStack {
                    Text("\(ByteFormat.full(info.usedCapacity)) used")
                    Spacer()
                    Text("\(ByteFormat.full(info.availableCapacity)) free")
                }
                .font(.system(size: 10.5))
                .foregroundStyle(theme.muted)
                .padding(.top, 9)
                .padding(.bottom, 4)

                StackedBar(segments: [
                    .init(fraction: usedFraction, color: Color(hex: "0a84ff")),
                    .init(fraction: developmentFraction, color: Color(hex: "ff9f0a"))
                ])
                .frame(height: 6)

                HStack(spacing: 9) {
                    legend("in use", Color(hex: "0a84ff"))
                    legend("dev \(ByteFormat.compact(developmentBytes))", Color(hex: "ff9f0a"))
                    legend("free", theme.track)
                }
                .padding(.top, 6)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .devCard(theme)
    }

    private func legend(_ label: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
        }
        .font(.system(size: 9.5))
        .foregroundStyle(theme.muted)
    }
}

/// A single track divided into proportional coloured segments.
struct StackedBar: View {
    struct Segment {
        var fraction: Double
        var color: Color
    }

    let segments: [Segment]
    @Environment(\.theme) private var theme

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    Rectangle()
                        .fill(segment.color)
                        .frame(width: proxy.size.width * min(1, max(0, segment.fraction)))
                }
                Spacer(minLength: 0)
            }
        }
        .background(theme.track)
        .clipShape(.capsule)
    }
}
