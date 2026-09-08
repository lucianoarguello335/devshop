import SwiftUI

/// The scrolling centre column: one section per visible category, then Findings.
struct ContentColumn: View {
    @Bindable var model: AppModel
    @Environment(\.theme) private var theme

    private let columns = [GridItem(.flexible(), spacing: 10),
                           GridItem(.flexible(), spacing: 10),
                           GridItem(.flexible(), spacing: 10)]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    ForEach(model.visiblePanels) { panel in
                        section(for: panel)
                            .id(panel.category.rawValue)
                    }

                    if model.showConfigSection {
                        ConfigSection(model: model)
                            .id(AppModel.configSectionID)
                    }

                    if model.showFindingsSection {
                        FindingsSection(findings: model.filteredFindings,
                                        summary: model.findings.tally,
                                        copyPrompt: model.copyFindingsPrompt)
                            .id(AppModel.findingsSectionID)
                    }

                    if model.noResults {
                        Text("No tools match \u{201C}\(model.query)\u{201D}.")
                            .font(.system(size: 13))
                            .foregroundStyle(theme.muted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 60)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 26)
            }
            .scrollIndicators(.never)
            .withoutScrollEdgeEffect()
            .onChange(of: model.scrollTarget) { _, target in
                guard let target else { return }
                // A hidden panel is revealed in the same click, so its anchor needs one
                // run-loop turn to exist before it can be scrolled to.
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        proxy.scrollTo(target, anchor: .top)
                    }
                    model.clearScrollTarget()
                }
            }
        }
        .background(theme.background)
        .animation(.easeInOut(duration: 0.25), value: model.hiddenCategories)
        // Deliberately not animated on `query`: an implicit animation here animates an
        // insert-and-remove diff across every section on every keystroke, and typing is the
        // one place in this window where the result has to keep up with the user.
        .animation(.easeInOut(duration: 0.2), value: model.layout)
    }

    private func section(for panel: Panel) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text(panel.title)
                    .font(.system(size: 15, weight: .semibold))
                    .kerning(-0.22)
                Text(panel.meta(showSizes: model.hasSizes))
                    .font(.system(size: 11))
                    .foregroundStyle(theme.muted)
                    .contentTransition(.numericText())
                Spacer(minLength: 0)
                if panel.bytes > 0 {
                    MeterBar(fraction: Double(panel.bytes) / Double(max(1, model.largestPanelBytes)),
                             color: DevTheme.accent)
                        .frame(width: 110, height: 5)
                }
            }
            switch model.layout {
            case .grid:
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(panel.tools) { tile in
                        ToolTile(tile: tile,
                                 maximumBytes: model.largestToolBytes,
                                 isSelected: model.selectedToolID == tile.id,
                                 theme: theme) {
                            model.select(id: tile.id)
                        }
                        .equatable()
                    }
                }
            case .list:
                ToolListView(panel: panel,
                             sort: model.sort,
                             selectedToolID: model.selectedToolID,
                             maximumBytes: model.largestToolBytes,
                             theme: theme,
                             onSort: { model.sortBy($0) },
                             onSelect: { model.select(id: $0) })
            }
        }
    }
}
