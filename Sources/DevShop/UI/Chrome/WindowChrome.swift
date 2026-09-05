import AppKit
import SwiftUI

/// Configures the host `NSWindow` so the app's own 52pt header *is* the title bar.
///
/// `.windowStyle(.hiddenTitleBar)` alone still reserves the standard title bar and starts
/// the content below it, which left an empty band above the header and an empty gap beside
/// the traffic lights. Turning on `fullSizeContentView` moves the content up under the
/// title bar, but AppKit's title bar strip keeps painting over it — `titlebarAppearsTransparent`
/// does not stop that here, so the header showed through washed out.
///
/// The fix is to hide the strip outright and let `WindowControls` draw the close, minimise
/// and zoom buttons in the header instead, which is also what the design does.
/// Whether the app's window is currently full screen.
///
/// The header draws its own traffic lights, so it has to ask AppKit rather than being told.
@MainActor
enum FullScreen {
    static var isActive: Bool {
        let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first
        return window?.styleMask.contains(.fullScreen) ?? false
    }
}

/// What a double-click on the title bar should do.
///
/// AppKit's title bar normally provides this, but DevShop hides it so the header can own
/// that band, which took the behaviour with it. The system setting is honoured rather than
/// assuming zoom: System Settings › Desktop & Dock offers Zoom, Minimise or nothing, and a
/// window that ignores it feels broken to anyone who changed it.
@MainActor
enum TitleBarDoubleClick {
    static func perform() {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first else {
            return
        }
        switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
        // The `perform` variants match what a real title-bar click does, including the
        // window-delegate hooks. Confirmed working with the zoom button hidden.
        case "Minimize": window.performMiniaturize(nil)
        case "None": break
        default: window.performZoom(nil)   // "Maximize", and the default when unset
        }
    }
}

struct WindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = AttachmentView()
        // `window` is nil while the view is being created, so the coordinator attaches from
        // viewDidMoveToWindow rather than guessing at a delay.
        view.onMoveToWindow = { [coordinator = context.coordinator] window in
            guard let window else { return }
            coordinator.attach(to: window)
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        if let window = view.window { context.coordinator.attach(to: window) }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// A zero-sized view whose only job is to report when it lands in a window.
    private final class AttachmentView: NSView {
        var onMoveToWindow: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onMoveToWindow?(window)
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        private static let autosaveName = NSWindow.FrameAutosaveName("DevShopMain")
        private weak var window: NSWindow?
        private var hasSavedFrame = false
        private var didApplyDefaultFrame = false

        func attach(to window: NSWindow) {
            guard self.window !== window else {
                apply()
                return
            }
            self.window = window

            // The content is greedy, so left alone the window opens filling the screen.
            // Restore the remembered frame, or fall back to the design's 1180x790 centred,
            // and let AppKit persist it from then on.
            hasSavedFrame = window.setFrameUsingName(Self.autosaveName)
            window.setFrameAutosaveName(Self.autosaveName)

            // A remembered frame can point at a display that is no longer attached, or sit
            // with its title bar above the menu bar where it cannot be dragged back. Pull it
            // onto a visible screen rather than trusting it blindly.
            if hasSavedFrame, !Self.isUsable(window.frame) {
                window.setContentSize(NSSize(width: 1180, height: 790))
                window.center()
            }

            // Target/selector observers unregister themselves when the coordinator goes
            // away, which the block form would not.
            // Deliberately not didResize: that fires continuously while dragging an edge or
            // zooming the window, and re-running the chrome work on every frame is what made
            // resizing stutter. The title bar does not come back mid-resize.
            for name: NSNotification.Name in [
                NSWindow.didEndLiveResizeNotification,
                NSWindow.didBecomeKeyNotification,
                NSWindow.didEnterFullScreenNotification,
                NSWindow.didExitFullScreenNotification
            ] {
                NotificationCenter.default.addObserver(
                    self, selector: #selector(windowChanged), name: name, object: window)
            }
            apply()
        }

        /// A frame is usable when its title bar is inside some screen's visible area, so
        /// the window can still be moved by hand.
        private static func isUsable(_ frame: NSRect) -> Bool {
            NSScreen.screens.contains { screen in
                let visible = screen.visibleFrame
                let titleBar = NSRect(x: frame.minX, y: frame.maxY - 52,
                                      width: frame.width, height: 52)
                return visible.intersects(titleBar) && visible.contains(NSPoint(x: frame.midX,
                                                                                y: frame.maxY - 26))
            }
        }

        @objc private func windowChanged() { apply() }

        /// Re-applied on every layout pass: SwiftUI's window controller restores the title
        /// bar when the scene updates, and it would paint over the header again.
        private func apply() {
            guard let window else { return }

            window.styleMask.insert(.fullSizeContentView)
            // Hiding the title bar strip also took the zoom button with it, and AppKit reads
            // that button to decide whether a window can go full screen. Ask for it outright
            // so the green button in the header, the View menu and the F-key all work.
            window.collectionBehavior.insert(.fullScreenPrimary)
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            // The header is our own view, so dragging it has to move the window.
            window.isMovableByWindowBackground = true

            for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                window.standardWindowButton(type)?.isHidden = true
            }
            // Hiding the buttons leaves the strip itself, which is what washes out the
            // header. `WindowControls` replaces everything it provided.
            window.standardWindowButton(.closeButton)?.superview?.superview?.isHidden = true

            // SwiftUI sizes the window to fit its (greedy) content some time after the view
            // lands in it, so the design's size has to be applied after that pass rather
            // than during attach. Only on a first run — a remembered frame wins.
            // Nothing to size or centre while the window owns the whole screen, and doing it
            // there would fight the full-screen transition.
            if !hasSavedFrame && !didApplyDefaultFrame && !window.styleMask.contains(.fullScreen) {
                didApplyDefaultFrame = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak window] in
                    guard let window else { return }
                    window.setContentSize(NSSize(width: 1180, height: 790))
                    window.center()
                }
            }

        }
    }
}
