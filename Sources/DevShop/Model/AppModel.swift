import AppKit
import Foundation
import Observation

/// One row of the "Largest on disk" card.
struct CategoryTotal: Identifiable, Equatable {
    var category: ToolCategory
    var bytes: Int64
    var id: ToolCategory { category }
}

/// A category section as the centre column renders it.
struct Panel: Identifiable, Equatable {
    var id: ToolCategory { category }
    var category: ToolCategory
    var tools: [DetectedTool]
    /// Total measured bytes across the section; `0` before anything is measured.
    var bytes: Int64

    var title: String { category.title }

    func meta(showSizes: Bool) -> String {
        let count = "\(tools.count)"
        guard category != .notInstalled else { return "\(count) missing" }
        guard showSizes, bytes > 0 else { return "\(count) tools" }
        return "\(count) · \(ByteFormat.full(bytes))"
    }
}

@MainActor
@Observable
final class AppModel {
    // MARK: - Scan output

    private(set) var tools: [DetectedTool] = []
    private(set) var findings: [Finding] = []
    private(set) var systemInfo: SystemInfo = .unknown
    private(set) var homebrew: EnvironmentScanner.HomebrewSummary = .none
    /// Everything in /Applications, for the setup export.
    private(set) var applications: [InstalledApplication] = []

    /// Measured bytes per tool id. Restored from the cache at launch so the window is
    /// fully populated before any walking happens.
    private(set) var sizes: [String: Int64] = [:]
    private(set) var lastMeasuredAt: Date = .distantPast

    // MARK: - UI state

    var query: String = "" { didSet { if query != oldValue { rebuildDerived() } } }
    var selectedToolID: String?
    var hiddenCategories: Set<ToolCategory> = [] {
        didSet { if hiddenCategories != oldValue { rebuildDerived() } }
    }
    var findingsPanelVisible: Bool = true {
        didSet { if findingsPanelVisible != oldValue { rebuildDerived() } }
    }
    var largestOnDiskExpanded: Bool = true
    /// `nil` follows the system appearance; the title-bar control sets an override.
    var themeOverride: DevTheme.Appearance?
    /// Grid or list. Remembered between launches, because it is a lasting preference
    /// rather than something to re-pick every time the app opens.
    var layout: ContentLayout = .grid {
        didSet {
            guard layout != oldValue else { return }
            UserDefaults.standard.set(layout.rawValue, forKey: Self.layoutKey)
        }
    }
    /// Section the centre column should scroll to. Set by the sidebar, consumed and
    /// cleared by the centre column, so the same row can be clicked repeatedly.
    var scrollTarget: String?

    /// Which column the centre column is ordered by. Alphabetical by default.
    var sort = ToolSort() { didSet { if sort != oldValue { rebuildDerived() } } }

    private static let layoutKey = "contentLayout"
    /// Transient confirmation shown after a copy. `nil` when nothing is showing.
    private(set) var toast: String?
    private var toastTask: Task<Void, Never>?
    private(set) var isScanning = false
    private(set) var isMeasuring = false

    // MARK: - Collaborators

    private let scanner = EnvironmentScanner()
    private let measurer = SizeMeasurer()
    private var measureTask: Task<Void, Never>?
    /// A brief hold so the "Scanning" state is legible even when the probes finish instantly.
    private static let minimumScanDisplay = Duration.milliseconds(450)

    // MARK: - Lifecycle

    /// Loads the cache, runs the cheap probes, and measures sizes only if nothing is cached.
    func start() async {
        if let stored = UserDefaults.standard.string(forKey: Self.layoutKey),
           let restored = ContentLayout(rawValue: stored) {
            layout = restored
        }
        // Lets a screenshot or a UI test drive the window without synthesising clicks.
        if let preset = ProcessInfo.processInfo.environment["DEVSHOP_QUERY"] {
            query = preset
        }
        // Lets a screenshot or a UI test pin the appearance without clicking the switch.
        if let forced = ProcessInfo.processInfo.environment["DEVSHOP_APPEARANCE"],
           let appearance = DevTheme.Appearance(rawValue: forced) {
            themeOverride = appearance
        }
        let cache = SizeCache.load()
        sizes = cache.bytesByToolID
        lastMeasuredAt = cache.measuredAt
        await runScan()
        if cache.isEmpty {
            measureSizes()
        }
    }

