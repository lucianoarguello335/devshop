import AppKit

/// Keeps the Dock icon in step with the appearance the window is actually drawing.
///
/// A bundle carries one `CFBundleIconFile`, so `DevShop.icns` — the light icon — is what
/// Finder and the Dock show before launch. Once running, the app owns its Dock tile, and
/// swapping the image there is the only way macOS offers to vary an icon by appearance.
///
/// The cost of that is visible: in dark mode the tile changes from light to dark the moment
/// the app opens, and back when it quits. That is accepted here — a window drawing dark
/// under a light Dock icon reads worse than the one-time change at launch.
///
/// The appearance comes from the same value the whole window reads, so the icon follows
/// the title bar's light/dark switch as well as the system setting.
@MainActor
enum DockIcon {
    /// Decoding a multi-representation `.icns` is not free, and the appearance can flip
    /// repeatedly while someone plays with the switch.
    private static var cache: [DevTheme.Appearance: NSImage] = [:]
    private static var current: DevTheme.Appearance?

    static func apply(_ appearance: DevTheme.Appearance) {
        installTerminationReset()
        guard appearance != current else { return }
        guard let image = icon(for: appearance) else { return }
        current = appearance
        NSApplication.shared.applicationIconImage = image
    }

    /// The Dock keeps whatever image the app last set, even after the process is gone: a
    /// pinned DevShop that quit while dark went on showing the dark tile against a light
    /// Dock. Handing the icon back at termination — `applicationIconImage = nil` restores
    /// the original, per AppKit — lets the bundle's own `CFBundleIconFile` stand again.
    ///
    /// A crash or a force-quit skips this and leaves the tile stale until the Dock next
    /// restarts. There is no notification for those, so it is as far as this goes.
    private static var resetInstalled = false

    private static func installTerminationReset() {
        guard !resetInstalled else { return }
        resetInstalled = true
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { NSApplication.shared.applicationIconImage = nil }
        }
    }

    private static func icon(for appearance: DevTheme.Appearance) -> NSImage? {
        if let cached = cache[appearance] { return cached }
        // `swift run` produces a bare executable with no bundle; the icon is a packaging
        // detail, so its absence is not worth reporting.
        let name = appearance == .dark ? "DevShop-Dark" : "DevShop"
        guard let url = Bundle.main.url(forResource: name, withExtension: "icns"),
              let image = NSImage(contentsOf: url) else { return nil }
        cache[appearance] = image
        return image
    }
}
