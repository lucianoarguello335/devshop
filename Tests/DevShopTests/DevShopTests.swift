import Foundation
import Testing
@testable import DevShop

// MARK: - Catalog

@Suite("Catalog")
struct CatalogTests {
    @Test("every entry decodes and carries at least one rule")
    func decodes() {
        let all = Catalog.all
        #expect(all.count > 100)
        for tool in all {
            #expect(!tool.rules.isEmpty, "\(tool.id) has no detection rule")
            #expect(!tool.symbol.isEmpty, "\(tool.id) has no SF Symbol fallback")
            #expect(tool.color.count == 6, "\(tool.id) has a malformed colour")
        }
    }

    @Test("ids are unique")
    func uniqueIDs() {
        let ids = Catalog.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("every category is represented")
    func categoriesCovered() {
        let used = Set(Catalog.all.map(\.category))
        for category in ToolCategory.allCases where category != .notInstalled {
            #expect(used.contains(category), "no catalog entry for \(category.rawValue)")
        }
    }
}

// MARK: - Probes

@Suite("Probes")
struct ProbeTests {
    @Test("tilde expansion")
    func expansion() {
        #expect(Probes.expand("~/x") == Probes.home + "/x")
        #expect(Probes.expand("/opt/homebrew") == "/opt/homebrew")
    }

    @Test("abbreviation is the inverse of expansion")
    func abbreviation() {
        #expect(Probes.abbreviate(Probes.home + "/.nvm") == "~/.nvm")
        #expect(Probes.abbreviate("/usr/bin/swift") == "/usr/bin/swift")
    }

    @Test("subdirectories lists only visible directories")
    func subdirectories() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("devshop-probe-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("3.3.0"),
                                                withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("3.10.0"),
                                                withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".hidden"),
                                                withIntermediateDirectories: true)
        try Data().write(to: root.appendingPathComponent("README"))
        defer { try? FileManager.default.removeItem(at: root) }

        let found = Probes.subdirectories(of: root.path)
        #expect(found.sorted() == ["3.10.0", "3.3.0"])
    }

    @Test("a missing directory is empty, not an error")
    func missingDirectory() {
        #expect(Probes.subdirectories(of: "/nope/definitely/not/here").isEmpty)
    }

    /// Several casks stage a `latest` symlink beside the real version directory. Counting
    /// it made the cask look like it had two versions installed, and `latest` sorted after
    /// every number, so it became the reported version.
    @Test("a symlink to a directory is not counted as a version of its own")
    func symlinkedVersionIsSkipped() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("devshop-caskroom-\(UUID().uuidString)")
        let real = root.appendingPathComponent("583.0.0")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("latest"),
                                                   withDestinationURL: real)
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(Probes.subdirectories(of: root.path) == ["583.0.0"])
        #expect(Probes.isSymbolicLink(root.appendingPathComponent("latest").path))
        #expect(!Probes.isSymbolicLink(real.path))
    }
}

// MARK: - Homebrew

@Suite("Homebrew")
struct HomebrewTests {
    @Test("versions sort numerically, not lexically")
    func numericSort() {
        let sorted = ["1.9.0", "1.10.0", "1.2.0"].sorted(by: HomebrewReader.versionLess)
        #expect(sorted == ["1.2.0", "1.9.0", "1.10.0"])
    }
}

// MARK: - Byte formatting

@Suite("Byte formatting")
struct ByteFormatTests {
    @Test("compact form matches the design's labels")
    func compact() {
        #expect(ByteFormat.compact(7_500_000_000) == "7.5G")
        #expect(ByteFormat.compact(466_000_000) == "466M")
        #expect(ByteFormat.compact(0) == "0B")
    }

    @Test("full form is used by the inspector")
    func full() {
        #expect(ByteFormat.full(7_500_000_000) == "7.50 GB")
        #expect(ByteFormat.full(466_000_000) == "466 MB")
        #expect(ByteFormat.full(45_056) == "45 KB")
        #expect(ByteFormat.full(512) == "512 bytes")
    }
}

// MARK: - Health

@Suite("Health")
struct HealthTests {
    @Test("each band starts exactly where the one below ends")
    func boundaries() {
        #expect(HealthStatus(score: 100) == .healthy)
        #expect(HealthStatus(score: 90) == .healthy)
        #expect(HealthStatus(score: 89) == .mostlyHealthy)
        #expect(HealthStatus(score: 70) == .mostlyHealthy)
        #expect(HealthStatus(score: 69) == .needsAttention)
        #expect(HealthStatus(score: 50) == .needsAttention)
        #expect(HealthStatus(score: 49) == .problems)
        #expect(HealthStatus(score: 0) == .problems)
    }

    @Test("the ring colour and the caption cannot disagree")
    func singleSource() {
        // Both come from HealthStatus, so every band has a label and a distinct colour.
        let colours = Set(HealthStatus.allCases.map(\.hex))
        #expect(colours.count == HealthStatus.allCases.count)
        #expect(HealthStatus.allCases.allSatisfy { !$0.label.isEmpty })
    }

    @Test("the score matches the weights the ring is drawn from")
    func scoreMatchesBand() {
        let findings = [
            Finding(id: "e", tier: .error, title: "", detail: "", scope: "", toolIDs: []),
            Finding(id: "w1", tier: .warning, title: "", detail: "", scope: "", toolIDs: []),
            Finding(id: "w2", tier: .warning, title: "", detail: "", scope: "", toolIDs: []),
            Finding(id: "w3", tier: .warning, title: "", detail: "", scope: "", toolIDs: []),
            Finding(id: "w4", tier: .warning, title: "", detail: "", scope: "", toolIDs: []),
            Finding(id: "n1", tier: .info, title: "", detail: "", scope: "", toolIDs: []),
            Finding(id: "n2", tier: .info, title: "", detail: "", scope: "", toolIDs: []),
            Finding(id: "n3", tier: .info, title: "", detail: "", scope: "", toolIDs: [])
        ]
        // 100 - 15 - (4 * 5) - 3
        #expect(findings.healthScore == 62)
        #expect(HealthStatus(score: findings.healthScore) == .needsAttention)
    }
}

