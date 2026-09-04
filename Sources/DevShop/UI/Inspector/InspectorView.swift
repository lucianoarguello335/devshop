import AppKit
import SwiftUI

/// The right column: everything known about the selected tool, plus the read-only actions.
struct InspectorView: View {
    @Bindable var model: AppModel
    @Environment(\.theme) private var theme
    @State private var didCopy = false
    @State private var copyResetTask: Task<Void, Never>?

    private var tool: DetectedTool? { model.selectedTool }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("INSPECTOR")
                .font(.system(size: 10.5, weight: .semibold))
                .kerning(0.5)
                .foregroundStyle(theme.muted)

            if let tool {
                header(tool)
                statusPill(tool)
                details(tool)
                actions(tool)
                if tool.children.isEmpty {
                    shareOfCategory(tool)
                    Spacer(minLength: 0)
                    findings(tool)
                } else {
                    // A container's contents are far more useful here than a share bar, so
                    // they take the space instead and stretch to fill the column.
                    contents(tool)
                }
            } else {
                Spacer()
                Text("Scanning…")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.muted)
                    .frame(maxWidth: .infinity)
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(theme.sidebar)
        .onChange(of: model.selectedToolID) { _, _ in
            copyResetTask?.cancel()
            didCopy = false
        }
    }

    // MARK: - Sections

    private func header(_ tool: DetectedTool) -> some View {
        HStack(spacing: 12) {
            IconChip(tool: tool, size: 52, theme: theme)
            VStack(alignment: .leading, spacing: 1) {
                Text(tool.name)
                    .font(.system(size: 17, weight: .bold))
                    .kerning(-0.34)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(tool.subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.muted)
                    .lineLimit(2)
            }
        }
    }

    private func statusPill(_ tool: DetectedTool) -> some View {
        Text(tool.status.label)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(tool.status == .missing ? theme.muted : Color(hex: tool.status.hex))
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(pillBackground(tool.status), in: .rect(cornerRadius: 8))
    }

    private func pillBackground(_ status: ToolStatus) -> Color {
        switch status {
        case .ok: Color(hex: "30d158").opacity(0.16)
        case .warn: Color(hex: "ff9f0a").opacity(0.18)
        case .missing: theme.fill
        }
    }

    private func details(_ tool: DetectedTool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            detailRow("Location") {
                Text(tool.path.map(Probes.abbreviate) ?? "—")
                    .font(.system(size: 10.5, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            detailRow("Size") {
                Text(sizeText(tool))
                    .font(.system(size: 11.5))
                    .monospacedDigit()
            }
            detailRow("Managed") {
                Text(tool.managedBy).font(.system(size: 11.5))
            }
            detailRow("Category") {
                Text(tool.definition.category.inspectorLabel).font(.system(size: 11.5))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .devCard(theme)
    }

    private func detailRow(_ label: String,
                           @ViewBuilder value: () -> some View) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(theme.muted)
                .frame(width: 62, alignment: .leading)
            value()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func sizeText(_ tool: DetectedTool) -> String {
        let bytes = model.bytes(for: tool)
        if bytes > 0 { return ByteFormat.full(bytes) }
        if tool.status == .missing { return "—" }
        if tool.measurableRoot == nil { return "shared location" }
        return model.hasSizes ? "under 1 MB" : "not measured"
    }

    private func actions(_ tool: DetectedTool) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    guard let path = tool.path else { return }
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                } label: {
                    Text("Open in Finder")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .background(DevTheme.accent, in: .rect(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(tool.path == nil)
                .opacity(tool.path == nil ? 0.45 : 1)

                Button {
                    copy(tool)
                } label: {
                    Text(didCopy ? "Copied" : "Copy path")
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 13)
                        .frame(height: 30)
                        .devCard(theme, radius: 8)
                }
                .buttonStyle(.plain)
                .disabled(tool.path == nil)
                .opacity(tool.path == nil ? 0.45 : 1)
            }

            Button {
                guard let site = tool.definition.website, let url = URL(string: site) else { return }
                NSWorkspace.shared.open(url)
            } label: {
                HStack(spacing: 6) {
                    Text("Open official website")
                    SFIcon(symbol: "arrow.up.forward", size: 12).foregroundStyle(theme.muted)
                }
                .font(.system(size: 12, weight: .medium))
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .devCard(theme, radius: 8)
            }
            .buttonStyle(.plain)
            .disabled(tool.definition.website == nil)
            .opacity(tool.definition.website == nil ? 0.45 : 1)
        }
    }

    private func copy(_ tool: DetectedTool) {
        guard let path = tool.path else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
        withAnimation(.easeOut(duration: 0.15)) { didCopy = true }
        copyResetTask?.cancel()
        copyResetTask = Task {
            try? await Task.sleep(for: .milliseconds(1300))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.15)) { didCopy = false }
        }
    }

    private func shareOfCategory(_ tool: DetectedTool) -> some View {
        let bytes = model.bytes(for: tool)
        let categoryTotal = model.tools
            .filter { $0.category == tool.category }
            .reduce(Int64(0)) { $0 + model.bytes(for: $1) }
        let fraction = categoryTotal > 0 ? Double(bytes) / Double(categoryTotal) : 0

        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text("Share of disk")
                    .font(.system(size: 11.5, weight: .semibold))
                Spacer()
                Text(bytes > 0 ? "\(Int((fraction * 100).rounded()))%" : "—")
                    .font(.system(size: 10.5))
                    .monospacedDigit()
                    .foregroundStyle(theme.muted)
            }
            MeterBar(fraction: fraction,
                     color: tool.status == .missing
                     ? theme.muted : Color(hex: tool.definition.color))
                .frame(height: 7)
            Text(shareNote(tool, bytes: bytes, categoryTotal: categoryTotal))
                .font(.system(size: 10.5))
                .foregroundStyle(theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .devCard(theme)
    }

    private func shareNote(_ tool: DetectedTool, bytes: Int64, categoryTotal: Int64) -> String {
        guard bytes > 0 else {
            return model.hasSizes ? "No measurable footprint" : "Press Refresh to measure sizes"
        }
        return "\(ByteFormat.compact(bytes)) of \(ByteFormat.compact(categoryTotal)) "
             + "in \(tool.definition.category.inspectorLabel.lowercased())"
    }

    /// What lives inside a container tile — the formulae in the Cellar, the casks in the
    /// Caskroom, the globally installed npm packages — heaviest first.
    private func contents(_ tool: DetectedTool) -> some View {
        let children = model.children(of: tool)
        let maximum = model.largestChildBytes(of: tool)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Contents")
                    .font(.system(size: 11.5, weight: .semibold))
                Text("\(children.count) items")
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme.muted)
                Spacer(minLength: 0)
                if model.hasSizes {
                    Text(ByteFormat.compact(children.reduce(0) { $0 + model.bytes(for: $1) }))
                        .font(.system(size: 10.5))
                        .monospacedDigit()
                        .foregroundStyle(theme.muted)
                }
            }
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(children) { child in
                        ChildRow(child: child,
                                 bytes: model.bytes(for: child),
                                 maximumBytes: maximum)
                    }
                }
                .padding(.trailing, 2)
            }
            .scrollIndicators(.never)
            .withoutScrollEdgeEffect()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .devCard(theme)
    }

    @ViewBuilder
    private func findings(_ tool: DetectedTool) -> some View {
        let matches = model.findings(for: tool)
        if matches.isEmpty {
            Text("No findings for \(tool.name) — nothing needs attention.")
                .font(.system(size: 11))
                .foregroundStyle(theme.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(12)
                .background(theme.fill, in: .rect(cornerRadius: 10))
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Findings")
                        .font(.system(size: 11.5, weight: .semibold))
                    Text("\(matches.tally) · this item")
                        .font(.system(size: 10.5))
                        .foregroundStyle(theme.muted)
                }
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(matches) { finding in
                            FindingRow(finding: finding, compact: true)
                        }
                    }
                }
                .scrollIndicators(.never)
                .withoutScrollEdgeEffect()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, minHeight: 110, alignment: .leading)
            .devCard(theme)
        }
    }
}


/// One package inside a container, with its real icon where one exists.
private struct ChildRow: View {
    let child: ToolChild
    let bytes: Int64
    let maximumBytes: Int64

    @Environment(\.theme) private var theme
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            ChildIcon(child: child, size: 20)
            VStack(alignment: .leading, spacing: 0) {
                Text(child.name)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(child.version)
                    .font(.system(size: 10))
                    .foregroundStyle(theme.muted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if bytes > 0 {
                MeterBar(fraction: maximumBytes > 0
                         ? max(0.05, Double(bytes) / Double(maximumBytes)) : 0,
                         color: Color(hex: child.color))
                    .frame(width: 30, height: 4)
                Text(ByteFormat.compact(bytes))
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(theme.muted)
                    .frame(width: 34, alignment: .trailing)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(isHovering ? theme.fill : .clear, in: .rect(cornerRadius: 6))
        .contentShape(.rect)
        .onHover { isHovering = $0 }
        .help(Probes.abbreviate(child.path))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(child.name) \(child.version)")
    }
}
