import SwiftUI

/// A brief confirmation that fades in over the content and dismisses itself.
///
/// Deliberately not a sheet or an alert: copying to the clipboard needs acknowledging, not
/// interrupting, and nothing about it requires a response.
struct ToastView: View {
    let message: String
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 7) {
            SFIcon(symbol: "checkmark.circle.fill", size: 12, weight: .semibold)
                .foregroundStyle(Color(hex: "30d158"))
            Text(message)
                .font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(theme.card, in: .capsule)
        .overlay {
            Capsule().strokeBorder(theme.hairline, lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        .accessibilityLabel(message)
    }
}
