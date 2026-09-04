import SwiftUI

/// The whole window: title bar, then sidebar / content / inspector.
struct RootWindow: View {
    @Bindable var model: AppModel
    @Environment(\.colorScheme) private var systemScheme

    private var theme: DevTheme {
        DevTheme.of(model.themeOverride ?? (systemScheme == .dark ? .dark : .light))
    }

    var body: some View {
        VStack(spacing: 0) {
            TitleBar(model: model)
            Divider().overlay(theme.hairline)
            // No rules between the columns: the sidebar and inspector already read as
            // separate surfaces through their own background colour.
            HStack(spacing: 0) {
                SidebarView(model: model)
                    .frame(width: 236)
                ContentColumn(model: model)
                    .frame(maxWidth: .infinity)
                InspectorView(model: model)
                    .frame(width: 300)
            }
        }
        .withoutScrollEdgeEffect()
        .withoutWindowBarBackground()
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                ToastView(message: toast)
                    .padding(.bottom, 28)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3, bounce: 0.2), value: model.toast)
        .ignoresSafeArea(.container, edges: .top)   // the header *is* the title bar
        .frame(minWidth: 1080, idealWidth: 1180, minHeight: 700, idealHeight: 790)
        .background { WindowChrome().frame(width: 0, height: 0) }
        .background(theme.background)
        .environment(\.theme, theme)
        .preferredColorScheme(theme.colorScheme)
        .tint(DevTheme.accent)
        .foregroundStyle(theme.text)
        .animation(.easeInOut(duration: 0.22), value: model.themeOverride)
    }
}
