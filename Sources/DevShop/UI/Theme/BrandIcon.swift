import SwiftUI

/// The brand marks bundled with the app, keyed by Simple Icons slug.
///
/// Icon files come from Simple Icons and are CC0; the trademarks they depict belong to
/// their respective owners. `Scripts/fetch-icons.sh` regenerates `icons.json`.
@MainActor
enum IconStore {
    private static let pathData: [String: String] = {
        guard let url = Bundle.module.url(forResource: "icons", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let map = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return map
    }()

    /// Parsed paths are cached because a mark is drawn on every tile redraw.
    private static var cache: [String: Path] = [:]

    static func path(for slug: String?) -> Path? {
        guard let slug else { return nil }
        if let cached = cache[slug] { return cached }
        guard let data = pathData[slug], let parsed = SVGPath.parse(data) else { return nil }
        cache[slug] = parsed
        return parsed
    }
}

/// A Simple Icons mark scaled into the given size, or the tool's SF Symbol when no mark
/// exists for it.
struct BrandMark: View {
    let slug: String?
    let symbol: String
    let size: CGFloat

    var body: some View {
        if let path = IconStore.path(for: slug) {
            SVGShape(path: path)
                .frame(width: size, height: size)
        } else {
            SFIcon(symbol: symbol, size: size * 0.82, weight: .semibold)
                .frame(width: size, height: size)
        }
    }
}

/// Fits a 24×24 Simple Icons path into whatever rectangle it is given.
private struct SVGShape: Shape {
    let path: Path
    /// Measured once at construction. `boundingRect` walks the whole path, and `path(in:)`
    /// is called on every layout and draw pass — with a mark on every tile that added up.
    let bounds: CGRect

    init(path: Path) {
        self.path = path
        self.bounds = path.boundingRect
    }

    func path(in rect: CGRect) -> Path {
        guard bounds.width > 0, bounds.height > 0 else { return path }
        let scale = min(rect.width / bounds.width, rect.height / bounds.height)
        let dx = rect.midX - (bounds.midX * scale)
        let dy = rect.midY - (bounds.midY * scale)
        return path.applying(CGAffineTransform(scaleX: scale, y: scale)
            .concatenating(CGAffineTransform(translationX: dx, y: dy)))
    }
}

/// The rounded, brand-tinted chip a mark sits on. Used at 30pt on tiles and 52pt in the
/// inspector, exactly as the design specifies.
struct IconChip: View {
    let tool: DetectedTool
    let size: CGFloat
    let theme: DevTheme

    private var isMissing: Bool { tool.status == .missing }
    private var brand: Color { Color(hex: tool.definition.color) }
    private var radius: CGFloat { size * 0.26 }

    var body: some View {
        BrandMark(slug: tool.definition.icon,
                  symbol: tool.definition.symbol,
                  size: size * 0.56)
            .foregroundStyle(isMissing ? AnyShapeStyle(theme.muted) : AnyShapeStyle(.white))
            .frame(width: size, height: size)
            .background {
                if isMissing {
                    RoundedRectangle(cornerRadius: radius).fill(theme.fillStrong)
                } else {
                    RoundedRectangle(cornerRadius: radius)
                        .fill(LinearGradient(
                            colors: [brand, brand.opacity(0.8)],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                }
            }
            .shadow(color: isMissing ? .clear : brand.opacity(0.33),
                    radius: size * 0.1, y: size * 0.05)
    }
}
