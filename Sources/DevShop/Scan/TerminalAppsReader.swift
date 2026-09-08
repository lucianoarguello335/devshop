import Foundation

/// Finds the terminal emulators installed on this Mac.
///
/// Driven by a table of bundle identifiers rather than by scanning every app for something
/// terminal-shaped: the identifier is stable, and it is what lets the reader know where a
/// given terminal keeps its settings.
enum TerminalAppsReader {

    /// One terminal DevShop knows how to look for.
    private struct Known {
        var bundleIdentifier: String
        var name: String
        /// App bundle names to look for, in order of preference.
        var bundleNames: [String]
        /// Where it keeps its own configuration. `~` paths, only reported when they exist.
        var configPaths: [String]
        var website: String?
        var colorHex: String
        var iconSlug: String?
    }

    /// Directories searched, in precedence order. A user-installed copy wins over a cask
    /// staging directory holding the same app.
    private static let searchRoots = ["/Applications",
                                      "~/Applications",
                                      "/System/Applications/Utilities",
                                      "/Applications/Utilities"]

    private static let known: [Known] = [
        Known(bundleIdentifier: "com.apple.Terminal", name: "Terminal",
              bundleNames: ["Terminal.app"],
              configPaths: ["~/Library/Preferences/com.apple.Terminal.plist"],
              website: "https://support.apple.com/guide/terminal",
              colorHex: "1d1d1f", iconSlug: nil),
        Known(bundleIdentifier: "com.googlecode.iterm2", name: "iTerm2",
              bundleNames: ["iTerm.app", "iTerm2.app"],
              configPaths: ["~/Library/Preferences/com.googlecode.iterm2.plist",
                            "~/Library/Application Support/iTerm2"],
              website: "https://iterm2.com",
              colorHex: "3c8f3c", iconSlug: "iterm2"),
        Known(bundleIdentifier: "dev.warp.Warp-Stable", name: "Warp",
              bundleNames: ["Warp.app"],
              configPaths: ["~/.warp", "~/Library/Application Support/dev.warp.Warp-Stable"],
              website: "https://www.warp.dev",
              colorHex: "01a0f0", iconSlug: "warp"),
        Known(bundleIdentifier: "com.mitchellh.ghostty", name: "Ghostty",
              bundleNames: ["Ghostty.app"],
              configPaths: ["~/.config/ghostty/config"],
              website: "https://ghostty.org",
              colorHex: "3b2a4a", iconSlug: nil),
        Known(bundleIdentifier: "net.kovidgoyal.kitty", name: "kitty",
              bundleNames: ["kitty.app"],
              configPaths: ["~/.config/kitty/kitty.conf"],
              website: "https://sw.kovidgoyal.net/kitty",
              colorHex: "88b053", iconSlug: nil),
        Known(bundleIdentifier: "io.alacritty", name: "Alacritty",
              bundleNames: ["Alacritty.app"],
              configPaths: ["~/.config/alacritty/alacritty.toml",
                            "~/.config/alacritty/alacritty.yml"],
              website: "https://alacritty.org",
              colorHex: "f46d01", iconSlug: "alacritty"),
        Known(bundleIdentifier: "com.github.wez.wezterm", name: "WezTerm",
              bundleNames: ["WezTerm.app"],
              configPaths: ["~/.wezterm.lua", "~/.config/wezterm/wezterm.lua"],
              website: "https://wezterm.org",
              colorHex: "4e49ee", iconSlug: nil),
        Known(bundleIdentifier: "co.zeit.hyper", name: "Hyper",
              bundleNames: ["Hyper.app"],
              configPaths: ["~/.hyper.js"],
              website: "https://hyper.is",
              colorHex: "000000", iconSlug: "hyper"),
        Known(bundleIdentifier: "terminus.tabby", name: "Tabby",
              bundleNames: ["Tabby.app"],
              configPaths: ["~/Library/Application Support/tabby/config.yaml"],
              website: "https://tabby.sh",
              colorHex: "6c5ce7", iconSlug: nil),
        Known(bundleIdentifier: "com.raphamorim.rio", name: "Rio",
              bundleNames: ["Rio.app"],
              configPaths: ["~/.config/rio/config.toml"],
              website: "https://rioterm.com",
              colorHex: "f4425c", iconSlug: nil),
        Known(bundleIdentifier: "tech.typesafe.sheru", name: "Sheru",
              bundleNames: ["Sheru.app"],
              configPaths: [],
              website: nil,
              colorHex: "5e5ce6", iconSlug: nil),
        Known(bundleIdentifier: "com.apple.dt.Xcode", name: "Xcode Console",
              bundleNames: [],
              configPaths: [],
              website: nil,
              colorHex: "0a84ff", iconSlug: nil)
    ]

    static func scan(fileManager: FileManager = .default) -> [TerminalApp] {
        known.compactMap { entry -> TerminalApp? in
            guard !entry.bundleNames.isEmpty,
                  let path = locate(entry, fileManager: fileManager) else { return nil }
            return TerminalApp(id: entry.bundleIdentifier,
                               name: entry.name,
                               version: Probes.appVersion(at: path),
                               build: Probes.appBuild(at: path),
                               path: path,
                               configPaths: entry.configPaths.filter(Probes.exists),
                               website: entry.website,
                               colorHex: entry.colorHex,
                               iconSlug: entry.iconSlug)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func locate(_ entry: Known, fileManager: FileManager) -> String? {
        for root in searchRoots {
            for name in entry.bundleNames {
                let candidate = Probes.expand(root) + "/" + name
                if fileManager.fileExists(atPath: candidate) { return candidate }
            }
        }
        // A cask stages the real bundle even when nothing has been linked into
        // /Applications yet, so it is worth one more look before giving up.
        for name in entry.bundleNames {
            let token = String(name.dropLast(4)).lowercased()
            let caskroom = "/opt/homebrew/Caskroom/\(token)"
            for version in Probes.subdirectories(of: caskroom) {
                let candidate = "\(caskroom)/\(version)/\(name)"
                if fileManager.fileExists(atPath: candidate) { return candidate }
            }
        }
        return nil
    }
}