    /// The Refresh button: re-probe, then re-measure every size.
    func refresh() {
        guard !isScanning && !isMeasuring else { return }
        Task {
            await runScan()
            measureSizes()
        }
    }

    private func runScan() async {
        isScanning = true
        defer { isScanning = false }
        async let hold: Void = Task.sleep(for: Self.minimumScanDisplay)
        let info = SystemInfoReader.read()
        let result = await scanner.scan(catalog: Catalog.all)
        try? await hold

        tools = result.tools
        homebrew = result.homebrew
        applications = result.applications
        systemInfo = info
        findings = FindingsEngine.evaluate(tools: result.tools, homebrew: result.homebrew)
        rebuildDerived()
        if selectedToolID == nil || !tools.contains(where: { $0.id == selectedToolID }) {
            selectedToolID = defaultSelection()?.id
        }
    }

    private func measureSizes() {
        measureTask?.cancel()
        let snapshot = tools
        isMeasuring = true
        measureTask = Task { [measurer] in
            var collected: [String: Int64] = [:]
            var pending: [String: Int64] = [:]
            var lastFlush = ContinuousClock.now

            for await measurement in await measurer.measure(snapshot) {
                collected[measurement.toolID] = measurement.bytes
                pending[measurement.toolID] = measurement.bytes
                // Publishing every single measurement meant one full rebuild per directory
                // walked. Bars still fill in progressively, just a few times a second.
                if ContinuousClock.now - lastFlush > .milliseconds(250) {
                    sizes.merge(pending) { _, new in new }
                    pending.removeAll(keepingCapacity: true)
                    lastFlush = .now
                    rebuildDerived()
                }
            }
            if !pending.isEmpty {
                sizes.merge(pending) { _, new in new }
                rebuildDerived()
            }
            guard !Task.isCancelled else {
                isMeasuring = false
                return
            }
            lastMeasuredAt = .now
            isMeasuring = false
            SizeCache(measuredAt: lastMeasuredAt, bytesByToolID: collected).save()
        }
    }

    /// Prefer something interesting over the alphabetically first tile.
    private func defaultSelection() -> DetectedTool? {
        // Lets a screenshot or a UI test open on a specific tile.
        if let wanted = ProcessInfo.processInfo.environment["DEVSHOP_SELECT"],
           let match = tools.first(where: { $0.definition.id == wanted }) {
            return match
        }
        if let flagged = findings.first?.toolIDs.first,
           let tool = tools.first(where: { $0.id == flagged }) {
            return tool
        }
        return tools.first { $0.status != .missing }
    }

    // MARK: - Derived state

    var isBusy: Bool { isScanning || isMeasuring }

    /// What the Refresh button says. Measuring is by far the longer phase, and calling it
    /// "Scanning" for a minute and a half made a working app look stuck.
    var refreshLabel: String {
        if isScanning { return "Scanning" }
        if isMeasuring { return "Measuring" }
        return "Refresh"
    }

    /// True once at least one size is known, which is what un-hides the size UI.
    var hasSizes: Bool { !sizes.isEmpty }

    func bytes(for tool: DetectedTool) -> Int64 { sizes[tool.id] ?? 0 }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func matches(_ tool: DetectedTool) -> Bool {
        let q = trimmedQuery
        guard !q.isEmpty else { return true }
        let haystack = [tool.name, tool.subtitle, tool.path ?? "", tool.managedBy]
        return haystack.contains { $0.localizedStandardContains(q) }
    }

    /// Every category with at least one tool, filtered by the search field and the sidebar
    /// toggles.
    ///
    /// Stored rather than computed. As a computed property it ran on every access, and the
    /// centre column reads it once per section plus once for the bar scale — eight full
    /// filter-and-sort passes over every tool for a single redraw, which is what made
    /// scrolling and live resize stutter.
    private(set) var visiblePanels: [Panel] = []

