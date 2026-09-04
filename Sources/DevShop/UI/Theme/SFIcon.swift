import SwiftUI

/// An SF Symbol that paints where it was laid out.
///
/// SwiftUI coalesces position changes from ancestors and lets leaf views resolve their own
/// frame, which left bare `Image(systemName:)` glyphs in this window drawing several points
/// away from the box they belong to — the appearance switch's sun sat outside its own
/// background, and the "System Info" arrow floated free of its button. `geometryGroup()`
/// makes the parent resolve the frame first and hand it down, which is exactly the barrier
/// the symbol needs. Every symbol in the app goes through this view so the fix cannot be
/// forgotten at a call site.
struct SFIcon: View {
    let symbol: String
    var size: CGFloat = 11
    var weight: Font.Weight = .regular

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: weight))
            .geometryGroup()
    }
}