// MARK: - Sorting

@Suite("Sorting")
struct SortTests {
    @Test("clicking the same column flips it, a different one switches to it")
    func toggling() {
        var sort = ToolSort()
        #expect(sort.field == .name && sort.ascending)
        sort.toggle(.name)
        #expect(sort.field == .name && !sort.ascending)
        // Size starts descending, because "biggest first" is what the question means.
        sort.toggle(.size)
        #expect(sort.field == .size && !sort.ascending)
        sort.toggle(.size)
        #expect(sort.ascending)
    }
}

// MARK: - Package contents

@Suite("Package contents")
struct ChildTests {
    @Test("a cask's build revision is trimmed off the version")
    func caskVersion() {
        // Homebrew writes "1.44121.0,a670de38..." into the Caskroom directory name.
        let child = ToolChild(id: "brew.casks/claude", token: "claude", name: "Claude",
                              version: "1.44121.0", path: "/tmp", appBundlePath: nil,
                              iconSlug: nil, color: "0a84ff")
        #expect(!child.version.contains(","))
    }

    @Test("a monogram falls back to the first two letters")
    func monogram() {
        let child = ToolChild(id: "x", token: "ripgrep", name: "ripgrep", version: "1",
                              path: "/tmp", appBundlePath: nil, iconSlug: nil, color: "0a84ff")
        #expect(child.monogram == "Ri")
    }

    @Test("the same name always gets the same tint")
    func stableTint() {
        #expect(ChildReaders.tint(for: "ripgrep") == ChildReaders.tint(for: "ripgrep"))
    }
}

// MARK: - SVG path parsing

@Suite("SVG path parsing")
struct SVGPathTests {
    @Test("absolute and relative commands produce the same square")
    func squares() throws {
        let absolute = try #require(SVGPath.parse("M0 0 L10 0 L10 10 L0 10 Z"))
        let relative = try #require(SVGPath.parse("m0 0 l10 0 l0 10 l-10 0 z"))
        #expect(absolute.boundingRect == relative.boundingRect)
        #expect(absolute.boundingRect == CGRect(x: 0, y: 0, width: 10, height: 10))
    }

    @Test("a real Simple Icons mark parses")
    func realMark() throws {
        // The Swift logo's opening subpath, verbatim from simple-icons.
        let data = "M14.663 0c.373.036.708.194 1.005.474.298.28.484.61.558.99"
                 + "l.223 1.19c.075.38.038.75-.111 1.115-.15.364-.39.652-.72.86"
                 + "l-1.005.65Z"
        let path = try #require(SVGPath.parse(data))
        #expect(!path.isEmpty)
        #expect(path.boundingRect.width > 0)
    }

    @Test("arcs are converted, not skipped")
    func arcs() throws {
        let path = try #require(SVGPath.parse("M0 5 A5 5 0 1 1 10 5 Z"))
        let bounds = path.boundingRect
        #expect(bounds.width.rounded() == 10)
        #expect(bounds.height > 4)
    }

    @Test("nonsense returns nil rather than a broken path")
    func rejectsGarbage() {
        #expect(SVGPath.parse("hello world") == nil)
        #expect(SVGPath.parse("") == nil)
    }
}

// MARK: - Findings

@Suite("Findings")
struct FindingsTests {
    /// A version-managed tile's own id carries the version, while its definition id does
    /// not — that split is what the duplicate rule keys on.
    private func tool(_ id: String,
                      name: String,
                      category: ToolCategory,
                      subtitle: String,
                      status: ToolStatus = .ok,
                      managedBy: String = "Homebrew") -> DetectedTool {
        let definitionID = id.split(separator: "@").first.map(String.init) ?? id
        return DetectedTool(
            id: id,
            definition: ToolDefinition(id: definitionID, name: name, category: category, icon: nil,
                                       symbol: "circle", color: "888888", website: nil,
                                       rules: [.executable(names: [name])], missingNote: nil),
            status: status,
            subtitle: subtitle,
            path: status == .missing ? nil : "/opt/homebrew/bin/\(name)",
            managedBy: managedBy,
            measurableRoot: nil
        )
    }

    @Test("a runtime past its EOL date is an error")
    func pastEOL() {
        let node = tool("lang.node", name: "Node.js", category: .lang, subtitle: "18.20.0 · nvm")
        let findings = FindingsEngine.evaluate(
            tools: [node], homebrew: .none,
            now: Calendar.current.date(from: DateComponents(year: 2026, month: 9))!)
        let eol = findings.first { $0.title.hasPrefix("Node.js 18") }
        #expect(eol?.tier == .error)
        #expect(eol?.title.hasSuffix("past end of life") == true)
        #expect(eol?.toolIDs == ["lang.node"])
    }

    @Test("a runtime with years left produces nothing")
    func healthyRuntime() {
        let node = tool("lang.node", name: "Node.js", category: .lang, subtitle: "24.1.0 · nvm")
        let findings = FindingsEngine.evaluate(
            tools: [node], homebrew: .none,
            now: Calendar.current.date(from: DateComponents(year: 2026, month: 9))!)
        #expect(!findings.contains { $0.title.contains("end of life") })
    }

    @Test("no container runtime is reported once")
    func containers() {
        let findings = FindingsEngine.evaluate(tools: [], homebrew: .none)
        #expect(findings.count { $0.id == "containers.none" } == 1)
    }

