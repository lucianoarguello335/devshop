import SwiftUI

/// The centre column's table layout: one row per tool, with sortable column headers.
///
/// Built from stacks rather than `Table` so a row can carry the icon chip, status dot and
/// size bar the design calls for, and so selection behaves exactly as it does in the grid.
struct ToolListView: View {
    let panel: Panel
    let sort: ToolSort
    let selectedToolID: String?
    let maximumBytes: Int64
    let theme: DevTheme
    let onSort: (SortField) -> Void
    let onSelect: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ListHeader(sort: sort, theme: theme, onSort: onSort)
            ForEach(Array(panel.tools.enumerated()), id: \.element.id) { index, tile in
                ToolListRow(tile: tile,
                            maximumBytes: maximumBytes,
                            isSelected: selectedToolID == tile.id,
                            isAlternate: !index.isMultiple(of: 2),
                            theme: theme) {
                    onSelect(tile.id)
                }
                .equatable()
            }
        }
        .frame(maxWidth: .infinity)
        .devCard(theme)
        .clipShape(.rect(cornerRadius: 10))
    }
}

/// Column geometry, shared by the header and every row so they cannot drift apart.
private enum ListMetrics {
    /// Icon chip and status dot.
    static let leading: CGFloat = 58
    /// Size bar plus its label.
    static let size: CGFloat = 104
    static let inset: CGFloat = 14

    /// Flexible columns, as fractions of whatever is left over.
    static let flexible: [(field: SortField, share: CGFloat)] = [
        (.name, 0.22), (.version, 0.20), (.location, 0.36), (.managedBy, 0.22)
    ]

    static let shares = flexible.map(\.share)

    static var layout: TableRowLayout {
        TableRowLayout(leading: leading, trailing: size, shares: shares)
    }
}

/// Lays a table row out in one pass: a fixed column at each end, and the space between split
/// by share.
///
/// This used to be arithmetic over a width the table measured with a `GeometryReader` and fed
/// back to itself through `@State`. That meant one state write per section per frame of a live
/// resize, each one re-running the header and every row in the table.
private struct TableRowLayout: Layout {
    let leading: CGFloat
    let trailing: CGFloat
    let shares: [CGFloat]

    func sizeThatFits(proposal: ProposedViewSize,
                      subviews: Subviews,
                      cache: inout ()) -> CGSize {
        let height = subviews.reduce(CGFloat(0)) {
            max($0, $1.sizeThatFits(.unspecified).height)
        }
        return CGSize(width: proposal.width ?? (leading + trailing),
                      height: proposal.height ?? height)
    }

    func placeSubviews(in bounds: CGRect,
                       proposal: ProposedViewSize,
                       subviews: Subviews,
                       cache: inout ()) {
        var x = bounds.minX
        for (index, width) in widths(in: bounds.width).enumerated() {
            guard index < subviews.count else { break }
            subviews[index].place(at: CGPoint(x: x, y: bounds.midY),
                                  anchor: .leading,
                                  proposal: ProposedViewSize(width: width,
                                                             height: bounds.height))
            x += width
        }
    }

    private func widths(in total: CGFloat) -> [CGFloat] {
        let flexible = max(0, total - leading - trailing)
        return [leading] + shares.map { flexible * $0 } + [trailing]
    }
}

private struct ListHeader: View {
    let sort: ToolSort
    let theme: DevTheme
    let onSort: (SortField) -> Void

    var body: some View {
        ListMetrics.layout {
            Color.clear
            ForEach(ListMetrics.flexible, id: \.field) { column in
                ColumnHeader(field: column.field, sort: sort, theme: theme) {
                    onSort(column.field)
                }
            }
            ColumnHeader(field: .size, sort: sort, theme: theme) { onSort(.size) }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 34)
        .padding(.horizontal, ListMetrics.inset)
        .background(theme.fill.opacity(0.4))
    }
}

/// One clickable column heading.
///
/// At rest a heading is just a label, which is how it reads — the whole row looked inert,
/// and only the already-sorted column showed any sign that a click did anything. Hovering
/// now lights the cell and ghosts in the chevron the click would leave behind, so the
/// affordance and the outcome are both visible before committing to it.
private struct ColumnHeader: View {
    let field: SortField
    let sort: ToolSort
    let theme: DevTheme
    let action: () -> Void

    @State private var isHovering = false

