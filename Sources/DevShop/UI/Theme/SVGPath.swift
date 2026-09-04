import CoreGraphics
import SwiftUI

/// Parses SVG path data into a SwiftUI `Path`.
///
/// Simple Icons ships every brand mark as a single `<path>` on a 24×24 canvas, so a small
/// parser is all that stands between the downloaded data and a crisp vector at any size —
/// no image assets, no asset catalog, no rasterisation.
enum SVGPath {
    /// Returns `nil` for data the parser cannot make sense of, so the caller can fall back
    /// to an SF Symbol rather than draw something wrong.
    static func parse(_ data: String) -> Path? {
        var scanner = Scanner(data)
        var path = Path()
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        /// Reflection of the previous cubic/quadratic control point, for S and T.
        var lastCubicControl: CGPoint?
        var lastQuadControl: CGPoint?
        var command: Character?
        var didDraw = false

        func point(_ x: CGFloat, _ y: CGFloat, relative: Bool) -> CGPoint {
            relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
        }

        while true {
            scanner.skipSeparators()
            if scanner.isAtEnd { break }

            if let next = scanner.peekCommand() {
                command = next
                scanner.advance()
            } else if command == nil {
                return nil                      // data must begin with a command
            } else if command == "M" || command == "m" {
                command = command == "M" ? "L" : "l"   // repeated moveto pairs are linetos
            }

            guard let cmd = command else { return nil }
            let relative = cmd.isLowercase
            let upper = Character(cmd.uppercased())

            switch upper {
            case "M":
                guard let x = scanner.number(), let y = scanner.number() else { return nil }
                current = point(x, y, relative: relative)
                subpathStart = current
                path.move(to: current)
                lastCubicControl = nil; lastQuadControl = nil

            case "L":
                guard let x = scanner.number(), let y = scanner.number() else { return nil }
                current = point(x, y, relative: relative)
                path.addLine(to: current)
                didDraw = true
                lastCubicControl = nil; lastQuadControl = nil

            case "H":
                guard let x = scanner.number() else { return nil }
                current = CGPoint(x: relative ? current.x + x : x, y: current.y)
                path.addLine(to: current)
                didDraw = true
                lastCubicControl = nil; lastQuadControl = nil

            case "V":
                guard let y = scanner.number() else { return nil }
                current = CGPoint(x: current.x, y: relative ? current.y + y : y)
                path.addLine(to: current)
                didDraw = true
                lastCubicControl = nil; lastQuadControl = nil

            case "C":
                guard let x1 = scanner.number(), let y1 = scanner.number(),
                      let x2 = scanner.number(), let y2 = scanner.number(),
                      let x = scanner.number(), let y = scanner.number() else { return nil }
                let c1 = point(x1, y1, relative: relative)
                let c2 = point(x2, y2, relative: relative)
                current = point(x, y, relative: relative)
                path.addCurve(to: current, control1: c1, control2: c2)
                didDraw = true
                lastCubicControl = c2; lastQuadControl = nil

            case "S":
                guard let x2 = scanner.number(), let y2 = scanner.number(),
                      let x = scanner.number(), let y = scanner.number() else { return nil }
                let c1 = reflect(lastCubicControl, about: current)
                let c2 = point(x2, y2, relative: relative)
                current = point(x, y, relative: relative)
                path.addCurve(to: current, control1: c1, control2: c2)
                didDraw = true
                lastCubicControl = c2; lastQuadControl = nil

            case "Q":
                guard let x1 = scanner.number(), let y1 = scanner.number(),
                      let x = scanner.number(), let y = scanner.number() else { return nil }
                let c = point(x1, y1, relative: relative)
                current = point(x, y, relative: relative)
                path.addQuadCurve(to: current, control: c)
                didDraw = true
                lastQuadControl = c; lastCubicControl = nil

            case "T":
                guard let x = scanner.number(), let y = scanner.number() else { return nil }
                let c = reflect(lastQuadControl, about: current)
                current = point(x, y, relative: relative)
                path.addQuadCurve(to: current, control: c)
                didDraw = true
                lastQuadControl = c; lastCubicControl = nil

            case "A":
                guard let rx = scanner.number(), let ry = scanner.number(),
                      let rotation = scanner.number(),
                      let largeArc = scanner.flag(), let sweep = scanner.flag(),
                      let x = scanner.number(), let y = scanner.number() else { return nil }
                let end = point(x, y, relative: relative)
                appendArc(to: &path, from: current, to: end, rx: rx, ry: ry,
                          rotationDegrees: rotation, largeArc: largeArc, sweep: sweep)
                current = end
                didDraw = true
                lastCubicControl = nil; lastQuadControl = nil

            case "Z":
                path.closeSubpath()
                current = subpathStart
                lastCubicControl = nil; lastQuadControl = nil

            default:
                return nil
            }
        }

        return didDraw ? path : nil
    }

    private static func reflect(_ control: CGPoint?, about anchor: CGPoint) -> CGPoint {
        guard let control else { return anchor }
        return CGPoint(x: 2 * anchor.x - control.x, y: 2 * anchor.y - control.y)
    }