    @Test("two installs of one release line collapse into a single finding")
    func mergesReleaseLines() {
        let rubies = ["3.0.6", "3.0.7"].map {
            tool("lang.ruby@\($0)", name: "Ruby", category: .lang,
                 subtitle: "\($0) · rbenv", managedBy: "rbenv")
        }
        let findings = FindingsEngine.evaluate(
            tools: rubies, homebrew: .none,
            now: Calendar.current.date(from: DateComponents(year: 2026, month: 9))!)
        let eol = findings.filter { $0.title.contains("Ruby 3.0") }
        #expect(eol.count == 1)
        #expect(eol.first?.toolIDs.count == 2)
    }

    @Test("three managed versions of one runtime is a note")
    func duplicates() {
        let versions = ["3.2.2", "3.3.0", "3.3.6"].map {
            tool("lang.ruby@\($0)", name: "Ruby", category: .lang,
                 subtitle: "\($0) · rbenv", managedBy: "rbenv")
        }
        let findings = FindingsEngine.evaluate(tools: versions, homebrew: .none)
        let dupes = findings.first { $0.id == "dupes.lang.ruby" }
        #expect(dupes?.tier == .info)
        #expect(dupes?.toolIDs.count == 3)
    }

    @Test("health score subtracts the weighted penalties")
    func scoring() {
        let findings = [
            Finding(id: "a", tier: .error, title: "", detail: "", scope: "", toolIDs: []),
            Finding(id: "b", tier: .warning, title: "", detail: "", scope: "", toolIDs: []),
            Finding(id: "c", tier: .info, title: "", detail: "", scope: "", toolIDs: [])
        ]
        #expect(findings.healthScore == 79)
        #expect(findings.tally == "1 error · 1 warning · 1 note")
        #expect([Finding]().tally == "nothing needs attention")
    }
}

// MARK: - Size cache

@Suite("Size cache")
struct SizeCacheTests {
    @Test("round-trips through JSON")
    func roundTrip() throws {
        let cache = SizeCache(measuredAt: Date(timeIntervalSince1970: 1_700_000_000),
                              bytesByToolID: ["lang.swift": 1234, "ide.xcode": 4_000_000_000])
        let data = try JSONEncoder().encode(cache)
        let decoded = try JSONDecoder().decode(SizeCache.self, from: data)
        #expect(decoded.bytesByToolID == cache.bytesByToolID)
        #expect(decoded.measuredAt == cache.measuredAt)
        #expect(!decoded.isEmpty)
    }

    @Test("an empty cache is recognised")
    func empty() {
        #expect(SizeCache.empty.isEmpty)
    }
}

// MARK: - Size measurement

@Suite("Size measurement")
struct SizeMeasurementTests {
    @Test("a directory tree is summed")
    func sumsTree() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("devshop-size-\(UUID().uuidString)")
        let nested = root.appendingPathComponent("a/b")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 40_000).write(to: nested.appendingPathComponent("big.bin"))
        try Data(repeating: 0, count: 40_000).write(to: root.appendingPathComponent("also.bin"))
        defer { try? FileManager.default.removeItem(at: root) }

        let bytes = SizeMeasurer.allocatedSize(ofDirectory: root.path)
        #expect(bytes >= 80_000)
    }

    @Test("a path that does not exist measures zero")
    func missingPath() {
        #expect(SizeMeasurer.allocatedSize(ofDirectory: "/nope/not/here") == 0)
    }
}

// MARK: - Tile data

@Suite("Tile data")
struct TileDataTests {
    private func tool(path: String?, status: ToolStatus = .ok) -> DetectedTool {
        DetectedTool(
            id: "lang.node",
            definition: ToolDefinition(id: "lang.node", name: "Node.js", category: .lang,
                                       icon: "nodedotjs", symbol: "circle", color: "339933",
                                       website: nil, rules: [.executable(names: ["node"])],
                                       missingNote: nil),
            status: status,
            subtitle: "22.19.0 · nvm",
            path: path,
            managedBy: "nvm",
            measurableRoot: path,
            children: [ToolChild(id: "c", token: "t", name: "n", version: "1", path: "/tmp",
                                 appBundlePath: nil, iconSlug: nil, color: "0a84ff")]
        )
    }

    @Test("a tile carries what its tool draws, and nothing behind it")
    func mirrorsTheTool() {
        let source = tool(path: "/opt/homebrew/bin/node")
        let tile = TileData(tool: source, bytes: 1_500_000, findingTier: .warning)

        #expect(tile.id == source.id)
        #expect(tile.name == source.name)
        #expect(tile.subtitle == source.subtitle)
        #expect(tile.managedBy == source.managedBy)
        #expect(tile.status == source.status)
        #expect(tile.iconSlug == source.definition.icon)
        #expect(tile.symbol == source.definition.symbol)
        #expect(tile.colorHex == source.definition.color)
        #expect(tile.bytes == 1_500_000)
        #expect(tile.findingTier == .warning)
        #expect(!tile.isMissing)
    }

    @Test("the path is abbreviated once, where the row used to do it on every redraw")
    func abbreviatesThePath() {
        let inside = Probes.home + "/.nvm/versions/node/v22.19.0/bin/node"
        #expect(TileData(tool: tool(path: inside), bytes: 0, findingTier: nil).displayPath
            == Probes.abbreviate(inside))
        #expect(TileData(tool: tool(path: nil, status: .missing),
                         bytes: 0, findingTier: nil).displayPath == nil)
    }

    /// Equality is what lets `.equatable()` skip a tile whose inputs did not change, so a
    /// size landing has to register and an untouched neighbour has to not.
    @Test("only a real change compares unequal")
    func equality() {
        let source = tool(path: "/opt/homebrew/bin/node")
        let before = TileData(tool: source, bytes: 100, findingTier: nil)
        #expect(before == TileData(tool: source, bytes: 100, findingTier: nil))
        #expect(before != TileData(tool: source, bytes: 200, findingTier: nil))
        #expect(before != TileData(tool: source, bytes: 100, findingTier: .info))
    }
}

