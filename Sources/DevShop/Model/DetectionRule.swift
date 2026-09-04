import Foundation

/// How a catalog entry is located on disk. Rules are tried in order; the first hit
/// supplies the install path and version. Every rule is a pure filesystem read —
/// no subprocess is ever spawned.
enum DetectionRule: Sendable, Codable, Equatable {
    /// An executable on a fixed search list of bin directories.
    case executable(names: [String])
    /// A Homebrew formula: `/opt/homebrew/Cellar/<name>/<version>`.
    case brewFormula(name: String)
    /// A Homebrew cask: `/opt/homebrew/Caskroom/<name>/<version>`.
    case brewCask(name: String)
    /// An application bundle; version comes from `CFBundleShortVersionString`.
    case appBundle(paths: [String])
    /// A directory that simply has to exist.
    case directory(path: String, version: String?)
    /// A version manager whose installed versions each become their own tile.
    case versionManager(VersionManagerKind)

    private enum Kind: String, Codable {
        case executable, brewFormula, brewCask, appBundle, directory, versionManager
    }

    private enum CodingKeys: String, CodingKey {
        case kind, names, name, paths, path, version, manager
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .executable:
            self = .executable(names: try c.decode([String].self, forKey: .names))
        case .brewFormula:
            self = .brewFormula(name: try c.decode(String.self, forKey: .name))
        case .brewCask:
            self = .brewCask(name: try c.decode(String.self, forKey: .name))
        case .appBundle:
            self = .appBundle(paths: try c.decode([String].self, forKey: .paths))
        case .directory:
            self = .directory(path: try c.decode(String.self, forKey: .path),
                              version: try c.decodeIfPresent(String.self, forKey: .version))
        case .versionManager:
            self = .versionManager(try c.decode(VersionManagerKind.self, forKey: .manager))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .executable(let names):
            try c.encode(Kind.executable, forKey: .kind)
            try c.encode(names, forKey: .names)
        case .brewFormula(let name):
            try c.encode(Kind.brewFormula, forKey: .kind)
            try c.encode(name, forKey: .name)
        case .brewCask(let name):
            try c.encode(Kind.brewCask, forKey: .kind)
            try c.encode(name, forKey: .name)
        case .appBundle(let paths):
            try c.encode(Kind.appBundle, forKey: .kind)
            try c.encode(paths, forKey: .paths)
        case .directory(let path, let version):
            try c.encode(Kind.directory, forKey: .kind)
            try c.encode(path, forKey: .path)
            try c.encodeIfPresent(version, forKey: .version)
        case .versionManager(let manager):
            try c.encode(Kind.versionManager, forKey: .kind)
            try c.encode(manager, forKey: .manager)
        }
    }
}

/// Version managers that install several toolchain versions side by side. Each installed
/// version becomes its own tile, the way the design shows three Rubies.
enum VersionManagerKind: String, Sendable, Codable {
    case nvm, pyenv, rbenv, jenv, jvm, xcodeToolchains

    /// Directory holding one subdirectory per installed version.
    var root: String {
        switch self {
        case .nvm: "~/.nvm/versions/node"
        case .pyenv: "~/.pyenv/versions"
        case .rbenv: "~/.rbenv/versions"
        case .jenv: "~/.jenv/versions"
        case .jvm: "/Library/Java/JavaVirtualMachines"
        case .xcodeToolchains: "/Library/Developer/Toolchains"
        }
    }

    var managerName: String {
        switch self {
        case .nvm: "nvm"
        case .pyenv: "pyenv"
        case .rbenv: "rbenv"
        case .jenv: "jenv"
        case .jvm: "JVM install"
        case .xcodeToolchains: "Xcode toolchain"
        }
    }
}