    /// Endpoint-parameterised elliptical arc, converted to cubic segments using the
    /// procedure in the SVG specification's implementation notes (F.6.5).
    private static func appendArc(to path: inout Path,
                                  from start: CGPoint,
                                  to end: CGPoint,
                                  rx: CGFloat, ry: CGFloat,
                                  rotationDegrees: CGFloat,
                                  largeArc: Bool, sweep: Bool) {
        if start == end { return }
        var rx = abs(rx), ry = abs(ry)
        if rx == 0 || ry == 0 {
            path.addLine(to: end)
            return
        }

        let phi = rotationDegrees * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)
        let dx2 = (start.x - end.x) / 2, dy2 = (start.y - end.y) / 2
        let x1p = cosPhi * dx2 + sinPhi * dy2
        let y1p = -sinPhi * dx2 + cosPhi * dy2

        // Scale the radii up if they are too small to span the endpoints.
        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 {
            let scale = sqrt(lambda)
            rx *= scale
            ry *= scale
        }

        let sign: CGFloat = largeArc == sweep ? -1 : 1
        let numerator = max(0, rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p)
        let denominator = rx * rx * y1p * y1p + ry * ry * x1p * x1p
        let coefficient = denominator == 0 ? 0 : sign * sqrt(numerator / denominator)
        let cxp = coefficient * rx * y1p / ry
        let cyp = -coefficient * ry * x1p / rx
        let cx = cosPhi * cxp - sinPhi * cyp + (start.x + end.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (start.y + end.y) / 2

        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let dot = ux * vx + uy * vy
            let len = sqrt(ux * ux + uy * uy) * sqrt(vx * vx + vy * vy)
            guard len > 0 else { return 0 }
            let value = min(1, max(-1, dot / len))
            let result = acos(value)
            return (ux * vy - uy * vx) < 0 ? -result : result
        }

        let startAngle = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
        var sweepAngle = angle((x1p - cxp) / rx, (y1p - cyp) / ry,
                               (-x1p - cxp) / rx, (-y1p - cyp) / ry)
        if !sweep && sweepAngle > 0 { sweepAngle -= 2 * .pi }
        if sweep && sweepAngle < 0 { sweepAngle += 2 * .pi }

        // One cubic per quarter turn keeps the error well below a pixel at icon sizes.
        let segments = max(1, Int(ceil(abs(sweepAngle) / (.pi / 2))))
        let delta = sweepAngle / CGFloat(segments)
        let alpha = 4.0 / 3.0 * tan(delta / 4)

        var theta = startAngle
        var from = start
        for _ in 0..<segments {
            let next = theta + delta
            let cosTheta = cos(theta), sinTheta = sin(theta)
            let cosNext = cos(next), sinNext = sin(next)

            func map(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: cosPhi * rx * x - sinPhi * ry * y + cx,
                        y: sinPhi * rx * x + cosPhi * ry * y + cy)
            }
            let to = map(cosNext, sinNext)
            let d1 = map(cosTheta - alpha * sinTheta, sinTheta + alpha * cosTheta)
            let d2 = map(cosNext + alpha * sinNext, sinNext - alpha * cosNext)
            let c1 = CGPoint(x: from.x + (d1.x - map(cosTheta, sinTheta).x),
                             y: from.y + (d1.y - map(cosTheta, sinTheta).y))
            path.addCurve(to: to, control1: c1, control2: d2)
            from = to
            theta = next
        }
    }

    // MARK: - Scanner

    /// A minimal character scanner. `Foundation.Scanner` is avoided because SVG path data
    /// allows separators and signs in places its number parsing does not expect.
    private struct Scanner {
        private let characters: [Character]
        private var index: Int = 0

        init(_ text: String) { characters = Array(text) }

        var isAtEnd: Bool { index >= characters.count }

        mutating func advance() { index += 1 }

        mutating func skipSeparators() {
            while index < characters.count,
                  characters[index] == " " || characters[index] == ","
                    || characters[index] == "\n" || characters[index] == "\r"
                    || characters[index] == "\t" {
                index += 1
            }
        }

        func peekCommand() -> Character? {
            guard index < characters.count else { return nil }
            let c = characters[index]
            return "MmLlHhVvCcSsQqTtAaZz".contains(c) ? c : nil
        }

        mutating func number() -> CGFloat? {
            skipSeparators()
            var text = ""
            if index < characters.count, characters[index] == "-" || characters[index] == "+" {
                text.append(characters[index]); index += 1
            }
            var sawDot = false
            while index < characters.count {
                let c = characters[index]
                if c.isNumber {
                    text.append(c); index += 1
                } else if c == "." && !sawDot {
                    sawDot = true; text.append(c); index += 1
                } else if c == "e" || c == "E" {
                    text.append(c); index += 1
                    if index < characters.count, characters[index] == "-" || characters[index] == "+" {
                        text.append(characters[index]); index += 1
                    }
                } else {
                    break
                }
            }
            return Double(text).map { CGFloat($0) }
        }

        /// Arc flags are single digits and may be written without separators.
        mutating func flag() -> Bool? {
            skipSeparators()
            guard index < characters.count else { return nil }
            let c = characters[index]
            guard c == "0" || c == "1" else { return nil }
            index += 1
            return c == "1"
        }
    }
}
