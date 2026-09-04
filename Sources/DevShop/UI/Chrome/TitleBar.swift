import SwiftUI

/// The 52pt window header: title block, appearance switch, search field, Refresh.
/// The traffic lights are the real ones, so the leading inset leaves room for them.
struct TitleBar: View {
    @Bindable var model: AppModel
    /// The design's title bar height; the header replaces AppKit's own strip.
    static let height: CGFloat = 52
    @Environment(\.theme) private var theme
    /// Re-renders the "N min ago" label without polling the model.
    @State private var clock = Date.now

    private let tick = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 14) {
            WindowControls()
            VStack(alignment: .leading, spacing: 1) {
                Text("DevShop")
                    .font(.system(size: 13, weight: .semibold))
                    .kerning(-0.13)
                Text(model.lastFetchLabel(now: clock))
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme.muted)
                    .contentTransition(.numericText())
            }
            .allowsHitTesting(false)
            Spacer(minLength: 0)
            LayoutSwitch(model: model)
            AppearanceSwitch(model: model)
            CopySetupButton(model: model)
            SearchField(text: $model.query)
            RefreshButton(model: model)
        }
        .padding(.horizontal, 16)
        .frame(height: Self.height)
        .background {
            theme.chrome
                .contentShape(.rect)
                .onTapGesture(count: 2) { TitleBarDoubleClick.perform() }
        }
        .onReceive(tick) { clock = $0 }
    }
}

// MARK: - Layout

/// Grid or list for the centre column. Same pill as the appearance switch, so the two read
/// as a pair of view controls.
private struct LayoutSwitch: View {
    @Bindable var model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ContentLayout.allCases, id: \.self) { layout in
                Button {
                    model.layout = layout
                } label: {
                    SFIcon(symbol: layout.symbol, size: 11, weight: .semibold)
                        .foregroundStyle(model.layout == layout ? theme.text : theme.muted)
                        .frame(width: 26, height: 24)
                        .background {
                            if model.layout == layout {
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(theme.card)
                                    .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
                            }
                        }
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help(layout.label)
                .accessibilityLabel(layout.label)
            }
        }
        .padding(2)
        .frame(height: 28)
        .background(theme.fill, in: .rect(cornerRadius: 9))
        .animation(.easeInOut(duration: 0.2), value: model.layout)
    }
}

// MARK: - Appearance

private struct AppearanceSwitch: View {
    @Bindable var model: AppModel
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var systemScheme

    private var current: DevTheme.Appearance {
        model.themeOverride ?? (systemScheme == .dark ? .dark : .light)
    }

    var body: some View {
        // One button over the whole pill, so a click anywhere flips the appearance.
        Button {
            model.themeOverride = current == .dark ? .light : .dark
        } label: {
            HStack(spacing: 2) {
                icon("sun.max.fill", isOn: current == .light)
                icon("moon.fill", isOn: current == .dark)
            }
            .padding(2)
            .frame(height: 28)
            .background(theme.fill, in: .rect(cornerRadius: 9))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(current == .dark ? "Switch to light appearance" : "Switch to dark appearance")
        .accessibilityLabel("Appearance")
        .accessibilityValue(current == .dark ? "Dark" : "Light")
    }

    /// `geometryGroup()` is load-bearing, not decoration. SwiftUI coalesces position
    /// changes from ancestors and lets leaf views resolve their own frame, which landed
    /// these glyphs about 9pt left of the box they belong to. The group forces the frame to
    /// be resolved by the parent first, so the symbol paints where it was laid out.
    private func icon(_ symbol: String, isOn: Bool) -> some View {
        SFIcon(symbol: symbol, size: 11, weight: .semibold)
            .foregroundStyle(isOn ? theme.text : theme.muted)
            .frame(width: 26, height: 24)
            .background {
                if isOn {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(theme.card)
                        .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isOn)
    }
}

// MARK: - Copy setup

/// Exports the whole scan as JSON. Styled like its neighbours in the header rather than as a
/// prominent action, because it is an occasional export, not something to reach for often.
private struct CopySetupButton: View {
    @Bindable var model: AppModel
    @Environment(\.theme) private var theme
    @State private var isHovering = false

    var body: some View {
        Button {
            model.copySetup()
        } label: {
            HStack(spacing: 6) {
                SFIcon(symbol: "doc.on.doc", size: 11, weight: .medium)
                Text("Copy setup")
                    .font(.system(size: 12.5, weight: .medium))
            }
            .foregroundStyle(theme.text)
            .padding(.horizontal, 11)
            .frame(height: 28)
            .background(isHovering ? theme.fillStrong : theme.fill, in: .rect(cornerRadius: 9))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .disabled(model.tools.isEmpty)
        .help("Copies the full setup including all dev elements and findings")
        .accessibilityLabel("Copy setup")
        .accessibilityHint("Copies every detected tool, its contents and the findings as JSON")
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}

// MARK: - Search

private struct SearchField: View {
    @Binding var text: String
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 7) {
            SFIcon(symbol: "magnifyingglass", size: 11, weight: .medium)
                .foregroundStyle(theme.muted)
            TextField("Search tools, paths, versions", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    SFIcon(symbol: "xmark.circle.fill", size: 11)
                        .foregroundStyle(theme.muted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 11)
        .frame(width: 250, height: 28)
        .background(theme.fill, in: .rect(cornerRadius: 8))
    }
}

// MARK: - Refresh

private struct RefreshButton: View {
    @Bindable var model: AppModel
    @State private var spin = false

    var body: some View {
        Button {
            model.refresh()
        } label: {
            HStack(spacing: 7) {
                SFIcon(symbol: "arrow.clockwise", size: 11, weight: .semibold)
                    .rotationEffect(.degrees(spin ? 360 : 0))
                Text(model.refreshLabel)
                    .font(.system(size: 12.5, weight: .medium))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 13)
            .frame(height: 28)
            .background(DevTheme.accent, in: .rect(cornerRadius: 8))
            .shadow(color: DevTheme.accent.opacity(0.4), radius: 1, y: 1)
        }
        .buttonStyle(.plain)
        .disabled(model.isBusy)
        .help("Re-scan the environment and re-measure sizes")
        .onChange(of: model.isBusy) { _, busy in
            if busy {
                withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                    spin = true
                }
            } else {
                // A repeatForever animation is not cancelled by changing the value with
                // animations disabled — it keeps repeating and the arrow never stops.
                // Overriding it with a zero-duration animation both ends the repeat and
                // avoids the anticlockwise unwind that animating back to zero produces.
                withAnimation(.linear(duration: 0)) { spin = false }
            }
        }
    }
}
