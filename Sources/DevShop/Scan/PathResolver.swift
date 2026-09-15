import Foundation

/// A kind of shell whose PATH is worth comparing.
enum ShellContext: String, CaseIterable, Sendable, Identifiable {
    /// A new Terminal or iTerm window: a login shell started from launchd's PATH.
    case loginTerminal
    /// A login shell started from a shell that already built PATH — an editor's terminal,
    /// tmux, `zsh -l`. The chain runs a second time, and path_helper reorders what it inherits.
    case nestedLogin

    var id: String { rawValue }

    var label: String {
        switch self {
        case .loginTerminal: "Login terminal"
        case .nestedLogin: "Nested login"
        }
    }

    var explanation: String {
        switch self {
        case .loginTerminal:
            "A new Terminal window. zsh starts from the system default PATH and runs "
          + "zshenv, zprofile, zshrc and zlogin once."
        case .nestedLogin:
            "A login shell started from one that already set PATH, such as an editor's "
          + "built-in terminal or tmux. The chain runs again, and path_helper moves the system "
          + "directories back in front of what it inherited."
        }
    }
}

/// One directory on a resolved PATH, and the line that put it there.
struct ResolvedDir: Sendable, Equatable {
    var path: String
    /// `nil` for launchd's default PATH, which no file sets.
    var setBy: ConfigOrigin?
    var isConditional: Bool = false
    var isFromPathHelper: Bool = false
    /// For a path_helper directory, the `/etc/paths*` file that lists it.
    var helperSource: String?

    /// Where to go to change this directory: the list file for path_helper, the line
    /// otherwise. Never the `eval` line in /etc/zprofile, which names no directory.
    var sourceLabel: String {
        guard isFromPathHelper else { return setBy?.location ?? "system default" }
        let source = sourceFile
        let short = source.hasPrefix("/etc/") ? String(source.dropFirst("/etc/".count)) : source
        return "path_helper \u{00b7} \(short)"
    }

    /// The full path of the file to open, for tooltips.
    var sourceFile: String {
        isFromPathHelper ? helperSource ?? "/etc/paths" : setBy?.location ?? "system default"
    }

    /// For narrow columns: `homebrew` rather than `path_helper · paths.d/homebrew`. The full
    /// `sourceFile` goes in the tooltip.
    var shortSourceLabel: String {
        guard isFromPathHelper else { return sourceLabel }
        return URL(fileURLWithPath: sourceFile).lastPathComponent
    }
}

/// A position in PATH. A hook is kept as a slot of its own, because what it adds lands at
/// that position — everything behind it may be outranked by something no file names.
enum PathSlot: Sendable, Equatable {
    case dir(ResolvedDir)
    case hook(PathStep)

    var dirPath: String? { if case .dir(let dir) = self { dir.path } else { nil } }
}

extension PathStep {
    /// What a user recognises a hook by: `brew shellenv`, `pyenv init -`, `nvm.sh`.
    var hookName: String {
        let text = origin.text
        if let hook = ShellConfigReader.evalHook(in: text) {
            // `pyenv init -` reads as a typo; the lone dash is a flag, not part of the name.
            return hook.name.split(separator: " ").filter { $0 != "-" }.joined(separator: " ")
        }
        if let target = ShellConfigReader.sourcedFile(in: text) {
            // `${TERM}-${VENDOR}` is not a name anyone recognises; the line they can open is.
            guard !target.contains("$") else { return "\(origin.location) \u{00b7} source" }
            return URL(fileURLWithPath: target).lastPathComponent
        }
        return origin.location
    }

    /// False when `hookName` had to fall back to a file and line.
    var hasRecognisableName: Bool { !hookName.hasPrefix(origin.location) }

    /// The directories a prepend or append adds, for the "already there" guard.
    var addedPaths: [String]? {
        switch operation {
        case .prepend(let paths), .append(let paths): paths
        default: nil
        }
    }
}

struct ResolvedPath: Sendable, Equatable {
    var context: ShellContext
    var slots: [PathSlot]

    var dirs: [ResolvedDir] {
        slots.compactMap { if case .dir(let dir) = $0 { dir } else { nil } }
    }
}

/// Where a command is found in one context.
struct CommandHit: Sendable, Equatable {
    /// The executable PATH lookup lands on, abbreviated.
    var path: String
    var dir: ResolvedDir
    /// Every hook ahead of this directory, in the order the shell runs them. Any of them
    /// could put something in front that wins instead.
    var hooksAhead: [PathStep] = []

    var isUncertain: Bool { !hooksAhead.isEmpty }

    /// `brew shellenv, pyenv init - and 7 more` — names, not line numbers, because a row has
    /// room for a phrase and the inspector lists the lines.
    var hooksSummary: String {
        // Most likely to change PATH first: a hook with a real name in a file the user wrote
        // (`nvm.sh`, `pyenv init -`), then ones known only by line, then system files. Stable,
        // so equal hooks keep run order.
        func rank(_ step: PathStep) -> Int {
            (step.origin.stage.isUserOwned ? 0 : 2) + (step.hasRecognisableName ? 0 : 1)
        }
        let ranked = hooksAhead.enumerated()
            .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
            .map(\.element)
        var names: [String] = []
        for name in ranked.map(\.hookName) where !names.contains(name) { names.append(name) }
        guard names.count > 3 else {
            guard names.count > 1 else { return names.first ?? "" }
            return names.dropLast().joined(separator: ", ") + " and " + (names.last ?? "")
        }
        return names.prefix(3).joined(separator: ", ") + " and \(names.count - 3) more"
    }
}

