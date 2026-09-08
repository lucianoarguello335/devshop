import Foundation

/// Where in the zsh startup sequence a file is read. The raw values are the load order, so
/// origins sort into the sequence the shell actually runs them in — which is what decides
/// which of two conflicting declarations wins.
enum LoadStage: Int, Codable, Sendable, Comparable, CaseIterable {
    case systemEnv = 0
    case userEnv
    case pathHelper
    case systemProfile
    case userProfile
    case systemRC
    case userRC
    case login
    case sourced

    var label: String {
        switch self {
        case .systemEnv: "System env"
        case .userEnv: "User env"
        case .pathHelper: "path_helper"
        case .systemProfile: "System profile"
        case .userProfile: "User profile"
        case .systemRC: "System rc"
        case .userRC: "User rc"
        case .login: "Login"
        case .sourced: "Sourced"
        }
    }

    /// True for the files a user is expected to edit. Used to keep "you put this in the
    /// wrong file" advice off files the user does not own.
    var isUserOwned: Bool {
        switch self {
        case .userEnv, .userProfile, .userRC, .login, .sourced: true
        case .systemEnv, .pathHelper, .systemProfile, .systemRC: false
        }
    }

    static func < (a: LoadStage, b: LoadStage) -> Bool { a.rawValue < b.rawValue }
}

/// One place a directive is declared: which file, which line, and the line verbatim.
struct ConfigOrigin: Sendable, Equatable, Codable {
    /// Abbreviated with `~`, as everything user-facing in this app is.
    var file: String
    var line: Int
    var stage: LoadStage
    /// The source line as written, trimmed of surrounding whitespace.
    var text: String

    var location: String { "\(file):\(line)" }
}

/// What kind of thing a directive is. Also the grouping used by the centre column.
enum ConfigEntryKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case path
    case environment
    case initHook
    case source
    case framework
    case alias
    case function
    case option

    var id: String { rawValue }

    /// Section subhead in the centre column, in display order.
    var groupTitle: String {
        switch self {
        case .path: "PATH"
        case .environment: "Environment"
        case .initHook: "Init hooks"
        case .source: "Sourced files"
        case .framework: "Framework"
        case .alias: "Aliases"
        case .function: "Functions"
        case .option: "Options"
        }
    }

    /// Singular label shown in the inspector's Kind row.
    var inspectorLabel: String {
        switch self {
        case .path: "PATH entry"
        case .environment: "Environment variable"
        case .initHook: "Init hook"
        case .source: "Sourced file"
        case .framework: "Framework setting"
        case .alias: "Alias"
        case .function: "Function"
        case .option: "Shell option"
        }
    }

    /// What the group is, and what goes wrong when it is not what you thought. Shown on the
    /// group's info icon in the centre column and under the name in the inspector, from this
    /// one string so the two cannot drift apart.
    var explanation: String {
        switch self {
        case .path:
            "Directories the shell searches for commands, in the order it searches them. "
          + "The first match wins, so a duplicate or a missing directory quietly changes "
          + "which tool actually runs."
        case .environment:
            "Variables every program started from a terminal inherits. Tools read these "
          + "rather than asking, so a stale value fails much later and blames something else."
        case .initHook:
            "Commands run at every shell start whose output the shell then evaluates. They "
          + "are how version managers take over PATH, and they are usually most of the wait "
          + "before the first prompt."
        case .source:
            "Other files read in as if their contents were pasted into this one. Everything "
          + "they define arrives too, which is why a shell can behave in ways no file you "
          + "wrote explains."
        case .framework:
            "Settings for a shell framework such as oh-my-zsh \u{2014} its install location, "
          + "theme and plugin list. Every plugin listed here is more work at every shell start."
        case .alias:
            "Short names that expand to a longer command before it runs. They exist only in "
          + "interactive shells, so a script or a colleague running the same command gets "
          + "the real one."
        case .function:
            "Named blocks of shell code defined at startup and run on demand. Defining one "
          + "costs nothing until it is called, unlike an init hook."
        case .option:
            "Switches that change how zsh itself behaves \u{2014} history, completion, key "
          + "bindings and prompt settings. They affect the shell rather than the programs "
          + "it runs."
        }
    }

    var symbol: String {
        switch self {
        case .path: "arrow.triangle.branch"
        case .environment: "equal.square.fill"
        case .initHook: "bolt.fill"
        case .source: "doc.text.fill"
        case .framework: "puzzlepiece.extension.fill"
        case .alias: "arrow.left.arrow.right"
        case .function: "function"
        case .option: "slider.horizontal.3"
        }
    }

    var accentHex: String {
        switch self {
        case .path: "0a84ff"
        case .environment: "30d158"
        case .initHook: "ff9f0a"
        case .source: "5e5ce6"
        case .framework: "bf5af2"
        case .alias: "64d2ff"
        case .function: "ff6482"
        case .option: "8e8e93"
        }
    }
}

/// One unique thing the shell does at startup.
///
/// The same variable exported in two files collapses into a single entry carrying both
/// origins — that is what "unique" means here, and it is what makes a conflict visible as
/// one row rather than two unrelated ones.
struct ConfigEntry: Sendable, Identifiable, Equatable {
    /// Namespaced so it cannot collide with a `DetectedTool` id: `env.JAVA_HOME`,
    /// `path./opt/homebrew/bin`.
    var id: String
    var kind: ConfigEntryKind
    var name: String
    /// What the inspector and the row show. Masked when `isSecret`.
    var displayValue: String
    /// The value as written. Never written to any export while `isSecret` is true.
    var rawValue: String
    var isSecret: Bool = false
    /// Every declaration, in load order. The last one is what the shell ends up with.
    var origins: [ConfigOrigin] = []
    /// One line of plain English for the row.
    var summary: String = ""

    var lastOrigin: ConfigOrigin? { origins.last }
    var isDuplicated: Bool { origins.count > 1 }

    /// True when two declarations disagree about the value, rather than merely repeating it.
    var hasConflictingOrigins: Bool {
        guard origins.count > 1 else { return false }
        return Set(origins.map(\.text)).count > 1
    }
}

/// Everything the reader could learn about the startup chain in one pass.
struct ShellConfigSnapshot: Sendable, Equatable {
    /// The login shell this snapshot describes, e.g. `/bin/zsh`.
    var shell: String
    var entries: [ConfigEntry]
    /// One entry per file actually read, in load order, with `line` holding its line count.
    var filesRead: [ConfigOrigin]
    var terminals: [TerminalApp]
    /// Backup and leftover dotfiles found next to the live ones. Abbreviated paths.
    var staleFiles: [String]
    /// Files whose permissions let someone other than the owner write them.
    var writableFiles: [String]

    static let empty = ShellConfigSnapshot(shell: "/bin/zsh",
                                           entries: [],
                                           filesRead: [],
                                           terminals: [],
                                           staleFiles: [],
                                           writableFiles: [])

    var isEmpty: Bool { entries.isEmpty && terminals.isEmpty }

    func entry(id: String) -> ConfigEntry? { entries.first { $0.id == id } }

    /// "7 files · 34 entries", the meta line beside the section title.
    var meta: String {
        let files = "\(filesRead.count) file\(filesRead.count == 1 ? "" : "s")"
        let items = "\(entries.count) entr\(entries.count == 1 ? "y" : "ies")"
        return "\(files) · \(items)"
    }
}

/// One kind's worth of entries, ready for the centre column to draw.
struct ConfigGroup: Identifiable, Equatable, Sendable {
    var kind: ConfigEntryKind
    var entries: [ConfigEntry]
    var id: String { kind.rawValue }
}