// MARK: - Version reading

@Suite("Version reading")
struct VersionReaderTests {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("devshop-version-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("a failed download is not mistaken for a version")
    func rejectsJunk() {
        // SDKMAN's `var/version` really does end up holding an nginx 404 page.
        #expect(VersionReaders.plausible("<html><head><title>404 Not Found</title>") == nil)
        #expect(VersionReaders.plausible("installed") == nil)
        #expect(VersionReaders.plausible("") == nil)
        #expect(VersionReaders.plausible("   ") == nil)
        #expect(VersionReaders.plausible("147 formulae · 52 casks") == nil)
    }

    @Test("a version keeps its shape, with any leading v dropped")
    func acceptsVersions() {
        #expect(VersionReaders.plausible("3.11.6") == "3.11.6")
        #expect(VersionReaders.plausible("v0.40.7") == "0.40.7")
        #expect(VersionReaders.plausible(" 2.2.0\n") == "2.2.0")
        #expect(VersionReaders.plausible("1.17.2-beta1") == "1.17.2-beta1")
    }

    @Test("a Python distribution states its version in the dist-info directory name")
    func distInfo() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let site = root.appendingPathComponent("lib/python3.14/site-packages")
        try FileManager.default.createDirectory(at: site, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: site.appendingPathComponent("poetry-2.2.0.dist-info"),
            withIntermediateDirectories: true)

        #expect(VersionReaders.distInfoVersion(package: "poetry",
                                               inSitePackagesUnder: root.path) == "2.2.0")
        #expect(VersionReaders.distInfoVersion(package: "pip",
                                               inSitePackagesUnder: root.path) == nil)
    }

    @Test("npm's own manifest is read for its version")
    func packageJSON() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("package.json")
        try #"{"name":"npm","version":"11.19.0"}"#.write(to: file, atomically: true,
                                                         encoding: .utf8)
        #expect(VersionReaders.packageJSONVersion(at: file.path) == "11.19.0")
        #expect(VersionReaders.packageJSONVersion(at: root.path + "/absent.json") == nil)
    }

    @Test("the newest versioned subdirectory wins, and it sorts numerically")
    func versionedDirectory() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["5.9", "5.10", "Extras"] {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        #expect(VersionReaders.versionedSubdirectory(of: root.path) == "5.10")
    }
}

extension SizeMeasurementTests {
    @Test("a symlinked root measures the file it points at")
    func followsSymlink() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("devshop-link-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let real = root.appendingPathComponent("clang")
        try Data(repeating: 0, count: 40_000).write(to: real)
        let link = root.appendingPathComponent("clang++")
        try fm.createSymbolicLink(at: link, withDestinationURL: real)

        #expect(SizeMeasurer.allocatedSize(ofDirectory: link.path) >= 40_000)
    }
}

extension VersionReaderTests {
    @Test("a man page header gives up its version, whatever order the fields are in")
    func titleHeader() {
        #expect(VersionReaders.version(
            inTitleHeader: #".TH curl 1 "March 12 2024" "curl 8.6.0" "curl Manual""#) == "8.6.0")
        #expect(VersionReaders.version(
            inTitleHeader: #".TH BASH 1 "2006 September 28" "GNU Bash-3.2""#) == "3.2")
    }

    @Test("groff escapes are removed and a build string is trimmed to three components")
    func titleHeaderEscapes() {
        // Apple's git page: `Git 2\&.50\&.1\&.428\&.g0e8243`.
        let line = #".TH "GIT" "1" "2025-07-22" "Git 2\&.50\&.1\&.428\&.g0e8243" "Git Manual""#
        #expect(VersionReaders.version(inTitleHeader: line) == "2.50.1")
    }

    @Test("a date is never mistaken for a version")
    func titleHeaderDates() {
        #expect(VersionReaders.version(inTitleHeader: #".TH "JQ" "1" "December 2023" "" """#) == nil)
        #expect(VersionReaders.version(inTitleHeader: #".TH FOO 1 "2025-07-22""#) == nil)
    }

    @Test("a -config script is read for the exact version, anchored on the tool's name")
    func configScript() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let bin = root.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try "#!/bin/sh\necho libcurl 8.7.1\n"
            .write(to: bin.appendingPathComponent("curl-config"), atomically: true, encoding: .utf8)

        let curl = bin.appendingPathComponent("curl").path
        #expect(VersionReaders.configScriptVersion(command: "curl", near: curl) == "8.7.1")
        #expect(VersionReaders.configScriptVersion(command: "wget", near: curl) == nil)
        #expect(VersionReaders.configScriptVersion(command: "curl", near: nil) == nil)
    }
}

// MARK: - Shell config parsing

@Suite("Shell config parsing")
struct ShellConfigParsingTests {
    private func parse(_ text: String, stage: LoadStage = .userRC) -> [ConfigEntry] {
        ShellConfigReader.parse(text, file: "~/.zshrc", stage: stage, home: "/Users/tester")
    }

    private func entry(_ entries: [ConfigEntry], _ id: String) -> ConfigEntry? {
        entries.first { $0.id == id }
    }

    @Test("an export becomes an environment entry")
    func export() {
        let entries = parse("export EDITOR=nvim")
        #expect(entries.count == 1)
        #expect(entries.first?.kind == .environment)
        #expect(entries.first?.name == "EDITOR")
        #expect(entries.first?.rawValue == "nvim")
        #expect(entries.first?.origins.first?.line == 1)
    }

    @Test("a bare assignment counts, but a conditional does not")
    func bareAssignment() {
        #expect(parse("LANG=en_US.UTF-8").first?.name == "LANG")
        #expect(parse("[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh").first?.kind == .source)
    }