    private var isActive: Bool { sort.field == field }

    /// The direction a click would produce, mirroring `ToolSort.toggle`: the active column
    /// flips, any other starts ascending — except size, which starts biggest-first.
    private var chevronPointsUp: Bool {
        isActive ? sort.ascending : field != .size
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(field.title.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .kerning(0.4)
                // Always laid out, so ghosting it in on hover cannot shift the title.
                SFIcon(symbol: chevronPointsUp ? "chevron.up" : "chevron.down",
                       size: 7, weight: .bold)
                    .opacity(isActive ? 1 : (isHovering ? 0.45 : 0))
            }
            .foregroundStyle(isActive || isHovering ? theme.text : theme.muted)
            .frame(maxWidth: .infinity,
                   alignment: field == .size ? .trailing : .leading)
            .padding(.vertical, 5)
            .background {
                // Negative inset widens the highlight past the text without moving it, so
                // the heading stays aligned with the column beneath it.
                RoundedRectangle(cornerRadius: 5)
                    .fill(isHovering ? theme.fill : .clear)
                    .padding(.horizontal, -6)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .pointerStyle(.link)
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .help(helpText)
    }

    private var helpText: String {
        let direction = chevronPointsUp ? "ascending" : "descending"
        return "Sort by \(field.title.lowercased()), \(direction)"
    }
}

/// One tool as a table row. `Equatable` for the same reason `ToolTile` is.
private struct ToolListRow: View, Equatable {
    let tile: TileData
    let maximumBytes: Int64
    let isSelected: Bool
    let isAlternate: Bool
    let theme: DevTheme
    let select: () -> Void

    @State private var isHovering = false

    nonisolated static func == (a: ToolListRow, b: ToolListRow) -> Bool {
        a.tile == b.tile
            && a.maximumBytes == b.maximumBytes
            && a.isSelected == b.isSelected
            && a.isAlternate == b.isAlternate
            && a.theme == b.theme
    }

    private var isMissing: Bool { tile.isMissing }

    var body: some View {
        Button(action: select) {
            ListMetrics.layout {
                HStack(spacing: 8) {
                    IconChip(tile: tile, size: 24, theme: theme)
                    Circle()
                        .fill(Color(hex: tile.status.hex))
                        .frame(width: 6, height: 6)
                    Spacer(minLength: 0)
                }

                HStack(spacing: 4) {
                    text(tile.name, size: 12.5, weight: .semibold, color: theme.text)
                    if let findingTier = tile.findingTier {
                        FindingBadge(tier: findingTier, size: 9.5)
                    }
                    Spacer(minLength: 0)
                }
                text(tile.version ?? "—", size: 12, weight: .regular,
                     color: tile.version == nil ? theme.muted : theme.faint)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(tile.displayPath ?? "—")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(theme.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                text(tile.managedBy, size: 12, weight: .regular, color: theme.faint)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    MeterBar(fraction: maximumBytes > 0 && tile.bytes > 0
                             ? max(0.04, Double(tile.bytes) / Double(maximumBytes)) : 0,
                             color: isMissing ? theme.muted : Color(hex: tile.colorHex))
                        .frame(width: 52, height: 4)
                    Text(tile.bytes > 0 ? ByteFormat.compact(tile.bytes) : "—")
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(theme.muted)
                        .frame(width: 40, alignment: .trailing)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .padding(.horizontal, ListMetrics.inset)
            .background(rowBackground)
            .overlay(alignment: .leading) {
                // A leading bar marks the selection without shifting the row's contents.
                Rectangle()
                    .fill(isSelected ? DevTheme.accent : .clear)
                    .frame(width: 3)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(accessibilityDescription)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private var accessibilityDescription: String {
        var parts = [tile.name, tile.version ?? "version unknown", tile.status.label]
        if let findingTier = tile.findingTier { parts.append("has \(findingTier.label.lowercased())") }
        return parts.joined(separator: ", ")
    }

    private func text(_ value: String,
                      size: CGFloat,
                      weight: Font.Weight,
                      color: Color) -> some View {
        Text(value)
            .font(.system(size: size, weight: weight))
            .foregroundStyle(color)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private var rowBackground: Color {
        if isSelected { return DevTheme.accent.opacity(0.12) }
        if isHovering { return theme.fill.opacity(0.7) }
        return isAlternate ? theme.fill.opacity(0.22) : .clear
    }
}
