import AppKit

/// Keeps the Dock icon in step with the appearance the window is actually drawing.
///
/// A bundle carries one `CFBundleIconFile`, so `DevShop.icns` — the light icon — is what
/// Finder and the Dock show before launch. Once running, the app owns its Dock tile, and
/// swapping the image there is the only way to get a dark variant on macOS: an Icon
/// Composer `.icon` renders its dark appearance from a system background and cannot vary
/// its layer artwork per appearance, which is exactly what these two icons do.
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
        guard appearance != current else { return }
        guard let image = icon(for: appearance) else { return }
        current = appearance
        NSApplication.shared.applicationIconImage = image
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
