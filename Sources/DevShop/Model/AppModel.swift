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
    /// Ready-to-draw rows. See `TileData` for why the tools are flattened here.
    var tools: [TileData]
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
    /// What the login shell loads before the first prompt.
    private(set) var shellConfig: ShellConfigSnapshot = .empty

    /// Measured bytes per tool id. Restored from the cache at launch so the window is
    /// fully populated before any walking happens.
    private(set) var sizes: [String: Int64] = [:]
    private(set) var lastMeasuredAt: Date = .distantPast

    // MARK: - UI state

    var query: String = "" { didSet { if query != oldValue { rebuildDerived() } } }

    /// What the inspector is describing. Three kinds of thing can be selected, so this is an
    /// enum rather than a bare id — a tool id and a config entry id are both strings and
    /// nothing else would tell them apart.
    enum Selection: Equatable, Sendable {
        case tool(String)
        case configEntry(String)
        case terminal(String)
    }

    var selection: Selection?

    /// The selected tool's id, or `nil` when something else is selected. Kept as a property
    /// so the tile grid and the list view still deal in ids and know nothing about the enum.
    var selectedToolID: String? {
        get { if case .tool(let id) = selection { id } else { nil } }
        set { selection = newValue.map(Selection.tool) }
    }

    /// Secrets the user has explicitly revealed, by entry id. Deliberately not persisted:
    /// revealing one is a decision for that moment, not a preference.
    var revealedSecrets: Set<String> = []
    var hiddenCategories: Set<ToolCategory> = [] {
        didSet { if hiddenCategories != oldValue { rebuildDerived() } }
    }
    var findingsPanelVisible: Bool = true {
        didSet { if findingsPanelVisible != oldValue { rebuildDerived() } }
    }
    var configPanelVisible: Bool = true {
        didSet { if configPanelVisible != oldValue { rebuildDerived() } }
    }
    var largestOnDiskExpanded: Bool = true
    /// Terminal Config groups that are collapsed. Every kind starts in here: the section is
    /// a reference list rather than something to read top to bottom, and seventy rows open by
    /// default would push the Findings section off the bottom of the column.
    var collapsedConfigKinds: Set<ConfigEntryKind> = Set(ConfigEntryKind.allCases)
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
        shellConfig = result.shellConfig
        systemInfo = info
        findings = FindingsEngine.evaluate(tools: result.tools,
                                           homebrew: result.homebrew,
                                           config: result.shellConfig)
        rebuildDerived()
        if !isSelectionStillValid { selection = defaultSelection() }
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

    /// A rescan can retire whatever was selected — a tool that is gone, a config entry that
    /// was edited out of a dotfile.
    private var isSelectionStillValid: Bool {
        switch selection {
        case .tool(let id): tools.contains { $0.id == id }
        case .configEntry(let id): shellConfig.entry(id: id) != nil
        case .terminal(let id): shellConfig.terminals.contains { $0.id == id }
        case nil: false
        }
    }

    /// Prefer something interesting over the alphabetically first tile.
    private func defaultSelection() -> Selection? {
        // Lets a screenshot or a UI test open on a specific tile.
        if let wanted = ProcessInfo.processInfo.environment["DEVSHOP_SELECT"],
           let match = tools.first(where: { $0.definition.id == wanted }) {
            return .tool(match.id)
        }
        // Findings carry tool ids and config entry ids in the same field, so the most severe
        // one opens whichever kind of thing it points at.
        if let flagged = findings.first?.toolIDs.first {
            if tools.contains(where: { $0.id == flagged }) { return .tool(flagged) }
            if shellConfig.entry(id: flagged) != nil { return .configEntry(flagged) }
        }
        return (tools.first { $0.status != .missing }).map { .tool($0.id) }
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
        SearchFilter.matches(tool, query: trimmedQuery)
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

    /// Config entries grouped by kind, filtered by the search field. Built here rather than
    /// in the view for the same reason `visiblePanels` is.
    private(set) var configGroups: [ConfigGroup] = []

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
        var tiers: [String: FindingTier] = [:]
        for finding in findings {
            for id in finding.toolIDs {
                // FindingTier sorts most severe first, so the minimum wins.
                tiers[id] = tiers[id].map { Swift.min($0, finding.tier) } ?? finding.tier
            }
        }
        findingTierByToolID = tiers

        visiblePanels = ToolCategory.allCases.compactMap { category in
            guard !hiddenCategories.contains(category) else { return nil }
            let members = tools.filter { $0.category == category && matches($0) }
            guard !members.isEmpty else { return nil }
            let sorted = members.sorted { sort.compare($0, $1, bytes: bytes(for:)) }
            return Panel(category: category,
                         tools: sorted.map {
                             TileData(tool: $0, bytes: bytes(for: $0), findingTier: tiers[$0.id])
                         },
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

        configGroups = ConfigEntryKind.allCases.compactMap { kind in
            let members = shellConfig.entries.filter { $0.kind == kind && matches($0) }
            return members.isEmpty ? nil : ConfigGroup(kind: kind, entries: members)
        }
    }

    /// Search matches the name, the value and the files a directive comes from. The raw value
    /// is deliberately not searched: a masked secret should not be findable by typing it.
    private func matches(_ entry: ConfigEntry) -> Bool {
        let q = trimmedQuery
        guard !q.isEmpty else { return true }
        if entry.name.localizedStandardContains(q) { return true }
        if entry.displayValue.localizedStandardContains(q) { return true }
        return entry.origins.contains { $0.file.localizedStandardContains(q) }
    }

    func findingTier(for tool: DetectedTool) -> FindingTier? {
        findingTierByToolID[tool.id]
    }

    /// Counts shown next to each sidebar toggle, including hidden categories.
    func count(of category: ToolCategory) -> Int { categoryCounts[category] ?? 0 }

    func bytes(for child: ToolChild) -> Int64 { sizes[child.id] ?? 0 }

    /// A container's contents, heaviest first — the order that answers "what is taking up
    /// all this space" without any further clicking.
    ///
    /// A search narrows the list to the matching entries. The tile only survives the filter
    /// because one of its children matched, so showing all 153 formulae again would hide the
    /// one the user typed.
    func children(of tool: DetectedTool) -> [ToolChild] {
        tool.children.filter { SearchFilter.matches($0, query: trimmedQuery) }.sorted {
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

    /// Config findings carry entry ids in the same `toolIDs` field. Entry ids are namespaced
    /// by kind (`env.JAVA_HOME`), so they cannot collide with a tool id.
    func findings(for entry: ConfigEntry) -> [Finding] {
        findings.filter { $0.toolIDs.contains(entry.id) }
    }

    /// A terminal has no id in any finding, so its findings are the ones scoped to its own
    /// config files.
    func findings(for terminal: TerminalApp) -> [Finding] {
        guard !terminal.configPaths.isEmpty else { return [] }
        return findings.filter { finding in
            terminal.configPaths.contains { finding.scope.hasSuffix($0) }
        }
    }

    var selectedConfigEntry: ConfigEntry? {
        guard case .configEntry(let id) = selection else { return nil }
        return shellConfig.entry(id: id)
    }

    var selectedTerminal: TerminalApp? {
        guard case .terminal(let id) = selection else { return nil }
        return shellConfig.terminals.first { $0.id == id }
    }

    /// Most severe finding for a config entry, for the badge on its row.
    func findingTier(for entry: ConfigEntry) -> FindingTier? {
        findingTierByToolID[entry.id]
    }

    var selectedTool: DetectedTool? {
        guard case .tool(let id) = selection else { return nil }
        return tools.first { $0.id == id } ?? tools.first
    }

    var showFindingsSection: Bool { findingsPanelVisible && !filteredFindings.isEmpty }

    var showConfigSection: Bool { configPanelVisible && !configGroups.isEmpty }

    /// Whether the Shell & Core Tooling panel is on screen, which is where the Terminal
    /// Config section is drawn. When that panel is toggled off or filtered away by the
    /// search, the section falls to the end of the panels rather than disappearing with it.
    var configFollowsShellPanel: Bool {
        visiblePanels.contains { $0.category == .shell }
    }

    /// Whether a Terminal Config group is showing its rows.
    ///
    /// A search overrides the collapse state entirely. Matching a row and then hiding it
    /// inside a closed group would make the search look broken, and the collapse state is
    /// remembered underneath so clearing the field puts everything back.
    func isExpanded(_ kind: ConfigEntryKind) -> Bool {
        !trimmedQuery.isEmpty || !collapsedConfigKinds.contains(kind)
    }

    func toggleConfigGroup(_ kind: ConfigEntryKind) {
        if collapsedConfigKinds.contains(kind) {
            collapsedConfigKinds.remove(kind)
        } else {
            collapsedConfigKinds.insert(kind)
        }
    }

    /// The meta line beside the Terminal Config title. Narrows to what the search is
    /// actually showing, so the count never contradicts the rows under it.
    var configMeta: String {
        let shown = configGroups.reduce(0) { $0 + $1.entries.count }
        guard shown != shellConfig.entries.count else { return shellConfig.meta }
        return "\(shown) of \(shellConfig.entries.count) entries"
    }

    var noResults: Bool {
        !trimmedQuery.isEmpty && visiblePanels.isEmpty
            && filteredFindings.isEmpty && configGroups.isEmpty
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
        hiddenCategories.isEmpty && findingsPanelVisible && configPanelVisible
    }

    /// One switch for the lot: hide everything when all of it is showing, otherwise bring
    /// it all back. Starting from a partly hidden state, showing everything is what someone
    /// reaching for a master switch almost always wants.
    func toggleAllPanels() {
        if allPanelsVisible {
            hiddenCategories = Set(ToolCategory.allCases)
            findingsPanelVisible = false
            configPanelVisible = false
        } else {
            hiddenCategories = []
            findingsPanelVisible = true
            configPanelVisible = true
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

    func revealConfig() {
        if !configPanelVisible { configPanelVisible = true }
        scrollTarget = Self.configSectionID
    }

    func clearScrollTarget() { scrollTarget = nil }

    static let findingsSectionID = "findings"
    static let configSectionID = "terminalconfig"

    /// Puts a briefing for an AI agent on the clipboard, built from the findings actually
    /// on screen so it matches what the user is looking at.
    func copyFindingsPrompt() {
        let prompt = FindingsPrompt.build(findings: filteredFindings,
                                          tools: tools,
                                          homebrew: homebrew,
                                          system: systemInfo,
                                          sizes: sizes,
                                          config: shellConfig)
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
                                          applications: applications,
                                          shellConfig: shellConfig))
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

    func select(_ tool: DetectedTool) { select(id: tool.id) }

    func select(id: String) { select(.tool(id)) }

    func select(_ entry: ConfigEntry) { select(.configEntry(entry.id)) }

    func select(_ terminal: TerminalApp) { select(.terminal(terminal.id)) }

    func select(_ new: Selection) {
        guard selection != new else { return }
        // Selecting a row inside a collapsed group has to open it. This happens when a row
        // matched by a search is clicked and the search is then cleared — without it the
        // selection would vanish while the inspector still described it.
        if case .configEntry(let id) = new, let kind = shellConfig.entry(id: id)?.kind {
            collapsedConfigKinds.remove(kind)
        }
        selection = new
    }

    /// Reveals one secret's value for the rest of the session. There is no matching hide:
    /// once it has been on screen, pretending otherwise buys nothing.
    func revealSecret(_ entry: ConfigEntry) { revealedSecrets.insert(entry.id) }

    func isRevealed(_ entry: ConfigEntry) -> Bool { revealedSecrets.contains(entry.id) }

    /// What the inspector shows for a value: the real thing only once asked for.
    func value(of entry: ConfigEntry) -> String {
        entry.isSecret && !isRevealed(entry) ? entry.displayValue : entry.rawValue
    }
}
