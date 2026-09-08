import AppKit
import SwiftUI

/// Real application icons, read from the bundles already on disk.
///
/// A cask stages an actual `.app`, so its own icon is available for free and is always
/// right — better than guessing a brand mark from the cask token. Icons are cached because
/// a list of fifty casks would otherwise hit the icon services on every redraw.
@MainActor
enum AppIconLoader {
    /// Icons are redrawn at the size they are actually shown, so a 20pt contents row costs a
    /// 40px bitmap on a Retina display and nothing more.
    ///
    /// `NSWorkspace.icon(forFile:)` hands back the whole icon family — representations up to
    /// 512pt — and setting `size` only changes how it draws, not what it holds on to. With a
    /// busy Caskroom that is tens of full icon families retained for the life of the process,
    /// so each one is redrawn once into a single small bitmap and the original is let go.
    private static let scale: CGFloat = 2

    private static var cache: [String: Image] = [:]
    /// Insertion order, for evicting the oldest entry once the cache is full. A plain cap is
    /// enough here: the working set is one container's contents list.
    private static var order: [String] = []
    private static let limit = 256

    /// The same bundle drawn at two sizes is two bitmaps, so the size is part of the key.
    static func icon(atBundlePath path: String, points: CGFloat = 20) -> Image? {
        let key = "\(path)@\(points)"
        if let cached = cache[key] { return cached }
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        guard let small = downsampled(NSWorkspace.shared.icon(forFile: path), points: points)
        else { return nil }
        let image = Image(nsImage: small)
        if order.count >= limit, let oldest = order.first {
            order.removeFirst()
            cache[oldest] = nil
        }
        cache[key] = image
        order.append(key)
        return image
    }

    /// Redraws an icon into one bitmap at the size it is actually shown.
    private static func downsampled(_ icon: NSImage, points: CGFloat) -> NSImage? {
        let pixels = Int(points * scale)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: pixels,
                                         pixelsHigh: pixels,
                                         bitsPerSample: 8,
                                         samplesPerPixel: 4,
                                         hasAlpha: true,
                                         isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0,
                                         bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        icon.draw(in: NSRect(x: 0, y: 0, width: CGFloat(pixels), height: CGFloat(pixels)),
                  from: .zero,
                  operation: .copy,
                  fraction: 1)
        NSGraphicsContext.restoreGraphicsState()

        // Declaring the representation as `points` across is what makes it a 2x rep.
        rep.size = NSSize(width: points, height: points)
        let image = NSImage(size: NSSize(width: points, height: points))
        image.addRepresentation(rep)
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
        } else if let slug = child.iconSlug, IconStore.has(slug) {
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
