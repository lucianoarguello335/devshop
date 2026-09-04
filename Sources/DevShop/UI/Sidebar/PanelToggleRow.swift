import SwiftUI

/// One row of the PANELS list: chip, title, count, switch.
struct PanelToggleRow: View {
    let symbol: String
    let title: String
    let count: Int
    let isOn: Bool
    let accent: Color
    /// Clicking the row jumps the centre column to that section.
    let select: () -> Void
    /// Only the switch changes whether the section is shown, which is what it looks like it
    /// does. Previously the whole row toggled, leaving nothing to click to navigate.
    let toggle: () -> Void

    @Environment(\.theme) private var theme
    @State private var isHovering = false

    var body: some View {
        Button(action: select) {
            HStack(spacing: 9) {
                SFIcon(symbol: symbol, size: 10, weight: .semibold)
                    .foregroundStyle(isOn ? accent : theme.muted)
                    .frame(width: 20, height: 20)
                    .background(isOn ? accent.opacity(0.16) : theme.fill,
                                in: .rect(cornerRadius: 6))
                Text(title)
                    .font(.system(size: 12.5))
                    .foregroundStyle(isOn ? theme.text : theme.muted)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                Text("\(count)")
                    .font(.system(size: 10.5))
                    .monospacedDigit()
                    .foregroundStyle(theme.muted)
                Button(action: toggle) {
                    MiniSwitch(isOn: isOn)
                }
                .buttonStyle(.plain)
                .help(isOn ? "Hide this panel" : "Show this panel")
                .accessibilityLabel("Show \(title)")
                .accessibilityValue(isOn ? "on" : "off")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(isHovering ? theme.fill : .clear, in: .rect(cornerRadius: 7))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel("\(title), \(count) items")
        .accessibilityHint("Scrolls to this section")
    }
}

/// The 28×16 switch from the design — smaller than any stock control, so it is drawn.
struct MiniSwitch: View {
    let isOn: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        Capsule()
            .fill(isOn ? Color(hex: "30d158") : theme.fillStrong)
            .frame(width: 28, height: 16)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
                    .frame(width: 12, height: 12)
                    .padding(2)
            }
            .animation(.spring(duration: 0.22, bounce: 0.2), value: isOn)
    }
}
