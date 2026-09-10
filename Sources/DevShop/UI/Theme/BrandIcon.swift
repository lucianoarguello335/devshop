import SwiftUI

/// The brand marks bundled with the app, keyed by Simple Icons slug.
///
/// Icon files come from Simple Icons and are CC0; the trademarks they depict belong to
/// their respective owners. `Scripts/fetch-icons.sh` regenerates `icons.json`.
@MainActor
enum IconStore {
    private static var pathData: [String: String] = {
        // Mapped rather than read: the file is a quarter of a megabyte and every entry is
        // dropped again as soon as it has been parsed, so it never needs to be resident.
        guard let url = ResourceBundle.url(forResource: "icons", withExtension: "json"),
              let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let map = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return map
    }()

    /// Marks already fitted to a size they are drawn at. A mark is drawn on every tile and
    /// every table row, and fitting one walks and transforms the whole path, so both the parse
    /// and the fit are done once per size rather than on every layout and draw pass.
    private struct FitKey: Hashable {
        var slug: String
        var width: CGFloat
        var height: CGFloat
    }

    private static var fitted: [FitKey: Path] = [:]
    /// Slugs with no usable mark, so a miss is not re-parsed on every redraw.
    private static var missing: Set<String> = []

    /// The mark for `slug`, scaled and centred in a rectangle of `size`.
    static func path(for slug: String?, fittedIn size: CGSize) -> Path? {
        guard let slug, !missing.contains(slug) else { return nil }
        let key = FitKey(slug: slug, width: size.width, height: size.height)
        if let cached = fitted[key] { return cached }
        guard let parsed = parsed(slug) else { return nil }
        let result = fit(parsed, in: CGRect(origin: .zero, size: size))
        fitted[key] = result
        return result
    }

    /// Whether a mark exists at all, for callers that only need to choose a fallback.
    static func has(_ slug: String) -> Bool { parsed(slug) != nil }

    private static var parsedCache: [String: Path] = [:]

    private static func parsed(_ slug: String) -> Path? {
        if let cached = parsedCache[slug] { return cached }
        if missing.contains(slug) { return nil }
        guard let data = pathData[slug], let path = SVGPath.parse(data) else {
            missing.insert(slug)
            return nil
        }
        parsedCache[slug] = path
        // The source string has served its purpose; the parsed path is what gets drawn.
        pathData[slug] = nil
        return path
    }

    /// Fits a 24x24 Simple Icons path into the given rectangle, preserving its aspect ratio.
    private static func fit(_ path: Path, in rect: CGRect) -> Path {
        let bounds = path.boundingRect
        guard bounds.width > 0, bounds.height > 0 else { return path }
        let scale = min(rect.width / bounds.width, rect.height / bounds.height)
        let dx = rect.midX - (bounds.midX * scale)
        let dy = rect.midY - (bounds.midY * scale)
        return path.applying(CGAffineTransform(scaleX: scale, y: scale)
            .concatenating(CGAffineTransform(translationX: dx, y: dy)))
    }
}

/// A Simple Icons mark scaled into the given size, or the tool's SF Symbol when no mark
/// exists for it.
struct BrandMark: View {
    let slug: String?
    let symbol: String
    let size: CGFloat

    var body: some View {
        if let path = IconStore.path(for: slug, fittedIn: CGSize(width: size, height: size)) {
            FittedPath(path: path)
                .frame(width: size, height: size)
        } else {
            SFIcon(symbol: symbol, size: size * 0.82, weight: .semibold)
                .frame(width: size, height: size)
        }
    }
}

/// Draws an already-fitted path. Nothing is measured or transformed at draw time.
private struct FittedPath: Shape {
    let path: Path

    func path(in rect: CGRect) -> Path { path }
}

/// The rounded, brand-tinted chip a mark sits on. Used at 30pt on tiles and 52pt in the
/// inspector, exactly as the design specifies.
struct IconChip: View {
    let slug: String?
    let symbol: String
    /// Brand colour as a six-digit hex string.
    let colorHex: String
    let isMissing: Bool
    let size: CGFloat
    let theme: DevTheme
    /// The brand glow costs an offscreen pass per chip. Worth it once in the inspector; not
    /// worth it on every one of a hundred-odd tiles and rows.
    var glow: Bool = false

    init(tile: TileData, size: CGFloat, theme: DevTheme, glow: Bool = false) {
        self.init(slug: tile.iconSlug, symbol: tile.symbol, colorHex: tile.colorHex,
                  isMissing: tile.isMissing, size: size, theme: theme, glow: glow)
    }

    init(tool: DetectedTool, size: CGFloat, theme: DevTheme, glow: Bool = false) {
        self.init(slug: tool.definition.icon, symbol: tool.definition.symbol,
                  colorHex: tool.definition.color, isMissing: tool.status == .missing,
                  size: size, theme: theme, glow: glow)
    }

    init(slug: String?,
         symbol: String,
         colorHex: String,
         isMissing: Bool,
         size: CGFloat,
         theme: DevTheme,
         glow: Bool = false) {
        self.slug = slug
        self.symbol = symbol
        self.colorHex = colorHex
        self.isMissing = isMissing
        self.size = size
        self.theme = theme
        self.glow = glow
    }

    private var brand: Color { Color(hex: colorHex) }
    private var radius: CGFloat { size * 0.26 }

    var body: some View {
        BrandMark(slug: slug, symbol: symbol, size: size * 0.56)
            .foregroundStyle(isMissing ? AnyShapeStyle(theme.muted) : AnyShapeStyle(.white))
            .frame(width: size, height: size)
            .background {
                if isMissing {
                    RoundedRectangle(cornerRadius: radius).fill(theme.fillStrong)
                } else {
                    RoundedRectangle(cornerRadius: radius)
                        .fill(gradient)
                }
            }
    }

    private var gradient: some ShapeStyle {
        let base = LinearGradient(colors: [brand, brand.opacity(0.8)],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
        return glow
            ? AnyShapeStyle(base.shadow(.drop(color: brand.opacity(0.33),
                                              radius: size * 0.1, y: size * 0.05)))
            : AnyShapeStyle(base)
    }
}
