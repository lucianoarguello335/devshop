import Foundation

/// Derives what needs attention from the shell startup chain.
///
/// Every rule is a string comparison or a single `stat`, so the whole pass costs nothing
/// measurable next to the size walk. Rules that can match many entries emit one grouped
/// finding rather than one per entry: twelve separate "PATH set in the wrong file" rows
/// would bury the one error that matters and wreck the health score for a single mistake.
enum ConfigRules {
    static func evaluate(config: ShellConfigSnapshot,
                         tools: [DetectedTool],
                         fileManager: FileManager = .default) -> [Finding] {
        guard !config.entries.isEmpty else { return [] }
        var findings: [Finding] = []
        findings += plaintextSecrets(config)
        findings += missingPathDirectories(config, fileManager: fileManager)
        findings += duplicatePathEntries(config)
        findings += pathSetInInteractiveFile(config)
        findings += missingSourcedFiles(config, fileManager: fileManager)
        findings += profilingLeftEnabled(config)
        findings += slowInitHooks(config)
        findings += danglingLocations(config, tools: tools, fileManager: fileManager)
        findings += conflictingDeclarations(config)
        findings += aliasesShadowingExecutables(config)
        findings += staleBackupFiles(config)
        findings += worldWritableFiles(config)
        return findings
    }

    // MARK: - Rules

    /// A credential written into a dotfile. Every process the user starts inherits it, it
    /// ends up in backups, and it is one `cat` away from any screen share.
    private static func plaintextSecrets(_ config: ShellConfigSnapshot) -> [Finding] {
        config.entries.filter(\.isSecret).map { entry in
            let origin = entry.lastOrigin
            return Finding(
                id: "config.secret.\(entry.name)",
                tier: .error,
                title: "\(entry.name) is stored in plaintext",
                detail: "A credential is exported from \(origin?.location ?? "a startup file"), "
                      + "so every process started from a terminal inherits it and it survives "
                      + "in backups. Move it to the Keychain, a password manager's CLI, or a "
                      + "per-project .env file that is not committed.",
                scope: "Terminal Config · \(origin?.file ?? "Environment")",
                toolIDs: [entry.id])
        }
    }

    /// PATH pointing at somewhere that no longer exists. Harmless at runtime, but it is the
    /// fingerprint of a tool that was removed without its config being cleaned up.
    private static func missingPathDirectories(_ config: ShellConfigSnapshot,
                                               fileManager: FileManager) -> [Finding] {
        // Only what the user wrote. macOS ships /etc/paths.d entries for cryptex mounts
        // that genuinely are not on disk, and telling someone to fix a file they do not own
        // is worse than saying nothing.
        let missing = config.entries.filter {
            $0.kind == .path && !$0.rawValue.contains("$")
                && $0.origins.contains { $0.stage.isUserOwned }
                && !fileManager.fileExists(atPath: Probes.expand($0.rawValue))
        }
        guard !missing.isEmpty else { return [] }
        return [Finding(
            id: "config.path.missing",
            tier: .warning,
            title: "\(missing.count) PATH entr\(missing.count == 1 ? "y points" : "ies point") "
                 + "at a directory that does not exist",
            detail: "\(list(missing.map(\.name))) \(missing.count == 1 ? "is" : "are") added to "
                  + "PATH but not present on disk. Every command lookup searches "
                  + "\(missing.count == 1 ? "it" : "them") first and finds nothing.",
            scope: "Terminal Config · PATH",
            toolIDs: missing.map(\.id))]
    }

    /// The same directory added to PATH more than once.
    private static func duplicatePathEntries(_ config: ShellConfigSnapshot) -> [Finding] {
        let duplicated = config.entries.filter {
            $0.kind == .path && $0.isDuplicated && $0.origins.contains { $0.stage.isUserOwned }
        }
        guard !duplicated.isEmpty else { return [] }
        return [Finding(
            id: "config.path.duplicate",
            tier: .info,
            title: "\(duplicated.count) PATH entr\(duplicated.count == 1 ? "y is" : "ies are") "
                 + "added more than once",
            detail: "\(list(duplicated.map(\.name))) appear\(duplicated.count == 1 ? "s" : "") "
                  + "in the startup chain twice or more. Only the first copy is ever used; the "
                  + "rest just make PATH longer to search.",
            scope: "Terminal Config · PATH",
            toolIDs: duplicated.map(\.id))]
    }

