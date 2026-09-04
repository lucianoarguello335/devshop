import SwiftUI

/// The design's colour tokens, transcribed from the prototype's `THEMES` object.
///
/// The mockup specifies literal values rather than system semantic colours, and both
/// appearances are spelled out, so they are reproduced here exactly instead of being
/// approximated with `Color.secondary` and friends.
struct DevTheme: Equatable, Sendable {
    enum Appearance: String, Sendable, CaseIterable {
        case light, dark
    }

    var appearance: Appearance

    var background: Color
    var chrome: Color
    var sidebar: Color
    var card: Color
    var cardHover: Color
    var text: Color
    var muted: Color
    var faint: Color
    var hairline: Color
    var fill: Color
    var fillStrong: Color
    var track: Color
    var cardShadow: Color
    var cardShadowRadius: CGFloat
    /// Alpha applied to a tier colour when it becomes a finding row's background.
    var tierWash: Double
    var tagBackground: Color

    static let accent = Color(hex: "0a84ff")
    static let accentPressed = Color(hex: "0072e6")

    static let light = DevTheme(
        appearance: .light,
        background: Color(hex: "f4f4f6"),
        chrome: Color(hex: "f6f6f8"),
        sidebar: Color(hex: "eeeef2"),
        card: .white,
        cardHover: Color(hex: "fbfcff"),
        text: Color(hex: "1c1c1e"),
        muted: Color(hex: "8e8e93"),
        faint: Color(hex: "6c6c70"),
        hairline: Color.black.opacity(0.13),
        fill: Color(hex: "787880").opacity(0.12),
        fillStrong: Color(hex: "787880").opacity(0.22),
        track: Color(hex: "787880").opacity(0.16),
        cardShadow: Color.black.opacity(0.07),
        cardShadowRadius: 1.5,
        tierWash: 0.09,
        tagBackground: .white
    )

    static let dark = DevTheme(
        appearance: .dark,
        background: Color(hex: "1c1c1e"),
        chrome: Color(hex: "28282a"),
        sidebar: Color(hex: "1e1e20"),
        card: Color(hex: "2c2c2e"),
        cardHover: Color(hex: "343437"),
        text: Color(hex: "f2f2f7"),
        muted: Color(hex: "98989d"),
        faint: Color(hex: "aeaeb2"),
        hairline: Color.white.opacity(0.12),
        fill: Color(hex: "787880").opacity(0.24),
        fillStrong: Color(hex: "787880").opacity(0.36),
        track: Color(hex: "787880").opacity(0.30),
        cardShadow: Color.black.opacity(0.5),
        cardShadowRadius: 2,
        tierWash: 0.16,
        tagBackground: Color.white.opacity(0.08)
    )

    static func of(_ appearance: Appearance) -> DevTheme {
        appearance == .dark ? .dark : .light
    }

    var colorScheme: ColorScheme { appearance == .dark ? .dark : .light }
}

extension EnvironmentValues {
    /// Injected once at the window root so no view has to thread the palette through.
    @Entry var theme: DevTheme = .light
}

extension Color {
    /// Six-digit hex, with or without a leading `#`. Falls back to grey on bad input so a
    /// typo in the catalog cannot crash a tile.
    init(hex: String) {
        var value = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        if value.count == 3 {
            value = value.map { "\($0)\($0)" }.joined()
        }
        guard value.count == 6, let rgb = UInt32(value, radix: 16) else {
            self = Color(.sRGB, red: 0.56, green: 0.56, blue: 0.58, opacity: 1)
            return
        }
        self = Color(
            .sRGB,
            red: Double((rgb >> 16) & 0xff) / 255,
            green: Double((rgb >> 8) & 0xff) / 255,
            blue: Double(rgb & 0xff) / 255,
            opacity: 1
        )
    }
}

// MARK: - Shared card treatment

extension View {
    /// The rounded surface used by every panel in the design.
    func devCard(_ theme: DevTheme, radius: CGFloat = 10) -> some View {
        background(theme.card, in: .rect(cornerRadius: radius))
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(theme.hairline.opacity(0.5), lineWidth: 0.5)
            }
            .shadow(color: theme.cardShadow, radius: theme.cardShadowRadius, y: 1)
    }
}
