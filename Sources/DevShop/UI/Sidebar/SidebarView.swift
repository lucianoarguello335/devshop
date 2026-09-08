import SwiftUI

struct SidebarView: View {
    @Bindable var model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HealthRing(score: model.healthScore,
                       status: model.healthStatus,
                       label: model.healthLabel,
                       summary: model.findings.tally,
                       isScanning: model.isScanning)
                .padding(.horizontal, 6)
                .padding(.bottom, 16)

            HStack(spacing: 8) {
                Text("PANELS")
                    .font(.system(size: 10.5, weight: .semibold))
                    .kerning(0.5)
                    .foregroundStyle(theme.muted)
                Button {
                    model.toggleAllPanels()
                } label: {
                    MiniSwitch(isOn: model.allPanelsVisible)
                }
                .buttonStyle(.plain)
                .help(model.allPanelsVisible ? "Hide all panels" : "Show all panels")
                .accessibilityLabel("All panels")
                .accessibilityValue(model.allPanelsVisible ? "shown" : "hidden")
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 6)

            ScrollView {
                VStack(spacing: 1) {
                    ForEach(ToolCategory.allCases) { category in
                        PanelToggleRow(
                            symbol: category.symbol,
                            title: category.title,
                            count: model.count(of: category),
                            isOn: model.isVisible(category),
                            accent: DevTheme.accent,
                            select: { model.reveal(category) },
                            toggle: { model.toggle(category) }
                        )
                        // Terminal Config sits with the shell rather than after everything
                        // else: it describes the same part of the machine, and Not Installed
                        // is the natural end of the list.
                        if category == .shell {
                            PanelToggleRow(
                                symbol: "list.bullet.indent",
                                title: "Terminal Config",
                                count: model.shellConfig.entries.count,
                                isOn: model.configPanelVisible,
                                accent: Color(hex: "64d2ff"),
                                select: { model.revealConfig() },
                                toggle: { model.configPanelVisible.toggle() }
                            )
                        }
                    }
                    PanelToggleRow(
                        symbol: "exclamationmark.triangle.fill",
                        title: "Findings",
                        count: model.findings.count,
                        isOn: model.findingsPanelVisible,
                        accent: Color(hex: "ff9f0a"),
                        select: { model.revealFindings() },
                        toggle: { model.findingsPanelVisible.toggle() }
                    )
                }
                .padding(.horizontal, 4)
            }
            .scrollIndicators(.never)
            .withoutScrollEdgeEffect()
            .frame(maxHeight: .infinity)

            if !model.largestCategories.isEmpty {
                LargestOnDiskCard(rows: model.largestCategories,
                                  isExpanded: $model.largestOnDiskExpanded)
                    .padding(.top, 12)
            }

            ThisMacCard(info: model.systemInfo, developmentBytes: model.developmentBytes)
                .padding(.top, 10)
        }
        .padding(.horizontal, 12)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(theme.sidebar)
        .animation(.spring(duration: 0.38, bounce: 0.1), value: model.largestOnDiskExpanded)
    }
}
