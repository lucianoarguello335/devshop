import Foundation

/// Reads the zsh startup chain as text and reports every unique thing it does.
///
/// Nothing here spawns a process, exactly like `Probes`. That is a deliberate limit rather
/// than an oversight: running the user's dotfiles to find out what they do would execute
/// arbitrary code inside a read-only inspector. The cost is that what a framework defines
/// behind `source $ZSH/oh-my-zsh.sh`, or what an `eval` prints, cannot be resolved — those
/// are reported as the hook or the source that produces them, which is the thing a user can
/// actually act on anyway.
enum ShellConfigReader {

    // MARK: - Entry points

    /// Walks the chain in load order, follows `source` one level, and dedupes.
    static func read(home: String = Probes.home,
                     environment: [String: String] = ProcessInfo.processInfo.environment,
                     shell: String = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh",
                     terminals: [TerminalApp] = [],
                     fileManager: FileManager = .default) -> ShellConfigSnapshot {
        let zdotdir = environment["ZDOTDIR"].map { Probes.expand($0) } ?? home

        var merged: [ConfigEntry] = []
        var filesRead: [ConfigOrigin] = []
        var seenFiles: Set<String> = []

        func ingest(path: String, stage: LoadStage, isPathList: Bool = false) {
            let full = Probes.expand(path)
            guard !seenFiles.contains(full),
                  let text = try? String(contentsOfFile: full, encoding: .utf8) else { return }
            seenFiles.insert(full)
            let short = abbreviate(full, home: home)
            var parsed = isPathList
                ? parsePathList(text, file: short, stage: stage, home: home)
                : parse(text, file: short, stage: stage, home: home)
            // A sourced file's own internals are its business. What matters is what it puts
            // into the environment — without this, one theme file's 270 `typeset -g`
            // settings bury everything the user actually wrote.
            if stage == .sourced {
                parsed = parsed.filter { contributedBySourcedFiles.contains($0.kind) }
            }
            merge(parsed, into: &merged)
            filesRead.append(ConfigOrigin(file: short,
                                          line: text.components(separatedBy: .newlines).count,
                                          stage: stage,
                                          text: full))
        }

        ingest(path: "/etc/zshenv", stage: .systemEnv)
        ingest(path: zdotdir + "/.zshenv", stage: .userEnv)

        // path_helper folds these into PATH before any user rc file runs, so they belong in
        // the chain even though no shell file mentions them.
        ingest(path: "/etc/paths", stage: .pathHelper, isPathList: true)
        for name in (try? fileManager.contentsOfDirectory(atPath: "/etc/paths.d"))?.sorted() ?? [] {
            guard !name.hasPrefix(".") else { continue }
            ingest(path: "/etc/paths.d/" + name, stage: .pathHelper, isPathList: true)
        }

        ingest(path: "/etc/zprofile", stage: .systemProfile)
        ingest(path: zdotdir + "/.zprofile", stage: .userProfile)
        ingest(path: "/etc/zshrc", stage: .systemRC)
        ingest(path: zdotdir + "/.zshrc", stage: .userRC)
        ingest(path: zdotdir + "/.zlogin", stage: .login)

        // One level of `source`, and one level only. Following it all the way would pull in
        // the three hundred files oh-my-zsh loads and bury everything the user wrote.
        let sourced = merged.filter { $0.kind == .source }.map(\.rawValue)
        for target in sourced {
            let full = expandHome(target, home: home)
            guard !full.contains("$"), fileManager.fileExists(atPath: full) else { continue }
            ingest(path: full, stage: .sourced)
        }

        merged.sort {
            $0.kind == $1.kind
                ? $0.name.localizedStandardCompare($1.name) == .orderedAscending
                : order($0.kind) < order($1.kind)
        }

        return ShellConfigSnapshot(
            shell: shell,
            entries: merged,
            filesRead: filesRead,
            terminals: terminals,
            staleFiles: staleFiles(home: home, fileManager: fileManager),
            writableFiles: writableFiles(filesRead.map(\.text), home: home, fileManager: fileManager))
    }

