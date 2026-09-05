import AppKit
import ImageIO
import UniformTypeIdentifiers

// Renders the DevShop app icon: a palette of nine tool-coloured squares on a plain tile.
//
// Two appearances are drawn from the same geometry, so the light and dark icons differ
// only in the tile colour and the swatch values — nothing shifts position between them.
// The dark one is the icon the app ships; the light one is kept for docs and reference.
//
// Two outputs come from the same drawing code:
//
//   swift Scripts/render-appicon.swift <light|dark> <outDir>          full iconset (.icns)
//   swift Scripts/render-appicon.swift <light|dark> <outDir> --layer  glyph only (.icon)
//
// The `.icon` bundle supplies the tile itself, so its layer carries only the swatches on a
// transparent canvas; the `.icns` path has to draw the tile as well.

/// Apple's icon grid: the rounded shape occupies 824 of a 1024 canvas, leaving room for
/// the shadow, with a corner radius of about 22.5% of the shape.
private let shapeRatio: CGFloat = 824.0 / 1024.0
private let cornerRatio: CGFloat = 0.225
/// Width of the three-by-three grid as a fraction of the tile.
private let gridRatio: CGFloat = 0.58
/// Gap between swatches as a fraction of one grid cell.
private let gapRatio: CGFloat = 0.20
/// Swatch corner radius as a fraction of the swatch.
private let swatchCornerRatio: CGFloat = 0.28

private func rgb(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: 1)
}

struct Appearance {
    let tile: NSColor
    /// Hairline around the tile. The light tile is close to a white Dock background, so it
    /// needs an edge; the dark one reads on its own.
    let edge: NSColor?
    /// Row-major, top-left first.
    let swatches: [NSColor]
}

private let dark = Appearance(
    tile: rgb(0x1C1C1E),
    edge: nil,
    swatches: [
        rgb(0x30D158), rgb(0xFF9F0A), rgb(0x0A84FF),
        rgb(0xFFD60A), rgb(0xFF453A), rgb(0xBF5AF2),
        rgb(0x40CBE0), rgb(0xFF6FA5), rgb(0xF2F2F7),
    ]
)

private let light = Appearance(
    tile: rgb(0xF2F2F5),
    edge: NSColor.black.withAlphaComponent(0.10),
    swatches: [
        rgb(0x2C6B3A), rgb(0xF57C00), rgb(0x3A56C8),
        rgb(0xE8B21C), rgb(0xB0173C), rgb(0x7B27B0),
        rgb(0x1B7E9E), rgb(0xF5387F), rgb(0x3A3A3C),
    ]
)

let args = CommandLine.arguments
guard args.count >= 3, let mode = ["light": light, "dark": dark][args[1]] else {
    FileHandle.standardError.write(Data("usage: render-appicon <light|dark> <outDir>\n".utf8))
    exit(2)
}
let outDir = URL(fileURLWithPath: args[2])
/// Icon Composer masks and fills the tile itself, so the layer it consumes is the swatches
/// alone on a transparent canvas.
let layerOnly = args.contains("--layer")

func render(size: Int) -> CGImage? {
    let s = CGFloat(size)
    guard let ctx = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high

    let tileSize = (s * shapeRatio).rounded()
    let origin = ((s - tileSize) / 2).rounded()
    let rect = CGRect(x: origin, y: origin, width: tileSize, height: tileSize)
    let radius = tileSize * cornerRatio
    let tile = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius,
                      transform: nil)

    // A soft shadow sits under the tile, as the macOS icon grid expects. Skipped at the
    // smallest sizes, where it costs contrast and buys nothing visible.
    if size >= 64, !layerOnly {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012),
                      blur: s * 0.03,
                      color: NSColor.black.withAlphaComponent(0.28).cgColor)
        ctx.addPath(tile)
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fillPath()
        ctx.restoreGState()
    }

    if !layerOnly {
        ctx.addPath(tile)
        ctx.setFillColor(mode.tile.cgColor)
        ctx.fillPath()
    }

    if let edge = mode.edge, size >= 32, !layerOnly {
        ctx.addPath(tile)
        ctx.setStrokeColor(edge.cgColor)
        ctx.setLineWidth(max(1, s * 0.004))
        ctx.strokePath()
    }

    // The nine swatches. Cell centres are spaced evenly across the grid square; each
    // swatch is inset by half the gap, so the outer edges land on the grid bounds.
    let grid = tileSize * gridRatio
    let gridOrigin = CGPoint(x: rect.midX - grid / 2, y: rect.midY - grid / 2)
    let cell = grid / 3
    let gap = cell * gapRatio
    let swatch = cell - gap
    let swatchRadius = swatch * swatchCornerRatio

    for row in 0..<3 {
        for column in 0..<3 {
            // Row 0 is the top row visually; Core Graphics puts y=0 at the bottom.
            let x = gridOrigin.x + CGFloat(column) * cell + gap / 2
            let y = gridOrigin.y + CGFloat(2 - row) * cell + gap / 2
            let box = CGRect(x: x, y: y, width: swatch, height: swatch)
            let path = CGPath(roundedRect: box, cornerWidth: swatchRadius,
                              cornerHeight: swatchRadius, transform: nil)
            ctx.addPath(path)
            ctx.setFillColor(mode.swatches[row * 3 + column].cgColor)
            ctx.fillPath()
        }
    }

    return ctx.makeImage()
}

func write(_ image: CGImage, to url: URL) throws {
    guard let dest = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil
    ) else { throw CocoaError(.fileWriteUnknown) }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
}

try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

// The ten entries `iconutil` expects in an iconset.
let sizes: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

if layerOnly {
    guard let image = render(size: 1024) else {
        FileHandle.standardError.write(Data("could not render the layer\n".utf8))
        exit(1)
    }
    let url = outDir.appendingPathComponent("swatches-\(args[1]).png")
    try write(image, to: url)
    print("wrote \(url.lastPathComponent)")
} else {
    for entry in sizes {
        guard let image = render(size: entry.pixels) else {
            FileHandle.standardError.write(Data("could not render \(entry.pixels)px\n".utf8))
            exit(1)
        }
        try write(image, to: outDir.appendingPathComponent("\(entry.name).png"))
    }
    print("wrote \(sizes.count) icons to \(outDir.path)")
}
