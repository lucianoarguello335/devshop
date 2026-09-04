import Foundation

/// Reads Homebrew's on-disk layout directly. `Cellar/<formula>/<version>` and
/// `Caskroom/<cask>/<version>` mean exact versions and accurate counts are available
/// without ever running `brew`.
struct HomebrewReader: Sendable {
    struct Installed: Sendable {
        var version: String
        var path: String
    }

    let prefix: String
    private(set) var formulae: [String: Installed] = [:]
    private(set) var casks: [String: Installed] = [:]

    var isInstalled: Bool { Probes.isDirectory(prefix) }
    var formulaCount: Int { formulae.count }
    var caskCount: Int { casks.count }

    init() {
        // Apple silicon first, then the Intel prefix.
        prefix = Probes.isDirectory("/opt/homebrew") ? "/opt/homebrew" : "/usr/local/Homebrew"
        guard isInstalled else { return }
        formulae = Self.read(root: cellarPath)
        casks = Self.read(root: caskroomPath)
    }

    var cellarPath: String {
        prefix == "/opt/homebrew" ? "/opt/homebrew/Cellar" : "/usr/local/Cellar"
    }

    var caskroomPath: String {
        prefix == "/opt/homebrew" ? "/opt/homebrew/Caskroom" : "/usr/local/Caskroom"
    }

    /// Each package directory holds one subdirectory per installed version. When several
    /// are present the last one sorted is reported and the rest are still counted, which
    /// is what surfaces "old versions left behind".
    private static func read(root: String) -> [String: Installed] {
        var result: [String: Installed] = [:]
        for package in Probes.subdirectories(of: root) {
            let packagePath = root + "/" + package
            let versions = Probes.subdirectories(of: packagePath)
            guard let latest = versions.sorted(by: versionLess).last else { continue }
            result[package] = Installed(version: latest, path: packagePath + "/" + latest)
        }
        return result
    }

    /// Numeric-aware comparison so `1.10.0` sorts after `1.9.0`.
    static func versionLess(_ a: String, _ b: String) -> Bool {
        a.compare(b, options: .numeric) == .orderedAscending
    }

    /// Every version directory for a package, used to spot stale copies.
    func versions(ofFormula name: String) -> [String] {
        Probes.subdirectories(of: cellarPath + "/" + name)
    }

    func versions(ofCask name: String) -> [String] {
        Probes.subdirectories(of: caskroomPath + "/" + name)
    }
}