    /// Largest single measurement, so tile bars share one scale. Previously recomputed
    /// inside the tile loop, making it O(tiles x measurements) for every redraw.
    private(set) var largestToolBytes: Int64 = 0

    /// Total measured development footprint, for the disk bar.
    private(set) var developmentBytes: Int64 = 0

    /// The four heaviest categories, for the "Largest on disk" card.
    private(set) var largestCategories: [CategoryTotal] = []

    private(set) var filteredFindings: [Finding] = []

    /// Tile counts per category, including hidden ones, for the sidebar toggles.
    private(set) var categoryCounts: [ToolCategory: Int] = [:]

    /// Most severe finding tier per tool, for the badge beside its name. Precomputed
    /// because every tile would otherwise scan the findings on each redraw.
    private(set) var findingTierByToolID: [String: FindingTier] = [:]

    /// Largest measured panel, for the section bars. Reads the cached panels rather than
    /// rebuilding them.
    var largestPanelBytes: Int64 { visiblePanels.map(\.bytes).max() ?? 1 }

    /// Recomputes everything the views read. Called when the scan finishes, when a batch of
    /// sizes lands, and when a filter, sort or toggle changes — not on every redraw.
    private func rebuildDerived() {
        visiblePanels = ToolCategory.allCases.compactMap { category in
            guard !hiddenCategories.contains(category) else { return nil }
            let members = tools.filter { $0.category == category && matches($0) }
            guard !members.isEmpty else { return nil }
            let sorted = members.sorted { sort.compare($0, $1, bytes: bytes(for:)) }
            return Panel(category: category,
                         tools: sorted,
                         bytes: sorted.reduce(0) { $0 + bytes(for: $1) })
        }

        largestToolBytes = tools.reduce(Int64(0)) { Swift.max($0, bytes(for: $1)) }
        developmentBytes = sizes.values.reduce(0, +)

        var totals: [CategoryTotal] = []
        for category in ToolCategory.allCases where category != .notInstalled {
            var sum: Int64 = 0
            for tool in tools where tool.category == category {
                sum += bytes(for: tool)
            }
            if sum > 0 { totals.append(CategoryTotal(category: category, bytes: sum)) }
        }
        totals.sort { $0.bytes > $1.bytes }
        largestCategories = Array(totals.prefix(4))

        let q = trimmedQuery
        filteredFindings = q.isEmpty ? findings : findings.filter {
            $0.title.localizedStandardContains(q)
                || $0.detail.localizedStandardContains(q)
                || $0.scope.localizedStandardContains(q)
        }

        categoryCounts = Dictionary(grouping: tools, by: \.category).mapValues(\.count)

        var tiers: [String: FindingTier] = [:]
        for finding in findings {
            for id in finding.toolIDs {
                // FindingTier sorts most severe first, so the minimum wins.
                tiers[id] = tiers[id].map { Swift.min($0, finding.tier) } ?? finding.tier
            }
        }
        findingTierByToolID = tiers
    }

    func findingTier(for tool: DetectedTool) -> FindingTier? {
        findingTierByToolID[tool.id]
    }

    /// Counts shown next to each sidebar toggle, including hidden categories.
    func count(of category: ToolCategory) -> Int { categoryCounts[category] ?? 0 }

    func bytes(for child: ToolChild) -> Int64 { sizes[child.id] ?? 0 }

    /// A container's contents, heaviest first — the order that answers "what is taking up
    /// all this space" without any further clicking.
    func children(of tool: DetectedTool) -> [ToolChild] {
        tool.children.sorted {
            let a = bytes(for: $0), b = bytes(for: $1)
            return a == b ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : a > b
        }
    }

    /// Largest single child, so the contents bars share one scale.
    func largestChildBytes(of tool: DetectedTool) -> Int64 {
        tool.children.map { bytes(for: $0) }.max() ?? 0
    }

