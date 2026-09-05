import Foundation

/// Runs every catalog probe off the main actor and returns the tiles the window shows.
///
/// The scan is deliberately cheap: it stats known paths and lists a handful of
/// directories. Measuring how much space anything occupies is a separate, opt-in pass
/// (`SizeMeasurer`) that only runs when the user presses Refresh.
actor EnvironmentScanner {
    struct Result: Sendable {
        var tools: [DetectedTool]
        var homebrew: HomebrewSummary
        var applications: [InstalledApplication]
    }

    struct HomebrewSummary: Sendable, Equatable {
        var isInstalled: Bool
        var formulaCount: Int
        var caskCount: Int
        /// Packages with more than one version directory left in place.
        var staleFormulae: [String]
        static let none = HomebrewSummary(isInstalled: false, formulaCount: 0,
                                          caskCount: 0, staleFormulae: [])
    }

    func scan(catalog: [ToolDefinition]) -> Result {
        let brew = HomebrewReader()
        var tools: [DetectedTool] = []
        for definition in catalog {
            tools.append(contentsOf: detect(definition, brew: brew))
        }
        let stale = brew.formulae.keys.filter { brew.versions(ofFormula: $0).count > 1 }.sorted()
        let summary = HomebrewSummary(
            isInstalled: brew.isInstalled,
            formulaCount: brew.formulaCount,
            caskCount: brew.caskCount,
            staleFormulae: stale
        )
        return Result(tools: decorate(tools, brew: brew, summary: summary),
                      homebrew: summary,
                      applications: ApplicationsReader.scan())
    }

    // MARK: - Per-definition probing

    private func detect(_ definition: ToolDefinition, brew: HomebrewReader) -> [DetectedTool] {
        for rule in definition.rules {
            if case .versionManager(let kind) = rule {
                let versions = VersionReaders.versions(for: kind)
                if !versions.isEmpty {
                    return versions.map { managed in
                        DetectedTool(
                            id: "\(definition.id)@\(managed.version)",
                            definition: definition,
                            status: .ok,
                            subtitle: "\(managed.version) · \(kind.managerName)",
                            path: managed.path,
                            managedBy: kind.managerName,
                            measurableRoot: managed.path
                        )
                    }
                }
                continue
            }
            if let hit = apply(rule, definition: definition, brew: brew) {
                return [hit]
            }
        }
        return [missing(definition)]
    }

    private func apply(_ rule: DetectionRule,
                       definition: ToolDefinition,
                       brew: HomebrewReader) -> DetectedTool? {
        switch rule {
        case .executable(let names):
            guard let path = Probes.findExecutable(names) else { return nil }
            // A resolved Homebrew shim lands inside the Cellar, which carries the version.
            let version = brew.formulae.values.first { path.hasPrefix($0.path) }?.version
            let root = measurableRoot(for: path)
            return DetectedTool(
                id: definition.id,
                definition: definition,
                status: .ok,
                subtitle: version ?? sourceLabel(for: path),
                path: path,
                managedBy: managerLabel(for: path),
                measurableRoot: root.path,
                measuresBinaryOnly: root.isBinaryOnly
            )

        case .brewFormula(let name):
            guard let installed = brew.formulae[name] else { return nil }
            return DetectedTool(
                id: definition.id,
                definition: definition,
                status: .ok,
                subtitle: "\(installed.version) · Homebrew",
                path: installed.path,
                managedBy: "Homebrew formula",
                measurableRoot: installed.path
            )

        case .brewCask(let name):
            guard let installed = brew.casks[name] else { return nil }
            return DetectedTool(
                id: definition.id,
                definition: definition,
                status: .ok,
                subtitle: "\(installed.version) · Homebrew cask",
                path: installed.path,
                managedBy: "Homebrew cask",
                measurableRoot: installed.path
            )

        case .appBundle(let paths):
            guard let bundle = paths.first(where: { Probes.exists($0) }) else { return nil }
            let full = Probes.expand(bundle)
            let version = Probes.appVersion(at: full)
            let build = Probes.appBuild(at: full)
            var subtitle = version ?? "app bundle"
            if let build, let version, build != version { subtitle = "\(version) (\(build))" }
            return DetectedTool(
                id: definition.id,
                definition: definition,
                status: .ok,
                subtitle: subtitle,
                path: full,
                managedBy: brew.casks.values.contains { full.hasPrefix($0.path) }
                    ? "Homebrew cask" : "Application",
                measurableRoot: full
            )

        case .directory(let path, let version):
            guard Probes.exists(path) else { return nil }
            let full = Probes.expand(path)
            return DetectedTool(
                id: definition.id,
                definition: definition,
                status: .ok,
                subtitle: version ?? sourceLabel(for: full),
                path: full,
                managedBy: managerLabel(for: full),
                measurableRoot: Probes.isDirectory(full) ? full : measurableRoot(for: full).path,
                measuresBinaryOnly: !Probes.isDirectory(full) && measurableRoot(for: full).isBinaryOnly
            )

        case .versionManager:
            return nil
        }
    }

    private func missing(_ definition: ToolDefinition) -> DetectedTool {
        DetectedTool(
            id: definition.id,
            definition: definition,
            status: .missing,
            subtitle: definition.missingNote ?? "not installed",
            path: nil,
            managedBy: "—",
            measurableRoot: nil
        )
    }

    // MARK: - Labels

    /// Stubs in /usr/bin that hand off to whatever `xcode-select` points at.
    private static let developerShims: Set<String> = [
        "swift", "swiftc", "clang", "clang++", "cc", "c++", "git", "lldb", "xcrun", "xcodebuild"
    ]

    /// What a path says about how the tool got there.
    private func managerLabel(for path: String) -> String {
        switch true {
        case path.hasPrefix("/opt/homebrew"), path.hasPrefix("/usr/local/Cellar"): "Homebrew"
        case path.hasPrefix("/Library/Developer/CommandLineTools"): "Command Line Tools"
        case path.hasPrefix("/Applications/Xcode.app"): "Xcode"
        case path.contains("/.nvm/"): "nvm"
        case path.contains("/.pyenv/"): "pyenv"
        case path.contains("/.rbenv/"): "rbenv"
        case path.contains("/.cargo/"): "cargo"
        case path.hasPrefix("/usr/bin"), path.hasPrefix("/bin"),
             path.hasPrefix("/usr/sbin"), path.hasPrefix("/sbin"): "macOS"
        case path.hasPrefix("/Applications"): "Application"
        default: "Manual install"
        }
    }

    /// Short label used as the subtitle when no version could be read. Never a full path —
    /// that belongs in the inspector's Location row, not on a 30pt-tall tile.
    private func sourceLabel(for path: String) -> String {
        switch managerLabel(for: path) {
        case "macOS":
            // A handful of /usr/bin entries are xcrun shims into the developer toolchain;
            // the rest really are shipped with macOS.
            Self.developerShims.contains((path as NSString).lastPathComponent)
                ? "Apple toolchain" : "system"
        case "Command Line Tools": VersionReaders.commandLineToolsVersion().map { "\($0) · CLT" } ?? "Command Line Tools"
        case "Homebrew": "installed · Homebrew"
        case "Manual install": "installed"
        default: "installed · \(managerLabel(for: path))"
        }
    }

    /// The directory the size pass should measure, or `nil` for things with no footprint
    /// of their own. A bare executable in a shared bin directory is not measurable —
    /// walking `/usr/bin` would attribute the whole directory to one tool.
    private func measurableRoot(for path: String) -> (path: String?, isBinaryOnly: Bool) {
        let shared = ["/usr/bin", "/bin", "/usr/sbin", "/sbin",
                      "/opt/homebrew/bin", "/usr/local/bin",
                      "/Library/Developer/CommandLineTools/usr/bin"]
        let parent = (path as NSString).deletingLastPathComponent
        // Measure the executable itself rather than nothing. Walking the whole shared bin
        // directory would attribute every neighbour to this one tool, but the binary's own
        // allocated size is a real number and beats a blank cell.
        if shared.contains(parent) { return (path, true) }
        return (Probes.isDirectory(path) ? path : parent, false)
    }

    // MARK: - Post-pass

    /// Fills in the few tiles whose subtitle is a count rather than a version.
    private func decorate(_ tools: [DetectedTool],
                          brew: HomebrewReader,
                          summary: HomebrewSummary) -> [DetectedTool] {
        tools.map { tool in
            var tool = tool
            switch tool.definition.id {
            case "pkg.homebrew" where tool.status == .ok:
                tool.subtitle = "\(summary.formulaCount) formulae · \(summary.caskCount) casks"
                tool.managedBy = "self"
            case "brew.formulae" where tool.status == .ok:
                tool.subtitle = "\(summary.formulaCount) installed"
            case "brew.casks" where tool.status == .ok:
                tool.subtitle = "\(summary.caskCount) installed"
            case "brew.taps" where tool.status == .ok:
                tool.subtitle = "\(tapCount(brew: brew)) taps"
            case "brew.cache" where tool.status == .ok:
                tool.subtitle = "download cache"
            case "sdk.clt" where tool.status == .ok:
                tool.subtitle = VersionReaders.commandLineToolsVersion() ?? "installed"
            case "ide.vscodeext" where tool.status == .ok:
                let count = Probes.subdirectories(of: "~/.vscode/extensions").count
                tool.subtitle = "\(count) extensions"
            case "pkg.nvm" where tool.status == .ok:
                tool.subtitle = versionCount(at: "~/.nvm/versions/node", noun: "version")
            case "pkg.pyenv" where tool.status == .ok:
                tool.subtitle = versionCount(at: "~/.pyenv/versions", noun: "version")
            case "pkg.rbenv" where tool.status == .ok:
                tool.subtitle = versionCount(at: "~/.rbenv/versions", noun: "version")
            default:
                break
            }
            if tool.status != .missing {
                tool.children = ChildReaders.children(for: tool, brew: brew)
            }
            return tool
        }
    }

    private func tapCount(brew: HomebrewReader) -> Int {
        Probes.subdirectories(of: brew.prefix + "/Library/Taps")
            .reduce(0) { $0 + Probes.subdirectories(of: brew.prefix + "/Library/Taps/" + $1).count }
    }

    private func versionCount(at path: String, noun: String) -> String {
        let n = Probes.subdirectories(of: path).count
        return "\(n) \(noun)\(n == 1 ? "" : "s") installed"
    }
}