    /// PATH built in `.zshrc` rather than `.zprofile`. `.zshrc` runs for every interactive
    /// shell, so each nested shell prepends the same directories again.
    private static func pathSetInInteractiveFile(_ config: ShellConfigSnapshot) -> [Finding] {
        let inRC = config.entries.filter {
            $0.kind == .path && $0.origins.contains { $0.stage == .userRC }
        }
        guard inRC.count >= 2 else { return [] }
        return [Finding(
            id: "config.path.inrc",
            tier: .info,
            title: "\(inRC.count) PATH entries are set in ~/.zshrc rather than ~/.zprofile",
            detail: "~/.zshrc runs for every interactive shell, so opening a shell inside a "
                  + "shell prepends the same directories again and PATH grows each time. "
                  + "PATH belongs in ~/.zprofile, which runs once per login.",
            scope: "Terminal Config · ~/.zshrc",
            toolIDs: inRC.map(\.id))]
    }

    /// A `source` pointing at a file that is gone. zsh prints an error on every new shell.
    private static func missingSourcedFiles(_ config: ShellConfigSnapshot,
                                            fileManager: FileManager) -> [Finding] {
        let missing = config.entries.filter {
            $0.kind == .source && !$0.rawValue.contains("$")
                && !fileManager.fileExists(atPath: Probes.expand($0.rawValue))
        }
        guard !missing.isEmpty else { return [] }
        return [Finding(
            id: "config.source.missing",
            tier: .warning,
            title: "\(missing.count) sourced file\(missing.count == 1 ? "" : "s") "
                 + "\(missing.count == 1 ? "is" : "are") missing",
            detail: "\(list(missing.map(\.rawValue))) \(missing.count == 1 ? "is" : "are") "
                  + "sourced at startup but not on disk. Unless the line guards for it, every "
                  + "new shell prints an error before the first prompt.",
            scope: "Terminal Config · Sourced files",
            toolIDs: missing.map(\.id))]
    }

    /// `zmodload zsh/zprof` left in place after a debugging session. It profiles every shell
    /// that opens, for nothing, unless a matching `zprof` call prints the report.
    private static func profilingLeftEnabled(_ config: ShellConfigSnapshot) -> [Finding] {
        guard let profiler = config.entries.first(where: {
            $0.kind == .option && $0.rawValue.contains("zsh/zprof")
        }) else { return [] }
        let reports = config.entries.contains { $0.name == "zprof" || $0.rawValue == "zprof" }
        guard !reports else { return [] }
        return [Finding(
            id: "config.zprof",
            tier: .warning,
            title: "Shell profiling is left enabled",
            detail: "`zmodload zsh/zprof` is loaded at \(profiler.lastOrigin?.location ?? "startup") "
                  + "with no matching `zprof` call to print the report. Every shell pays the "
                  + "profiling overhead and nothing ever reads the result — this is almost "
                  + "always a debugging line that was never removed.",
            scope: "Terminal Config · \(profiler.lastOrigin?.file ?? "Options")",
            toolIDs: [profiler.id])]
    }

    /// The init hooks that are known to dominate shell startup time.
    private static let slowHooks = ["pyenv init", "rbenv init", "nodenv init", "jenv init",
                                    "nvm.sh", "conda", "sdkman", "goenv init", "phpenv init",
                                    "direnv hook", "thefuck"]

    private static func slowInitHooks(_ config: ShellConfigSnapshot) -> [Finding] {
        let slow = config.entries.filter { entry in
            (entry.kind == .initHook || entry.kind == .source)
                && slowHooks.contains { entry.rawValue.localizedCaseInsensitiveContains($0) }
        }
        guard slow.count >= 2 else { return [] }
        return [Finding(
            id: "config.slow",
            tier: .info,
            title: "\(slow.count) startup hooks are known to be slow",
            detail: "\(list(slow.map(\.name))) each run on every new shell and together are "
                  + "usually most of the wait before the first prompt. Lazy-loading them, or "
                  + "replacing them with their faster `--path` variants, is the usual fix.",
            scope: "Terminal Config · Init hooks",
            toolIDs: slow.map(\.id))]
    }

