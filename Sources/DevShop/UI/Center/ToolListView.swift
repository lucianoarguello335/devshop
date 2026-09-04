import SwiftUI

/// The centre column's table layout: one row per tool, with sortable column headers.
///
/// Built from stacks rather than `Table` so a row can carry the icon chip, status dot and
/// size bar the design calls for, and so selection behaves exactly as it does in the grid.
struct ToolListView: View {
    let panel: Panel
    @Bindable var model: AppModel
    @Environment(\.theme) private var theme

    /// Measured once for the table and handed down, so rows lay out without readers of
    /// their own.
    @State private var width: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            ListHeader(sort: model.sort, width: width) { model.sortBy($0) }
            ForEach(Array(panel.tools.enumerated()), id: \.element.id) { index, tool in
                ToolListRow(tool: tool,
                            width: width,
                            bytes: model.bytes(for: tool),
                            maximumBytes: model.largestToolBytes,
                            isSelected: model.selectedToolID == tool.id,
                            isAlternate: !index.isMultiple(of: 2),
                            findingTier: model.findingTier(for: tool)) {
                    model.select(tool)
                }
            }
        }
        // The table must claim the column's full width before it is measured. Sized to its
        // own content it would start at zero and never grow, because the column widths are
        // derived from the measurement.
        .frame(maxWidth: .infinity)
        .devCard(theme)
        .clipShape(.rect(cornerRadius: 10))
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { width = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, new in width = new }
            }
        }
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

    /// Width available to the flexible columns once the fixed ones are taken out.
    static func flexibleWidth(in total: CGFloat) -> CGFloat {
        max(0, total - leading - size)
    }
}

private struct ListHeader: View {
    let sort: ToolSort
    let width: CGFloat
    let onSort: (SortField) -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        let flexible = ListMetrics.flexibleWidth(in: width - ListMetrics.inset * 2)
        return HStack(spacing: 0) {
                Color.clear.frame(width: ListMetrics.leading)
                ForEach(ListMetrics.flexible, id: \.field) { column in
                    label(column.field)
                        .frame(width: flexible * column.share, alignment: .leading)
                }
            label(.size)
                .frame(width: ListMetrics.size, alignment: .trailing)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 34)
        .padding(.horizontal, ListMetrics.inset)
        .background(theme.fill.opacity(0.4))
    }

    private func label(_ field: SortField) -> some View {
        Button {
            onSort(field)
        } label: {
            HStack(spacing: 4) {
                Text(field.title.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .kerning(0.4)
                if sort.field == field {
                    SFIcon(symbol: sort.ascending ? "chevron.up" : "chevron.down",
                           size: 7, weight: .bold)
                }
            }
            .foregroundStyle(sort.field == field ? theme.text : theme.muted)
            .frame(maxWidth: .infinity,
                   alignment: field == .size ? .trailing : .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help("Sort by \(field.title.lowercased())")
    }
}

/// One tool as a table row.
private struct ToolListRow: View {
    let tool: DetectedTool
    let width: CGFloat
    let bytes: Int64
    let maximumBytes: Int64
    let isSelected: Bool
    let isAlternate: Bool
    /// Most severe finding touching this tool, if any.
    let findingTier: FindingTier?
    let select: () -> Void

    @Environment(\.theme) private var theme
    @State private var isHovering = false

    private var isMissing: Bool { tool.status == .missing }

    var body: some View {
        let flexible = ListMetrics.flexibleWidth(in: width - ListMetrics.inset * 2)
        return Button(action: select) {
            HStack(spacing: 0) {
                    HStack(spacing: 8) {
                        IconChip(tool: tool, size: 24, theme: theme)
                        Circle()
                            .fill(Color(hex: tool.status.hex))
                            .frame(width: 6, height: 6)
                    }
                    .frame(width: ListMetrics.leading, alignment: .leading)

                    HStack(spacing: 4) {
                        text(tool.name, size: 12.5, weight: .semibold, color: theme.text)
                        if let findingTier {
                            FindingBadge(tier: findingTier, size: 9.5)
                        }
                    }
                    .frame(width: flexible * ListMetrics.flexible[0].share, alignment: .leading)
                    text(tool.subtitle, size: 12, weight: .regular, color: theme.faint)
                        .frame(width: flexible * ListMetrics.flexible[1].share, alignment: .leading)
                    Text(tool.path.map(Probes.abbreviate) ?? "—")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(theme.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(width: flexible * ListMetrics.flexible[2].share, alignment: .leading)
                    text(tool.managedBy, size: 12, weight: .regular, color: theme.faint)
                        .frame(width: flexible * ListMetrics.flexible[3].share, alignment: .leading)

                    HStack(spacing: 8) {
                        MeterBar(fraction: maximumBytes > 0 && bytes > 0
                                 ? max(0.04, Double(bytes) / Double(maximumBytes)) : 0,
                                 color: isMissing ? theme.muted : Color(hex: tool.definition.color))
                            .frame(width: 52, height: 4)
                        Text(bytes > 0 ? ByteFormat.compact(bytes) : "—")
                            .font(.system(size: 11))
                            .monospacedDigit()
                            .foregroundStyle(theme.muted)
                            .frame(width: 40, alignment: .trailing)
                    }
                .frame(width: ListMetrics.size, alignment: .trailing)
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
        var parts = [tool.name, tool.subtitle, tool.status.label]
        if let findingTier { parts.append("has \(findingTier.label.lowercased())") }
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
