import SwiftUI

/// A measured size on one line.
///
/// The compact labels carry two letters (`466MB`, `14.8GB`), which no longer fit the 34pt
/// columns the one-letter form used: the unit wrapped onto a line of its own. Every size in
/// the app is drawn through this view so the width and the label can never drift apart again.
struct SizeLabel: View {
    let bytes: Int64
    var fontSize: CGFloat = 10
    /// Trailing-aligned column width. `nil` sizes to the text.
    var width: CGFloat? = SizeLabel.columnWidth
    /// Shown when nothing was measured.
    var placeholder: String = "\u{2014}"

    /// Fits `999MB` and `14.8GB` at 10\u{2013}11pt, the sizes the columns use.
    nonisolated static let columnWidth: CGFloat = 52

    @Environment(\.theme) private var theme

    var body: some View {
        Text(bytes > 0 ? ByteFormat.compact(bytes) : placeholder)
            .font(.system(size: fontSize))
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(theme.muted)
            .frame(width: width, alignment: .trailing)
    }
}
