import Foundation

/// One entry inside a container tile — a formula in the Cellar, a cask in the Caskroom, a
/// global npm package, an installed VS Code extension.
///
/// Children are read from the same directory listings that produced their parent, so
/// enumerating them costs nothing beyond the listing itself. Their sizes are measured with
/// everything else on Refresh.
struct ToolChild: Sendable, Identifiable, Equatable {
    /// Namespaced under the parent so measurements cannot collide: `brew.casks/chatgpt`.
    var id: String
    /// The name as the package manager knows it, e.g. `visual-studio-code`.
    var token: String
    /// What to show — a cask's real application name where one could be read.
    var name: String
    var version: String
    var path: String
    /// The installed `.app`, when this child is one. Its own icon is the best available.
    var appBundlePath: String?
    /// Simple Icons slug, when the token matched a bundled brand mark.
    var iconSlug: String?
    /// Tint for the monogram fallback.
    var color: String

    /// Two-letter monogram used when there is neither an app icon nor a brand mark.
    var monogram: String {
        let letters = name.filter { $0.isLetter || $0.isNumber }
        return String(letters.prefix(2)).capitalized
    }
}
