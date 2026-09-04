import SwiftUI

/// The small mark beside a tool's name when it has findings.
///
/// Shows the most severe tier, with a distinct shape per tier rather than colour alone.
/// Decorative by design — the row's accessibility label carries the same information, so a
/// screen reader is not made to announce an icon with no action behind it.
struct FindingBadge: View {
    let tier: FindingTier
    var size: CGFloat = 10

    var body: some View {
        SFIcon(symbol: tier.badgeSymbol, size: size, weight: .semibold)
            .foregroundStyle(Color(hex: tier.hex))
            .accessibilityHidden(true)
    }
}