    @Test("quotes are stripped from values")
    func quotes() {
        #expect(parse(#"export ZSH="$HOME/.oh-my-zsh""#).first?.rawValue == "$HOME/.oh-my-zsh")
        #expect(parse("export A='b c'").first?.rawValue == "b c")
    }

    @Test("comments are ignored, whole-line and trailing")
    func comments() {
        let entries = parse("""
        # export NOPE=1
        export YES=1 # trailing note
        """)
        #expect(entries.count == 1)
        #expect(entries.first?.name == "YES")
        #expect(entries.first?.rawValue == "1")
    }

    @Test("a hash inside a value is not a comment")
    func hashInValue() {
        #expect(parse(##"export COLOR="#ff9f0a""##).first?.rawValue == "#ff9f0a")
    }

    @Test("a PATH assignment becomes one entry per new directory")
    func pathSplit() {
        let entries = parse(#"export PATH="$HOME/bin:/opt/tools/bin:$PATH""#)
        #expect(entries.count == 2)
        #expect(entries.allSatisfy { $0.kind == .path })
        // $HOME is resolved against the injected home and abbreviated straight back.
        #expect(entry(entries, "path.~/bin") != nil)
        #expect(entry(entries, "path./opt/tools/bin") != nil)
    }

    @Test("the carried-forward $PATH is not an entry of its own")
    func pathCarryOver() {
        #expect(parse("export PATH=$JAVA_HOME/bin:$PATH").count == 1)
        #expect(parse("export PATH=$PATH").isEmpty)
    }

    @Test("an eval hook is named by the command it runs")
    func evalHook() {
        let entries = parse(#"eval "$(/opt/homebrew/bin/brew shellenv)""#)
        #expect(entries.first?.kind == .initHook)
        #expect(entries.first?.name == "brew shellenv")
        #expect(entries.first?.rawValue == "/opt/homebrew/bin/brew shellenv")
    }

    @Test("source is recognised plainly and behind a guard")
    func sources() {
        #expect(parse("source ~/.aliases").first?.kind == .source)
        #expect(parse("source ~/.aliases").first?.name == "~/.aliases")
        let guarded = parse(#"[ -s "/opt/nvm/nvm.sh" ] && \. "/opt/nvm/nvm.sh""#)
        #expect(guarded.first?.kind == .source)
        #expect(guarded.first?.name == "/opt/nvm/nvm.sh")
    }

    @Test("two sourced files with the same basename stay separate")
    func sourceIdentity() {
        var merged: [ConfigEntry] = []
        ShellConfigReader.merge(parse("source /opt/a/nvm.sh"), into: &merged)
        ShellConfigReader.merge(parse("source /opt/b/nvm.sh"), into: &merged)
        #expect(merged.count == 2)
    }

    @Test("aliases, options and framework settings are classified")
    func otherKinds() {
        #expect(parse("alias gs='git status'").first?.kind == .alias)
        #expect(parse("alias gs='git status'").first?.rawValue == "git status")
        #expect(parse("setopt COMBINING_CHARS").first?.kind == .option)
        #expect(parse("zmodload zsh/zprof").first?.kind == .option)
        #expect(parse("ZSH_THEME=robbyrussell").first?.kind == .framework)
        #expect(parse("typeset -g POWERLEVEL9K_MODE=ascii").first?.kind == .option)
    }

    @Test("a function is recorded and its body is not parsed")
    func functionBody() {
        let entries = parse("""
        greet() {
          export INSIDE=1
          alias hidden=nope
        }
        export OUTSIDE=1
        """)
        #expect(entries.map(\.kind) == [.function, .environment])
        #expect(entry(entries, "environment.INSIDE") == nil)
        #expect(entry(entries, "environment.OUTSIDE") != nil)
    }

    @Test("a multi-line array is one declaration, not several")
    func multiLineArray() {
        let entries = parse("""
        plugins=(
          git
          docker
        )
        export AFTER=1
        """)
        #expect(entries.count == 2)
        #expect(entry(entries, "framework.plugins")?.rawValue == "(git docker)")
        #expect(entry(entries, "environment.AFTER") != nil)
    }

    @Test("a line continuation is joined into one directive")
    func continuation() {
        let entries = parse("""
        export LONG=one\\
        two
        """)
        #expect(entries.count == 1)
        #expect(entries.first?.rawValue == "one two")
    }

    @Test("a path list file is read as plain directories")
    func pathListFile() {
        let entries = ShellConfigReader.parsePathList("""
        /usr/local/bin
        # a comment

        /usr/bin
        """, file: "/etc/paths", stage: .pathHelper, home: "/Users/tester")
        #expect(entries.count == 2)
        #expect(entries.allSatisfy { $0.kind == .path })
        #expect(entries.first?.origins.first?.line == 1)
        #expect(entries.last?.origins.first?.line == 4)
    }

    @Test("repeat declarations merge into one entry in load order")
    func merging() {
        var merged: [ConfigEntry] = []
        ShellConfigReader.merge(
            ShellConfigReader.parse("export JAVA_HOME=/jdk-21", file: "~/.zprofile",
                                    stage: .userProfile, home: "/Users/tester"),
            into: &merged)
        ShellConfigReader.merge(
            ShellConfigReader.parse("export JAVA_HOME=/jdk-22", file: "~/.zshrc",
                                    stage: .userRC, home: "/Users/tester"),
            into: &merged)
        #expect(merged.count == 1)
        let entry = try! #require(merged.first)
        #expect(entry.origins.count == 2)
        #expect(entry.isDuplicated)
        #expect(entry.hasConflictingOrigins)
        // The last declaration is the one the shell ends up with.
        #expect(entry.rawValue == "/jdk-22")
        #expect(entry.lastOrigin?.file == "~/.zshrc")
    }

    @Test("a repeat of the same value is not a conflict")
    func repeatedSameValue() {
        var merged: [ConfigEntry] = []
        for file in ["~/.zprofile", "~/.zshrc"] {
            ShellConfigReader.merge(
                ShellConfigReader.parse("export A=1", file: file, stage: .userRC,
                                        home: "/Users/tester"),
                into: &merged)
        }
        #expect(merged.first?.isDuplicated == true)
        #expect(merged.first?.hasConflictingOrigins == false)
    }
}

// MARK: - Secrets

@Suite("Config secrets")
struct ConfigSecretTests {
    @Test("a credential-shaped name is treated as a secret")
    func secretNames() {
        #expect(ShellConfigReader.isSecret(name: "GEMINI_API_KEY", value: "abc123"))
        #expect(ShellConfigReader.isSecret(name: "GITHUB_TOKEN", value: "abc123"))
        #expect(ShellConfigReader.isSecret(name: "DB_PASSWORD", value: "hunter2"))
        #expect(!ShellConfigReader.isSecret(name: "EDITOR", value: "nvim"))
        #expect(!ShellConfigReader.isSecret(name: "LANG", value: "en_US.UTF-8"))
    }

    @Test("a path is a location, not the secret itself")
    func locationsAreNotSecrets() {
        #expect(!ShellConfigReader.isSecret(name: "SSH_KEY_PATH", value: "~/.ssh/id_ed25519"))
        #expect(!ShellConfigReader.isSecret(name: "AWS_CA_BUNDLE", value: "/certs/ca.crt"))
        #expect(!ShellConfigReader.isSecret(name: "API_KEY", value: "$(pass show api)"))
    }

    @Test("known key shapes are caught whatever they are called")
    func secretValues() {
        #expect(ShellConfigReader.looksLikeSecretValue("ghp_0123456789abcdefghijklmnop"))
        #expect(ShellConfigReader.looksLikeSecretValue("AIzaSyA9yl7JYutmi1OGoUICoqyv9itUHMDp"))
        #expect(!ShellConfigReader.looksLikeSecretValue("en_US.UTF-8"))
        #expect(!ShellConfigReader.looksLikeSecretValue("dxfxcxdxbxegedabagacad"))
    }

    @Test("masking keeps the ends and hides the middle")
    func masking() {
        let masked = ShellConfigReader.mask("AIzaSyA9yl7JYutmiDpdA")
        #expect(masked.hasPrefix("AIza"))
        #expect(masked.hasSuffix("DpdA"))
        #expect(!masked.contains("SyA9yl7"))
        // A short value gives nothing away at all.
        #expect(!ShellConfigReader.mask("short").contains("s"))
    }

    @Test("a parsed secret is masked for display but kept for reveal")
    func parsedSecret() {
        let entries = ShellConfigReader.parse("export MY_API_KEY=ghp_0123456789abcdefghijkl",
                                              file: "~/.zshrc", stage: .userRC,
                                              home: "/Users/tester")
        let entry = try! #require(entries.first)
        #expect(entry.isSecret)
        #expect(entry.displayValue != entry.rawValue)
        #expect(entry.rawValue == "ghp_0123456789abcdefghijkl")
        #expect(entry.summary == "Secret value, hidden")
    }
}

// MARK: - Config rules

@Suite("Config rules")
struct ConfigRulesTests {
    private func snapshot(_ text: String,
                          stage: LoadStage = .userRC,
                          file: String = "~/.zshrc",
                          stale: [String] = [],
                          writable: [String] = []) -> ShellConfigSnapshot {
        var merged: [ConfigEntry] = []
        ShellConfigReader.merge(
            ShellConfigReader.parse(text, file: file, stage: stage, home: Probes.home),
            into: &merged)
        return ShellConfigSnapshot(shell: "/bin/zsh",
                                   entries: merged,
                                   filesRead: [],
                                   terminals: [],
                                   staleFiles: stale,
                                   writableFiles: writable)
    }

    private func finding(_ config: ShellConfigSnapshot, id: String) -> Finding? {
        ConfigRules.evaluate(config: config, tools: []).first { $0.id == id }
    }

    @Test("an empty chain produces nothing")
    func empty() {
        #expect(ConfigRules.evaluate(config: .empty, tools: []).isEmpty)
    }

    @Test("a plaintext secret is an error naming the file and line")
    func secret() {
        let config = snapshot("export MY_API_KEY=ghp_0123456789abcdefghijkl")
        let found = try! #require(finding(config, id: "config.secret.MY_API_KEY"))
        #expect(found.tier == .error)
        #expect(found.detail.contains("~/.zshrc:1"))
        #expect(found.toolIDs == ["environment.MY_API_KEY"])
        // The finding must never carry the value it is warning about.
        #expect(!found.detail.contains("ghp_0123456789abcdefghijkl"))
    }

    @Test("a PATH entry pointing nowhere is a warning")
    func missingPath() {
        let config = snapshot("export PATH=/definitely/not/here/bin:$PATH")
        let found = try! #require(finding(config, id: "config.path.missing"))
        #expect(found.tier == .warning)
        #expect(found.detail.contains("/definitely/not/here/bin"))
    }

    @Test("a missing PATH entry in a system file is left alone")
    func missingPathSystemFile() {
        let config = snapshot("/definitely/not/here/bin", stage: .pathHelper, file: "/etc/paths")
        // Parsed as shell text this is not an assignment, so build the entry directly.
        let entries = ShellConfigReader.parsePathList("/definitely/not/here/bin",
                                                      file: "/etc/paths",
                                                      stage: .pathHelper,
                                                      home: Probes.home)
        var system = config
        system.entries = entries
        #expect(finding(system, id: "config.path.missing") == nil)
    }

    @Test("a directory added to PATH twice is a note")
    func duplicatePath() {
        var config = snapshot("export PATH=/usr/local/bin:$PATH")
        ShellConfigReader.merge(
            ShellConfigReader.parse("export PATH=/usr/local/bin:$PATH", file: "~/.zprofile",
                                    stage: .userProfile, home: Probes.home),
            into: &config.entries)
        let found = try! #require(finding(config, id: "config.path.duplicate"))
        #expect(found.tier == .info)
    }

    @Test("PATH built in .zshrc is called out once, not once per directory")
    func pathInRC() {
        let config = snapshot("export PATH=/a/bin:/b/bin:/c/bin:$PATH")
        let all = ConfigRules.evaluate(config: config, tools: [])
        #expect(all.count { $0.id == "config.path.inrc" } == 1)
        #expect(finding(config, id: "config.path.inrc")?.tier == .info)
    }

    @Test("a single PATH line in .zshrc is not worth mentioning")
    func onePathInRCIsFine() {
        #expect(finding(snapshot("export PATH=/a/bin:$PATH"), id: "config.path.inrc") == nil)
    }

    @Test("sourcing a file that is not there is a warning")
    func missingSource() {
        let found = try! #require(finding(snapshot("source /definitely/not/here.zsh"),
                                          id: "config.source.missing"))
        #expect(found.tier == .warning)
    }

    @Test("a source path holding a variable is not judged")
    func unresolvableSource() {
        #expect(finding(snapshot("source $ZSH/oh-my-zsh.sh"), id: "config.source.missing") == nil)
    }

    @Test("profiling left on is a warning, unless a report is printed")
    func profiling() {
        #expect(finding(snapshot("zmodload zsh/zprof"), id: "config.zprof")?.tier == .warning)
        let reported = snapshot("""
        zmodload zsh/zprof
        zprof
        """)
        #expect(finding(reported, id: "config.zprof") == nil)
    }

    @Test("slow hooks are grouped into one note once there are two")
    func slowHooks() {
        let one = snapshot(#"eval "$(pyenv init -)""#)
        #expect(finding(one, id: "config.slow") == nil)
        let two = snapshot("""
        eval "$(pyenv init -)"
        eval "$(rbenv init -)"
        """)
        #expect(finding(two, id: "config.slow")?.tier == .info)
    }

    @Test("a variable pointing at a location that is gone is a warning")
    func dangling() {
        let found = try! #require(finding(snapshot("export JAVA_HOME=/no/such/jdk"),
                                          id: "config.dangling"))
        #expect(found.tier == .warning)
        #expect(found.detail.contains("JAVA_HOME"))
        #expect(finding(snapshot("export JAVA_HOME=/usr"), id: "config.dangling") == nil)
    }

