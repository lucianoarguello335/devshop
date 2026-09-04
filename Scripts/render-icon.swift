import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

// Renders DevShop.icns from a single-path SVG glyph.
//
// Run through `Scripts/make-icon.sh`, which compiles this alongside the app's own
// SVGPath parser so the glyph is drawn from the same vector data the UI uses.
//
//   swift Sources/DevShop/UI/Theme/SVGPath.swift Scripts/render-icon.swift <svg> <outDir>

/// Apple's icon grid: the rounded shape occupies 824 of a 1024 canvas, leaving room for
/// the shadow, with a corner radius of about 22.5% of the shape.
private let shapeRatio: CGFloat = 824.0 / 1024.0
private let cornerRatio: CGFloat = 0.225
private let glyphRatio: CGFloat = 0.50

private let light = NSColor(srgbRed: 143 / 255, green: 131 / 255, blue: 188 / 255, alpha: 1)
private let dark = NSColor(srgbRed: 103 / 255, green: 91 / 255, blue: 144 / 255, alpha: 1)

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write(Data("usage: render-icon <svg> <outDir>\n".utf8))
    exit(2)
}
let svgURL = URL(fileURLWithPath: args[1])
let outDir = URL(fileURLWithPath: args[2])

let svg = try String(contentsOf: svgURL, encoding: .utf8)

/// Pulls the `d` attribute out of the first `<path>`. Matching on `d="` alone is not enough:
/// uxwing's files carry an `id="Layer_1"` whose own text contains that sequence.
func pathData(in markup: String) -> String? {
    let pattern = try? NSRegularExpression(pattern: #"<path[^>]*\sd="([^"]+)""#,
                                           options: .dotMatchesLineSeparators)
    let range = NSRange(markup.startIndex..., in: markup)
    guard let match = pattern?.firstMatch(in: markup, range: range),
          let group = Range(match.range(at: 1), in: markup) else { return nil }
    return String(markup[group])
}

guard let d = pathData(in: svg), let parsed = SVGPath.parse(d) else {
    FileHandle.standardError.write(Data("could not parse a path from \(svgURL.path)\n".utf8))
    exit(1)
}
let glyph = parsed.cgPath
let glyphBounds = glyph.boundingBoxOfPath

func render(size: Int) -> CGImage? {
    let s = CGFloat(size)
    guard let ctx = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high

    let shapeSize = (s * shapeRatio).rounded()
    let origin = ((s - shapeSize) / 2).rounded()
    let rect = CGRect(x: origin, y: origin, width: shapeSize, height: shapeSize)
    let radius = shapeSize * cornerRatio
    let shape = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius,
                       transform: nil)

    // A soft shadow sits under the tile, as the macOS icon grid expects.
    if size >= 64 {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012),
                      blur: s * 0.03,
                      color: NSColor.black.withAlphaComponent(0.28).cgColor)
        ctx.addPath(shape)
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fillPath()
        ctx.restoreGState()
    }

    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [light.cgColor, dark.cgColor] as CFArray,
                              locations: [0, 1])!
    // Top-left to bottom-right, matching the tiles inside the app.
    ctx.drawLinearGradient(gradient,
                           start: CGPoint(x: rect.minX, y: rect.maxY),
                           end: CGPoint(x: rect.maxX, y: rect.minY),
                           options: [])
    ctx.restoreGState()

    // The glyph, scaled to fit and centred. The SVG's y axis points down, so it is flipped.
    let target = shapeSize * glyphRatio
    let scale = min(target / glyphBounds.width, target / glyphBounds.height)
    var transform = CGAffineTransform.identity
        .translatedBy(x: rect.midX, y: rect.midY)
        .scaledBy(x: scale, y: -scale)
        .translatedBy(x: -glyphBounds.midX, y: -glyphBounds.midY)
    guard let placed = glyph.copy(using: &transform) else { return nil }
    ctx.addPath(placed)
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fillPath()

    return ctx.makeImage()
}

// The sizes `iconutil` expects in an .iconset.
let variants: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024)
]

try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
for (name, size) in variants {
    guard let image = render(size: size) else {
        FileHandle.standardError.write(Data("failed to render \(name)\n".utf8))
        exit(1)
    }
    let url = outDir.appendingPathComponent("\(name).png")
    guard let dest = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil) else { exit(1) }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}
print("rendered \(variants.count) sizes into \(outDir.lastPathComponent)")
