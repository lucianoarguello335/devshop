import AppKit
import SwiftUI

/// The close / minimise / full screen buttons, drawn by the app.
///
/// `WindowChrome` hides AppKit's own title bar, because that strip paints over the header
/// no matter how transparent it is asked to be. These are real controls wired to the same
/// window actions — not decoration — and they can sit exactly where the design puts them.
struct WindowControls: View {
    @Environment(\.controlActiveState) private var activeState
    @State private var isHovering = false
    /// Drives the green button's glyph, which points inwards once the window is full screen.
    @State private var isFullScreen = false

    private var isActive: Bool { activeState != .inactive }

    var body: some View {
        HStack(spacing: 8) {
            control(.close, fill: Color(hex: "ff5f57"), symbol: "xmark", label: "Close")
            control(.miniaturize, fill: Color(hex: "febc2e"), symbol: "minus", label: "Minimise")
            control(.fullScreen, fill: Color(hex: "28c840"),
                    symbol: isFullScreen ? "arrow.down.right.and.arrow.up.left"
                                         : "arrow.up.left.and.arrow.down.right",
                    label: isFullScreen ? "Exit Full Screen" : "Enter Full Screen")
        }
        .onHover { isHovering = $0 }
        .onAppear { isFullScreen = FullScreen.isActive }
        .onReceive(NotificationCenter.default.publisher(
            for: NSWindow.didEnterFullScreenNotification)) { _ in isFullScreen = true }
        .onReceive(NotificationCenter.default.publisher(
            for: NSWindow.didExitFullScreenNotification)) { _ in isFullScreen = false }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .animation(.easeOut(duration: 0.18), value: isActive)
    }

    private enum Action { case close, miniaturize, fullScreen }

    private func control(_ action: Action,
                         fill: Color,
                         symbol: String,
                         label: String) -> some View {
        Button {
            perform(action)
        } label: {
            Circle()
                .fill(isActive ? fill : Color(hex: "8e8e93").opacity(0.45))
                .frame(width: 12, height: 12)
                .overlay {
                    // macOS only reveals the glyphs while the pointer is over the group.
                    SFIcon(symbol: symbol, size: action == .fullScreen ? 6 : 7, weight: .black)
                        .foregroundStyle(.black.opacity(0.55))
                        .opacity(isHovering && isActive ? 1 : 0)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func perform(_ action: Action) {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first else { return }
        switch action {
        case .close: window.performClose(nil)
        case .miniaturize: window.performMiniaturize(nil)
        // The green button is Full Screen, as it is everywhere else on macOS; holding
        // Option turns it back into Zoom, which is the same rule AppKit applies.
        case .fullScreen:
            if NSApp.currentEvent?.modifierFlags.contains(.option) == true {
                window.performZoom(nil)
            } else {
                window.toggleFullScreen(nil)
            }
        }
    }
}