    @Test("two files disagreeing about a value is a warning")
    func conflict() {
        var config = snapshot("export EDITOR=vim", stage: .userProfile, file: "~/.zprofile")
        ShellConfigReader.merge(
            ShellConfigReader.parse("export EDITOR=nvim", file: "~/.zshrc",
                                    stage: .userRC, home: Probes.home),
            into: &config.entries)
        let found = try! #require(finding(config, id: "config.conflict.EDITOR"))
        #expect(found.tier == .warning)
        #expect(found.detail.contains("~/.zprofile:1"))
        #expect(found.detail.contains("~/.zshrc:1"))
    }

    @Test("leftover config files and loose permissions are reported")
    func filesAroundTheChain() {
        let config = snapshot("export A=1",
                              stale: ["~/.zshrc.bak"],
                              writable: ["~/.zshrc"])
        #expect(finding(config, id: "config.stale")?.tier == .info)
        #expect(finding(config, id: "config.permissions")?.tier == .warning)
    }

    @Test("config findings reach the health score through the shared engine")
    func reachesHealthScore() {
        let config = snapshot("export MY_API_KEY=ghp_0123456789abcdefghijkl")
        let findings = FindingsEngine.evaluate(tools: [], homebrew: .none, config: config)
        #expect(findings.contains { $0.id == "config.secret.MY_API_KEY" })
        #expect(findings.healthScore < 100)
    }
}