struct CommandResolution: Sendable, Equatable, Identifiable {
    var command: String
    var hits: [ShellContext: CommandHit]
    var id: String { command }

    func hit(in context: ShellContext) -> CommandHit? { hits[context] }

    /// The two contexts run different executables.
    var differs: Bool {
        hits[.loginTerminal]?.path != hits[.nestedLogin]?.path
    }

    var isUncertain: Bool { hits.values.contains(where: \.isUncertain) }
}

/// Everything the Resolved PATH view and its finding read.
struct PathResolution: Sendable, Equatable {
    var paths: [ShellContext: ResolvedPath]
    var commands: [CommandResolution]

    static let empty = PathResolution(paths: [:], commands: [])

    func path(for context: ShellContext) -> ResolvedPath? { paths[context] }
}

/// Builds PATH the way zsh would, from the steps the reader found, without running anything.
///
/// Like `ShellConfigReader`, nothing here spawns a process. `resolve` is pure; only
/// `resolution(for:)` touches the filesystem, and only to ask whether a file is executable.
enum PathResolver {

    /// What launchd hands a login shell before any file runs.
    static let launchdDefault = ["/usr/bin", "/bin", "/usr/sbin", "/sbin"]

    /// Commands people most often find resolving to the wrong copy.
    static let commands = ["python3", "python", "pip3", "node", "npm", "ruby", "gem",
                           "java", "go", "cargo", "swift", "git"]

    static func resolution(for config: ShellConfigSnapshot,
                           commands: [String] = commands,
                           home: String = Probes.home,
                           fileManager: FileManager = .default) -> PathResolution {
        let login = resolve(config, context: .loginTerminal,
                            start: launchdDefault.map { .dir(ResolvedDir(path: $0)) })
        let nested = resolve(config, context: .nestedLogin, start: login.slots)
        let paths: [ShellContext: ResolvedPath] = [.loginTerminal: login, .nestedLogin: nested]

        let resolutions: [CommandResolution] = commands.compactMap { command in
            var hits: [ShellContext: CommandHit] = [:]
            for (context, path) in paths {
                hits[context] = lookup(command, in: path, home: home) {
                    fileManager.isExecutableFile(atPath: $0)
                }
            }
            return hits.isEmpty ? nil : CommandResolution(command: command, hits: hits)
        }
        return PathResolution(paths: paths, commands: resolutions)
    }

    /// Applies the chain's steps on top of `start`. Pure.
    static func resolve(_ config: ShellConfigSnapshot,
                        context: ShellContext,
                        start: [PathSlot]) -> ResolvedPath {
        var slots = start

        for step in config.pathSteps {
            func dirs(_ paths: [String]) -> [PathSlot] {
                paths.map { .dir(ResolvedDir(path: $0, setBy: step.origin,
                                             isConditional: step.isConditional)) }
            }
            if step.skipsIfPresent, let added = step.addedPaths,
               added.allSatisfy({ path in slots.contains { $0.dirPath == path } }) {
                continue
            }
            switch step.operation {
            case .prepend(let paths): slots = dirs(paths) + slots
            case .append(let paths): slots += dirs(paths)
            case .replace(let paths): slots = dirs(paths)
            case .unknown: slots.insert(.hook(step), at: 0)
            case .pathHelper:
                let system = config.pathHelperDirs
                let fronted = system.map { path in
                    PathSlot.dir(ResolvedDir(path: path, setBy: step.origin, isFromPathHelper: true,
                                             helperSource: config.pathHelperSources[path]))
                }
                let rest = slots.filter {
                    if case .dir(let dir) = $0 { !system.contains(dir.path) } else { true }
                }
                slots = fronted + rest
            }
            if config.pathIsUnique { slots = firstOccurrences(slots) }
        }
        return ResolvedPath(context: context, slots: slots)
    }

    /// PATH lookup: the first directory holding an executable wins. Hooks passed on the way
    /// are remembered, not skipped silently.
    static func lookup(_ command: String,
                       in path: ResolvedPath,
                       home: String,
                       isExecutable: (String) -> Bool) -> CommandHit? {
        var hooks: [PathStep] = []
        for slot in path.slots {
            switch slot {
            case .hook(let step):
                if !hooks.contains(step) { hooks.append(step) }
            case .dir(let dir):
                let full = expand(dir.path, home: home) + "/" + command
                if isExecutable(full) {
                    return CommandHit(path: ShellConfigReader.abbreviate(full, home: home),
                                      // Slots hold the last-run hook first; flip to run order.
                                      dir: dir, hooksAhead: hooks.reversed())
                }
            }
        }
        return nil
    }

    private static func firstOccurrences(_ slots: [PathSlot]) -> [PathSlot] {
        var seen: Set<String> = []
        return slots.filter {
            guard case .dir(let dir) = $0 else { return true }
            return seen.insert(dir.path).inserted
        }
    }

    private static func expand(_ path: String, home: String) -> String {
        path.hasPrefix("~") ? home + path.dropFirst() : path
    }
}
