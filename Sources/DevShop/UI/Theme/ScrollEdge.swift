import SwiftUI

extension View {
    /// Suppresses the title-bar/toolbar background that macOS paints over the top of the
    /// window. The header draws its own opaque chrome colour, and without this the system's
    /// translucent panel washes out everything in the first 32pt.
    @ViewBuilder
    func withoutWindowBarBackground() -> some View {
        if #available(macOS 15.0, *) {
            toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        } else {
            self
        }
    }

    /// Turns off macOS 26's automatic scroll-edge effect.
    ///
    /// The window's content deliberately extends under the title bar, and the system reads
    /// that as pinned controls overlapping scrolling content, so it fades the top of every
    /// scroll view. The design has flat, opaque surfaces, so the effect is suppressed.
    /// Availability-gated because the deployment target is macOS 14.
    @ViewBuilder
    func withoutScrollEdgeEffect() -> some View {
        if #available(macOS 26.0, *) {
            scrollEdgeEffectHidden(true, for: .all)
        } else {
            self
        }
    }
}