// MARK: - Files around the startup chain

@Suite("Startup chain files")
struct StartupChainFileTests {
    @Test("backup copies are found and the live files are left alone")
    func staleFiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        for name in [".zshrc", ".zshrc.pre-oh-my-zsh", ".bash_profile copy",
                     ".bash_profile.pysave", ".zprofile", "notes.txt"] {
            try "".write(to: root.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        let stale = ShellConfigReader.staleFiles(home: root.path)
        #expect(stale == ["~/.bash_profile copy", "~/.bash_profile.pysave",
                          "~/.zshrc.pre-oh-my-zsh"])
    }

    @Test("a file others can write is reported, a private one is not")
    func writableFiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let loose = root.appendingPathComponent(".zshrc")
        let tight = root.appendingPathComponent(".zprofile")
        for url in [loose, tight] {
            try "".write(to: url, atomically: true, encoding: .utf8)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o646],
                                              ofItemAtPath: loose.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o600],
                                              ofItemAtPath: tight.path)

        let writable = ShellConfigReader.writableFiles([loose.path, tight.path], home: root.path)
        #expect(writable == ["~/.zshrc"])
    }

    @Test("the chain is read in load order and a sourced file contributes only environment")
    func readsChainInOrder() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let extra = root.appendingPathComponent("extra.zsh")
        try """
        export FROM_SOURCED=1
        setopt NOISE
        """.write(to: extra, atomically: true, encoding: .utf8)
        try """
        export FROM_RC=1
        source \(extra.path)
        """.write(to: root.appendingPathComponent(".zshrc"), atomically: true, encoding: .utf8)
        try "export FROM_PROFILE=1\n"
            .write(to: root.appendingPathComponent(".zprofile"), atomically: true, encoding: .utf8)

        let config = ShellConfigReader.read(home: root.path,
                                            environment: ["ZDOTDIR": root.path])
        #expect(config.entry(id: "environment.FROM_PROFILE") != nil)
        #expect(config.entry(id: "environment.FROM_RC") != nil)
        #expect(config.entry(id: "environment.FROM_SOURCED") != nil)
        // A sourced file's own options are its business, not the user's configuration.
        #expect(config.entry(id: "option.setopt NOISE") == nil)

        let stages = config.filesRead.map(\.stage)
        #expect(stages == stages.sorted())
        #expect(config.filesRead.contains { $0.stage == .sourced })
    }
}