    /// Kinds a sourced file is allowed to contribute. See the filter in `read`.
    private static let contributedBySourcedFiles: Set<ConfigEntryKind> =
        [.path, .environment, .initHook, .alias, .source]

    private static func order(_ kind: ConfigEntryKind) -> Int {
        ConfigEntryKind.allCases.firstIndex(of: kind) ?? 0
    }

    // MARK: - Parsing

    /// Turns one file's text into entries. Pure — no filesystem, no environment. Every test
    /// drives this.
    static func parse(_ text: String,
                      file: String,
                      stage: LoadStage,
                      home: String = Probes.home) -> [ConfigEntry] {
        var out: [ConfigEntry] = []
        let lines = text.components(separatedBy: .newlines)
        var index = 0
        var braceDepth = 0

        while index < lines.count {
            let lineNumber = index + 1
            var raw = lines[index]
            // A trailing backslash continues the statement, and the continuation is part of
            // the same directive — joining them is what makes a wrapped `export` readable.
            while raw.hasSuffix("\\"), index + 1 < lines.count {
                raw = String(raw.dropLast()) + " "
                    + lines[index + 1].trimmingCharacters(in: .whitespaces)
                index += 1
            }
            index += 1

            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }

            // Inside a function body nothing is a startup directive: it only runs when the
            // function is called.
            if braceDepth > 0 {
                braceDepth += braceDelta(line)
                continue
            }

            let statement = stripComment(line)
            guard !statement.isEmpty else { continue }

            if let name = functionName(in: statement) {
                braceDepth += braceDelta(statement)
                out.append(entry(kind: .function,
                                 name: name,
                                 value: "\(name)()",
                                 origin: ConfigOrigin(file: file, line: lineNumber,
                                                      stage: stage, text: line)))
                continue
            }

            let origin = ConfigOrigin(file: file, line: lineNumber, stage: stage, text: line)

            // `plugins=(\n git\n docker\n)` is one declaration spread over several lines.
            // Without consuming it, its contents are read as directives of their own.
            if let assigned = assignment(in: statement),
               assigned.value.hasPrefix("("), !assigned.value.contains(")") {
                var contents = [String(assigned.value.dropFirst())]
                while index < lines.count {
                    let next = lines[index]
                    index += 1
                    if let close = next.firstIndex(of: ")") {
                        contents.append(String(next[next.startIndex..<close]))
                        break
                    }
                    contents.append(next)
                }
                let joined = contents
                    .map { stripComment($0).trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                out += assignmentEntries((assigned.name, "(\(joined))"),
                                         origin: origin, home: home)
                continue
            }

            out += directives(in: statement, origin: origin, home: home)
        }
        return out
    }

    /// `/etc/paths` and the files in `/etc/paths.d` are plain lists of directories, one per
    /// line, with no shell syntax at all.
    static func parsePathList(_ text: String,
                              file: String,
                              stage: LoadStage,
                              home: String = Probes.home) -> [ConfigEntry] {
        text.components(separatedBy: .newlines).enumerated().compactMap { index, raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { return nil }
            return pathEntry(line,
                             origin: ConfigOrigin(file: file, line: index + 1,
                                                  stage: stage, text: line),
                             home: home)
        }
    }

    /// Everything one statement declares. A statement usually declares one thing; a `PATH`
    /// assignment declares one per directory in it.
    private static func directives(in statement: String,
                                   origin: ConfigOrigin,
                                   home: String) -> [ConfigEntry] {
        if let alias = aliasDeclaration(in: statement) {
            return [entry(kind: .alias, name: alias.name, value: alias.value, origin: origin)]
        }
        if let assigned = assignment(in: statement) {
            return assignmentEntries(assigned, origin: origin, home: home)
        }
        if let hook = evalHook(in: statement) {
            return [entry(kind: .initHook, name: hook.name, value: hook.value, origin: origin)]
        }
        if let sourced = sourcedFile(in: statement) {
            // Named by its full path rather than its basename: two different `nvm.sh` files
            // in the chain are two different things, and merging them by name would hide one.
            let target = abbreviate(expandHome(sourced, home: home), home: home)
            return [entry(kind: .source, name: target, value: target, origin: origin)]
        }
        if let option = optionDeclaration(in: statement) {
            return [entry(kind: .option, name: option.name, value: option.value, origin: origin)]
        }
        return []
    }