    func findings(for tool: DetectedTool) -> [Finding] {
        findings.filter { $0.toolIDs.contains(tool.id) }
    }

    var selectedTool: DetectedTool? {
        guard let selectedToolID else { return tools.first }
        return tools.first { $0.id == selectedToolID } ?? tools.first
    }

    var showFindingsSection: Bool { findingsPanelVisible && !filteredFindings.isEmpty }

    var noResults: Bool {
        !trimmedQuery.isEmpty && visiblePanels.isEmpty && filteredFindings.isEmpty
    }

    var healthScore: Int { findings.healthScore }

    var healthStatus: HealthStatus { HealthStatus(score: healthScore) }

    var healthLabel: String { healthStatus.label }

    /// "Last fetch 2 min ago", driven by the size cache timestamp.
    func lastFetchLabel(now: Date = .now) -> String {
        if isScanning { return "Scanning…" }
        if isMeasuring { return "Measuring sizes…" }
        guard lastMeasuredAt != .distantPast else { return "Not measured yet" }
        let minutes = Int(now.timeIntervalSince(lastMeasuredAt) / 60)
        switch minutes {
        case ..<1: return "Last fetch just now"
        case 1: return "Last fetch 1 min ago"
        case 2..<60: return "Last fetch \(minutes) min ago"
        default:
            return "Last fetch \(lastMeasuredAt.formatted(date: .abbreviated, time: .shortened))"
        }
    }

    // MARK: - Intents

    /// True only when every panel, findings included, is showing.
    var allPanelsVisible: Bool {
        hiddenCategories.isEmpty && findingsPanelVisible
    }

    /// One switch for the lot: hide everything when all of it is showing, otherwise bring
    /// it all back. Starting from a partly hidden state, showing everything is what someone
    /// reaching for a master switch almost always wants.
    func toggleAllPanels() {
        if allPanelsVisible {
            hiddenCategories = Set(ToolCategory.allCases)
            findingsPanelVisible = false
        } else {
            hiddenCategories = []
            findingsPanelVisible = true
        }
    }

    func toggle(_ category: ToolCategory) {
        if hiddenCategories.contains(category) {
            hiddenCategories.remove(category)
        } else {
            hiddenCategories.insert(category)
        }
    }

    func isVisible(_ category: ToolCategory) -> Bool { !hiddenCategories.contains(category) }

    func sortBy(_ field: SortField) { sort.toggle(field) }

    /// Jumps the centre column to a section. A hidden panel is shown first — clicking its
    /// row and having nothing happen would be worse than revealing it.
    func reveal(_ category: ToolCategory) {
        if hiddenCategories.contains(category) { hiddenCategories.remove(category) }
        scrollTarget = category.rawValue
    }

    func revealFindings() {
        if !findingsPanelVisible { findingsPanelVisible = true }
        scrollTarget = Self.findingsSectionID
    }

    func clearScrollTarget() { scrollTarget = nil }

    static let findingsSectionID = "findings"

    /// Puts a briefing for an AI agent on the clipboard, built from the findings actually
    /// on screen so it matches what the user is looking at.
    func copyFindingsPrompt() {
        let prompt = FindingsPrompt.build(findings: filteredFindings,
                                          tools: tools,
                                          homebrew: homebrew,
                                          system: systemInfo,
                                          sizes: sizes)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)
        show(toast: "Copied to clipboard")
    }

    /// Puts the whole scan on the clipboard as JSON — every tile, its contents, the
    /// findings and the machine it came from.
    func copySetup() {
        let json = SetupExport.json(.init(tools: tools,
                                          findings: findings,
                                          homebrew: homebrew,
                                          system: systemInfo,
                                          sizes: sizes,
                                          measuredAt: lastMeasuredAt,
                                          applications: applications))
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(json, forType: .string)
        show(toast: "Setup copied to clipboard")
    }

    private func show(toast message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            toast = nil
        }
    }

    func select(_ tool: DetectedTool) {
        guard selectedToolID != tool.id else { return }
        selectedToolID = tool.id
    }
}
