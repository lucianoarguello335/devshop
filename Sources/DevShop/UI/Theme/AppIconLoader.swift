import AppKit
import SwiftUI

/// Real application icons, read from the bundles already on disk.
///
/// A cask stages an actual `.app`, so its own icon is available for free and is always
/// right — better than guessing a brand mark from the cask token. Icons are cached because
/// a list of fifty casks would otherwise hit the icon services on every redraw.
@MainActor
enum AppIconLoader {
    private static var cache: [String: Image] = [:]

    static func icon(atBundlePath path: String) -> Image? {
        if let cached = cache[path] { return cached }
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let native = NSWorkspace.shared.icon(forFile: path)
        // 64pt is comfortably above the 20pt the rows draw at on a Retina display.
        native.size = NSSize(width: 64, height: 64)
        let image = Image(nsImage: native)
        cache[path] = image
        return image
    }
}

/// The small square shown beside a package in a contents list.
///
/// Three sources, in descending order of fidelity: the installed application's own icon, a
/// bundled brand mark, and finally a tinted monogram.
struct ChildIcon: View {
    let child: ToolChild
    var size: CGFloat = 20
    @Environment(\.theme) private var theme

    private var tint: Color { Color(hex: child.color) }

    var body: some View {
        if let path = child.appBundlePath, let icon = AppIconLoader.icon(atBundlePath: path) {
            icon.resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        } else if let slug = child.iconSlug, IconStore.path(for: slug) != nil {
            BrandMark(slug: slug, symbol: "shippingbox.fill", size: size * 0.62)
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(tint, in: .rect(cornerRadius: size * 0.26))
        } else {
            Text(child.monogram)
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(tint.opacity(0.9), in: .rect(cornerRadius: size * 0.26))
        }
    }
}
