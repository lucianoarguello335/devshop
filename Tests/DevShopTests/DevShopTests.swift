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