// MARK: - Config groups

@Suite("Config groups")
@MainActor
struct ConfigGroupTests {
    @Test("the section follows the shell panel, and stands alone when that panel is gone")
    func placement() {
        let model = AppModel()
        // No scan has run, so no panel is visible and the section cannot follow one.
        #expect(!model.configFollowsShellPanel)
    }

    @Test("every kind carries its own explanation")
    func explanations() {
        let all = ConfigEntryKind.allCases.map(\.explanation)
        for (kind, text) in zip(ConfigEntryKind.allCases, all) {
            #expect(!text.isEmpty, "\(kind.rawValue) has no explanation")
            #expect(text.hasSuffix("."), "\(kind.rawValue) does not read as a sentence")
        }
        // A copy-paste between two cases would go unnoticed otherwise.
        #expect(Set(all).count == all.count)
    }

    @Test("every group starts collapsed")
    func collapsedByDefault() {
        let model = AppModel()
        #expect(ConfigEntryKind.allCases.allSatisfy { !model.isExpanded($0) })
    }

    @Test("toggling opens one group and leaves the rest alone")
    func toggle() {
        let model = AppModel()
        model.toggleConfigGroup(.path)
        #expect(model.isExpanded(.path))
        #expect(!model.isExpanded(.environment))
        model.toggleConfigGroup(.path)
        #expect(!model.isExpanded(.path))
    }

    @Test("a search shows matching rows whatever the collapse state, and restores it after")
    func searchOverridesCollapse() {
        let model = AppModel()
        model.query = "libpq"
        #expect(ConfigEntryKind.allCases.allSatisfy { model.isExpanded($0) })
        model.query = "   "
        #expect(ConfigEntryKind.allCases.allSatisfy { !model.isExpanded($0) })
    }
}

// MARK: - Search

@Suite("Search")
struct SearchFilterTests {
    private func child(_ token: String, name: String? = nil, version: String = "1.0") -> ToolChild {
        ToolChild(id: "brew.formulae/\(token)", token: token, name: name ?? token,
                  version: version, path: "/opt/homebrew/Cellar/\(token)/\(version)",
                  appBundlePath: nil, iconSlug: nil, color: "888888")
    }

    private func container(children: [ToolChild]) -> DetectedTool {
        var tool = DetectedTool(
            id: "brew.formulae",
            definition: ToolDefinition(id: "brew.formulae", name: "Formulae", category: .pkg,
                                       icon: nil, symbol: "circle", color: "888888", website: nil,
                                       rules: [.directory(path: "/opt/homebrew/Cellar", version: nil)],
                                       missingNote: nil),
            status: .ok,
            subtitle: "153 installed",
            path: "/opt/homebrew/Cellar",
            managedBy: "Homebrew",
            measurableRoot: "/opt/homebrew/Cellar"
        )
        tool.children = children
        return tool
    }

    @Test("a container matches on a package nested inside it")
    func matchesOnChild() {
        let tool = container(children: [child("libomp", version: "23.1.0"), child("summarize")])
        #expect(SearchFilter.matches(tool, query: "libomp"))
        #expect(SearchFilter.matches(tool, query: "LIBOMP"))
        #expect(!SearchFilter.matches(tool, query: "gcloud"))
    }

    @Test("an empty query matches everything")
    func emptyQuery() {
        #expect(SearchFilter.matches(container(children: []), query: ""))
        #expect(SearchFilter.matches(child("libomp"), query: ""))
    }

    @Test("a cask row is findable by the token it was installed under, not only its app name")
    func matchesOnToken() {
        let cask = child("gcloud-cli", name: "Google Cloud CLI", version: "583.0.0")
        #expect(SearchFilter.matches(cask, query: "gcloud-cli"))
        #expect(SearchFilter.matches(cask, query: "Google Cloud"))
        #expect(SearchFilter.matches(cask, query: "583"))
        #expect(!SearchFilter.matches(cask, query: "azure"))
    }

    @MainActor
    @Test("the contents list narrows to the matching entries")
    func contentsAreFiltered() {
        let model = AppModel()
        let tool = container(children: [child("libomp"), child("summarize"), child("libpq")])
        model.query = "libomp"
        #expect(model.children(of: tool).map(\.token) == ["libomp"])
        model.query = ""
        #expect(model.children(of: tool).count == 3)
    }

    @MainActor
    @Test("the contents list follows the column the centre list is sorted by")
    func contentsFollowTheSort() {
        let model = AppModel()
        let tool = container(children: [child("summarize"), child("libomp"), child("libpq")])

        // The default, and what the list header shows on launch.
        #expect(model.sort.field == .name && model.sort.ascending)
        #expect(model.children(of: tool).map(\.token) == ["libomp", "libpq", "summarize"])

        model.sort.toggle(.name)
        #expect(model.children(of: tool).map(\.token) == ["summarize", "libpq", "libomp"])

        // Size starts descending, and with nothing measured every child ties on zero, so
        // the name is what breaks the tie — descending, to match.
        model.sort.toggle(.size)
        #expect(model.children(of: tool).map(\.token) == ["summarize", "libpq", "libomp"])
    }
}