    private static func assignmentEntries(_ assigned: (name: String, value: String),
                                          origin: ConfigOrigin,
                                          home: String) -> [ConfigEntry] {
        let name = assigned.name
        let value = assigned.value

        if pathVariables.contains(name) {
            // `PATH="$HOME/bin:$PATH"` is one statement declaring one new directory. The
            // `$PATH` token is the old value being carried forward, not an entry.
            return value.split(separator: ":", omittingEmptySubsequences: true)
                .map(String.init)
                .filter { !isPathCarryOver($0) }
                .compactMap { pathEntry($0, origin: origin, home: home) }
        }
        if frameworkVariables.contains(name) {
            return [entry(kind: .framework, name: name, value: value, origin: origin)]
        }
        if name.hasPrefix("POWERLEVEL9K_") || name.hasPrefix("ZSH_") || name.contains("{") {
            return [entry(kind: .option, name: name, value: value, origin: origin)]
        }
        return [entry(kind: .environment, name: name, value: value, origin: origin)]
    }

    private static func pathEntry(_ token: String,
                                  origin: ConfigOrigin,
                                  home: String) -> ConfigEntry? {
        let trimmed = unquote(token.trimmingCharacters(in: .whitespaces))
        guard !trimmed.isEmpty, !isPathCarryOver(trimmed) else { return nil }
        let expanded = abbreviate(expandHome(trimmed, home: home), home: home)
        return entry(kind: .path, name: expanded, value: expanded, origin: origin)
    }

    private static func isPathCarryOver(_ token: String) -> Bool {
        let bare = unquote(token.trimmingCharacters(in: .whitespaces))
        return ["$PATH", "${PATH}", "$path", "${path}", "$MANPATH", "${MANPATH}",
                "$FPATH", "${FPATH}"].contains(bare)
    }

    // MARK: - Statement recognisers

    private static let pathVariables: Set<String> = ["PATH", "path", "MANPATH", "FPATH", "fpath"]
    private static let frameworkVariables: Set<String> =
        ["ZSH", "ZSH_THEME", "ZSH_CUSTOM", "plugins", "ZSH_THEME_RANDOM_CANDIDATES"]
    private static let assignmentKeywords = ["export ", "typeset -gx ", "typeset -g ",
                                             "typeset -x ", "typeset ", "declare -x ",
                                             "declare ", "local ", "readonly "]
    private static let optionKeywords = ["setopt", "unsetopt", "zstyle", "zmodload",
                                         "autoload", "bindkey", "umask", "ulimit",
                                         "compinit", "zle", "limit", "zprof"]