    /// A variable pointing at a location that is not there. `JAVA_HOME` left behind after a
    /// JDK upgrade is the classic case, and it fails in a confusing way much later.
    private static func danglingLocations(_ config: ShellConfigSnapshot,
                                          tools: [DetectedTool],
                                          fileManager: FileManager) -> [Finding] {
        let dangling = config.entries.filter { entry in
            guard entry.kind == .environment, !entry.isSecret else { return false }
            let value = entry.rawValue
            guard value.hasPrefix("/") || value.hasPrefix("~"), !value.contains("$") else {
                return false
            }
            return !fileManager.fileExists(atPath: Probes.expand(value))
        }
        guard !dangling.isEmpty else { return [] }
        let names = dangling.map { "\($0.name) → \($0.rawValue)" }
        let related = tools.filter { tool in
            guard let path = tool.path else { return false }
            return dangling.contains { path.hasPrefix(Probes.expand($0.rawValue)) }
        }
        return [Finding(
            id: "config.dangling",
            tier: .warning,
            title: "\(dangling.count) variable\(dangling.count == 1 ? "" : "s") "
                 + "point\(dangling.count == 1 ? "s" : "") at a location that is gone",
            detail: "\(list(names)) — the path is set at startup but nothing is there. Tools "
                  + "that trust the variable rather than checking it will fail with an error "
                  + "that names something else entirely.",
            scope: "Terminal Config · Environment",
            toolIDs: dangling.map(\.id) + related.map(\.id))]
    }

    /// The same name given two different values in two files. Whichever runs last wins, and
    /// it is rarely the one the user was editing.
    private static func conflictingDeclarations(_ config: ShellConfigSnapshot) -> [Finding] {
        config.entries
            .filter { $0.kind == .environment && $0.hasConflictingOrigins }
            .map { entry in
                let where_ = entry.origins.map(\.location).joined(separator: ", ")
                return Finding(
                    id: "config.conflict.\(entry.name)",
                    tier: .warning,
                    title: "\(entry.name) is set to different values in two places",
                    detail: "Declared at \(where_). The last one to run wins, which is "
                          + "\(entry.lastOrigin?.file ?? "the later file") — editing the other "
                          + "has no effect.",
                    scope: "Terminal Config · Environment",
                    toolIDs: [entry.id])
            }
    }

    /// An alias that hides a real command of the same name.
    private static func aliasesShadowingExecutables(_ config: ShellConfigSnapshot) -> [Finding] {
        let shadowing = config.entries.filter {
            $0.kind == .alias && Probes.findExecutable([$0.name]) != nil
        }
        guard !shadowing.isEmpty else { return [] }
        return [Finding(
            id: "config.alias.shadow",
            tier: .info,
            title: "\(shadowing.count) alias\(shadowing.count == 1 ? "" : "es") "
                 + "hide\(shadowing.count == 1 ? "s" : "") a real command",
            detail: "\(list(shadowing.map(\.name))) each share a name with an executable on "
                  + "PATH. That is often deliberate, but it means a script or a colleague "
                  + "running the same command gets different behaviour to an interactive shell.",
            scope: "Terminal Config · Aliases",
            toolIDs: shadowing.map(\.id))]
    }

    /// Backup copies of config files sitting next to the live ones.
    private static func staleBackupFiles(_ config: ShellConfigSnapshot) -> [Finding] {
        guard !config.staleFiles.isEmpty else { return [] }
        return [Finding(
            id: "config.stale",
            tier: .info,
            title: "\(config.staleFiles.count) leftover shell config file"
                 + "\(config.staleFiles.count == 1 ? "" : "s") in the home directory",
            detail: "\(list(config.staleFiles)) look like backups. They never load, so anything "
                  + "changed in one of them has no effect — which is a confusing thing to "
                  + "rediscover months later.",
            scope: "Terminal Config · Files",
            toolIDs: [])]
    }

    /// A dotfile anyone can write is a way to run code as this user on every new shell.
    private static func worldWritableFiles(_ config: ShellConfigSnapshot) -> [Finding] {
        guard !config.writableFiles.isEmpty else { return [] }
        return [Finding(
            id: "config.permissions",
            tier: .warning,
            title: "\(config.writableFiles.count) startup file"
                 + "\(config.writableFiles.count == 1 ? " is" : "s are") writable by others",
            detail: "\(list(config.writableFiles)) can be modified by a group member or by any "
                  + "user on this Mac. Anything written into one of them runs as you the next "
                  + "time a terminal opens. `chmod go-w` on each restores the usual permissions.",
            scope: "Terminal Config · Files",
            toolIDs: [])]
    }

    // MARK: - Helpers

    /// "a, b and 3 more" — long enough to be actionable, short enough to read.
    private static func list(_ items: [String], limit: Int = 3) -> String {
        guard items.count > limit else {
            guard items.count > 1 else { return items.first ?? "" }
            return items.dropLast().joined(separator: ", ") + " and " + (items.last ?? "")
        }
        return items.prefix(limit).joined(separator: ", ")
             + " and \(items.count - limit) more"
    }
}