    /// `NAME=value`, with or without a declaring keyword.
    static func assignment(in statement: String) -> (name: String, value: String)? {
        var rest = statement
        var hadKeyword = false
        var changed = true
        while changed {
            changed = false
            for keyword in assignmentKeywords where rest.hasPrefix(keyword) {
                rest = String(rest.dropFirst(keyword.count)).trimmingCharacters(in: .whitespaces)
                hadKeyword = true
                changed = true
                break
            }
        }
        guard let equals = rest.firstIndex(of: "=") else { return nil }
        let name = String(rest[rest.startIndex..<equals]).trimmingCharacters(in: .whitespaces)
        let value = String(rest[rest.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        // A keyword vouches for the statement, so a name that is not a plain identifier —
        // `POWERLEVEL9K_PROMPT_CHAR_{OK,ERROR}_...` — is still an assignment. Without one,
        // only a real identifier counts, which is what keeps `[[ -f x ]] || source y` out.
        guard hadKeyword ? !name.contains(" ") : isIdentifier(name) else { return nil }
        return (name, unquote(value))
    }

    static func aliasDeclaration(in statement: String) -> (name: String, value: String)? {
        guard statement.hasPrefix("alias ") else { return nil }
        var rest = String(statement.dropFirst("alias ".count)).trimmingCharacters(in: .whitespaces)
        // `alias -g`, `alias -s`
        while rest.hasPrefix("-") {
            guard let space = rest.firstIndex(of: " ") else { return nil }
            rest = String(rest[rest.index(after: space)...]).trimmingCharacters(in: .whitespaces)
        }
        guard let equals = rest.firstIndex(of: "=") else { return nil }
        let name = String(rest[rest.startIndex..<equals]).trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !name.contains(" ") else { return nil }
        let value = String(rest[rest.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
        return (name, unquote(value))
    }

    /// `eval "$(brew shellenv)"` — the hook is named by the command it runs, because that is
    /// what a user recognises and searches for.
    static func evalHook(in statement: String) -> (name: String, value: String)? {
        guard let evalRange = statement.range(of: "eval ") ?? statement.range(of: "eval\t")
        else { return nil }
        let tail = String(statement[evalRange.upperBound...]).trimmingCharacters(in: .whitespaces)
        let inner = commandSubstitution(in: tail) ?? unquote(tail)
        guard !inner.isEmpty else { return nil }
        // `/opt/homebrew/bin/brew shellenv` reads better as `brew shellenv`.
        var words = inner.split(separator: " ").map(String.init)
        if let first = words.first {
            words[0] = URL(fileURLWithPath: first).lastPathComponent
        }
        return (words.prefix(3).joined(separator: " "), inner)
    }

    /// `source x`, `. x`, and the conditional forms — `[ -s "x" ] && \. "x"`.
    static func sourcedFile(in statement: String) -> String? {
        let markers = ["source ", "\\. ", ". ", "&& . ", "|| . "]
        for marker in markers {
            let range: Range<String.Index>?
            if statement.hasPrefix(marker) {
                range = statement.startIndex..<statement.index(statement.startIndex,
                                                               offsetBy: marker.count)
            } else {
                range = statement.range(of: " " + marker) ?? statement.range(of: marker)
                    .flatMap { statement.hasPrefix(marker) ? $0 : nil }
            }
            guard let range else { continue }
            let tail = String(statement[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            let target = unquote(tail.split(separator: " ").first.map(String.init) ?? "")
            guard !target.isEmpty, target != "&&", target != "||" else { continue }
            return target
        }
        return nil
    }

    static func optionDeclaration(in statement: String) -> (name: String, value: String)? {
        guard let keyword = optionKeywords.first(where: {
            statement == $0 || statement.hasPrefix($0 + " ")
        }) else { return nil }
        let rest = String(statement.dropFirst(keyword.count)).trimmingCharacters(in: .whitespaces)
        let name = rest.isEmpty ? keyword : "\(keyword) \(rest.split(separator: " ").first ?? "")"
        return (name, rest.isEmpty ? keyword : rest)
    }

    /// `name() {`, `name () {` or `function name`.
    static func functionName(in statement: String) -> String? {
        if statement.hasPrefix("function ") {
            let rest = String(statement.dropFirst("function ".count))
                .trimmingCharacters(in: .whitespaces)
            let name = rest.prefix { $0 != " " && $0 != "(" && $0 != "{" }
            return name.isEmpty ? nil : String(name)
        }
        guard let paren = statement.range(of: "()"), statement.contains("{") else { return nil }
        let head = String(statement[statement.startIndex..<paren.lowerBound])
            .trimmingCharacters(in: .whitespaces)
        guard !head.isEmpty, isIdentifier(head) else { return nil }
        return head
    }

    // MARK: - Text helpers

    private static func isIdentifier(_ text: String) -> Bool {
        guard let first = text.first, first.isLetter || first == "_" else { return false }
        return text.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    /// Drops a trailing `#` comment, ignoring one that sits inside quotes.
    static func stripComment(_ line: String) -> String {
        var single = false, double = false
        for (offset, character) in line.enumerated() {
            switch character {
            case "'" where !double: single.toggle()
            case "\"" where !single: double.toggle()
            case "#" where !single && !double:
                // `foo#bar` is not a comment; a comment starts a word.
                let index = line.index(line.startIndex, offsetBy: offset)
                let before = offset == 0 ? " " : line[line.index(before: index)]
                if before == " " || before == "\t" || offset == 0 {
                    return String(line[line.startIndex..<index])
                        .trimmingCharacters(in: .whitespaces)
                }
            default: break
            }
        }
        return line.trimmingCharacters(in: .whitespaces)
    }

    static func unquote(_ value: String) -> String {
        var text = value.trimmingCharacters(in: .whitespaces)
        while text.count >= 2,
              let first = text.first, let last = text.last,
              first == last, first == "\"" || first == "'" {
            text = String(text.dropFirst().dropLast())
        }
        return text
    }

    /// Contents of `$(...)` or backticks, if the text is a command substitution.
    private static func commandSubstitution(in text: String) -> String? {
        if let open = text.range(of: "$(") {
            var depth = 1
            var index = open.upperBound
            while index < text.endIndex {
                if text[index] == "(" { depth += 1 }
                if text[index] == ")" {
                    depth -= 1
                    if depth == 0 {
                        return String(text[open.upperBound..<index])
                            .trimmingCharacters(in: .whitespaces)
                    }
                }
                index = text.index(after: index)
            }
        }
        if let open = text.firstIndex(of: "`"),
           let close = text.lastIndex(of: "`"), open < close {
            return String(text[text.index(after: open)..<close])
                .trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private static func braceDelta(_ line: String) -> Int {
        line.reduce(0) { $0 + ($1 == "{" ? 1 : ($1 == "}" ? -1 : 0)) }
    }

    private static func expandHome(_ path: String, home: String) -> String {
        for token in ["$HOME", "${HOME}"] where path.hasPrefix(token) {
            return home + String(path.dropFirst(token.count))
        }
        return path.hasPrefix("~") ? home + String(path.dropFirst()) : path
    }

    /// `Probes.abbreviate` against an injectable home, so tests can use a scratch directory.
    static func abbreviate(_ path: String, home: String) -> String {
        path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    // MARK: - Entry construction

    private static func entry(kind: ConfigEntryKind,
                              name: String,
                              value: String,
                              origin: ConfigOrigin) -> ConfigEntry {
        let secret = kind == .environment && isSecret(name: name, value: value)
        return ConfigEntry(id: "\(kind.rawValue).\(name)",
                           kind: kind,
                           name: name,
                           displayValue: secret ? mask(value) : value,
                           rawValue: value,
                           isSecret: secret,
                           origins: [origin],
                           summary: summary(kind: kind, name: name, value: value, secret: secret))
    }

    /// Collapses repeat declarations into one entry carrying every origin. The last
    /// declaration wins at runtime, so its value is the one shown.
    static func merge(_ parsed: [ConfigEntry], into merged: inout [ConfigEntry]) {
        for new in parsed {
            guard let index = merged.firstIndex(where: { $0.id == new.id }) else {
                merged.append(new)
                continue
            }
            merged[index].origins += new.origins
            merged[index].displayValue = new.displayValue
            merged[index].rawValue = new.rawValue
            merged[index].isSecret = merged[index].isSecret || new.isSecret
            merged[index].summary = new.summary
        }
    }

    private static func summary(kind: ConfigEntryKind,
                                name: String,
                                value: String,
                                secret: Bool) -> String {
        switch kind {
        case .path: "Added to PATH"
        case .environment: secret ? "Secret value, hidden" : value
        case .initHook: "Runs `\(value)` at every prompt start"
        case .source: "Sourced from \(value)"
        case .framework: value
        case .alias: value
        case .function: "Defined for the session"
        case .option: value
        }
    }

    // MARK: - Secrets

    private static let secretNameMarkers = ["SECRET", "PASSWORD", "PASSWD", "TOKEN",
                                            "CREDENTIAL", "API_KEY", "APIKEY", "ACCESS_KEY",
                                            "PRIVATE_KEY", "AUTH"]

    static func isSecret(name: String, value: String) -> Bool {
        guard !value.isEmpty else { return false }
        // A path or a command substitution is a location, not the secret itself — flagging
        // `SSH_KEY_PATH=~/.ssh/id_ed25519` would be noise, and masking it would hide the
        // only useful part.
        let looksLikeLocation = value.hasPrefix("/") || value.hasPrefix("~")
            || value.hasPrefix("$") || value.hasPrefix(".") || value.contains("$(")
        if looksLikeLocation { return false }

        let upper = name.uppercased()
        if secretNameMarkers.contains(where: { upper.contains($0) }) { return true }
        if upper.hasSuffix("_KEY") || upper == "KEY" { return true }
        return looksLikeSecretValue(value)
    }

    /// Recognises the shapes that are unambiguously credentials wherever they appear.
    static func looksLikeSecretValue(_ value: String) -> Bool {
        let prefixes = ["sk-", "sk_live_", "sk_test_", "pk_live_", "ghp_", "gho_", "ghu_",
                        "ghs_", "github_pat_", "AIza", "xoxb-", "xoxp-", "xoxa-", "AKIA",
                        "ASIA", "glpat-", "npm_", "dop_v1_", "shpat_"]
        if prefixes.contains(where: { value.hasPrefix($0) }), value.count >= 20 { return true }
        // A long unbroken token of key-alphabet characters is a credential far more often
        // than it is anything else worth putting in a dotfile.
        guard value.count >= 32, !value.contains(" "), !value.contains("/") else { return false }
        let alphabet = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        guard value.unicodeScalars.allSatisfy({ alphabet.contains($0) }) else { return false }
        return value.contains(where: \.isNumber) && value.contains(where: \.isLetter)
    }

    /// Keeps enough of the ends to recognise which key it is, and none of the middle.
    static func mask(_ value: String) -> String {
        guard value.count > 12 else { return String(repeating: "\u{2022}", count: 8) }
        let head = value.prefix(4)
        let tail = value.suffix(4)
        return "\(head)\(String(repeating: "\u{2022}", count: 10))\(tail)"
    }

    // MARK: - Files around the chain

    private static let backupMarkers = [".bak", ".old", ".orig", ".save", ".pysave",
                                        ".backup", " copy", ".pre-", "~"]
    private static let configStems = [".zshrc", ".zprofile", ".zshenv", ".zlogin",
                                      ".bash_profile", ".bashrc", ".profile", ".p10k.zsh"]

    /// Leftover copies of config files. They never load, so anything a user "fixed" in one
    /// of these had no effect — which is exactly the confusion worth surfacing.
    static func staleFiles(home: String, fileManager: FileManager = .default) -> [String] {
        let names = (try? fileManager.contentsOfDirectory(atPath: home)) ?? []
        return names
            .filter { name in
                guard let stem = configStems.first(where: { name.hasPrefix($0) }),
                      name != stem else { return false }
                let suffix = String(name.dropFirst(stem.count))
                return backupMarkers.contains { suffix.contains($0) }
            }
            .sorted()
            .map { "~/" + $0 }
    }

    /// Files anyone but the owner can write. A writable dotfile is a way onto the machine.
    static func writableFiles(_ paths: [String],
                              home: String,
                              fileManager: FileManager = .default) -> [String] {
        paths.compactMap { path in
            guard let attributes = try? fileManager.attributesOfItem(atPath: path),
                  let permissions = attributes[.posixPermissions] as? NSNumber else { return nil }
            return permissions.int16Value & 0o022 != 0 ? abbreviate(path, home: home) : nil
        }
    }
}
