import Foundation

/// What the search field matches against.
///
/// Pure and free of the model so the rules can be tested directly. The query is trimmed
/// once by the caller; an empty query matches everything.
enum SearchFilter {
    /// A tile matches on its own fields, or on any single entry inside it.
    ///
    /// Most of what a Mac has installed is not a catalog tile — it is one of the 150-odd
    /// formulae, casks or global npm packages nested inside a container tile. Without the
    /// child pass a search for `libomp` came back empty even though the Homebrew tile
    /// lists it.
    static func matches(_ tool: DetectedTool, query: String) -> Bool {
        guard !query.isEmpty else { return true }
        let haystack = [tool.name, tool.subtitle, tool.version ?? "",
                        tool.path ?? "", tool.managedBy]
        if haystack.contains(where: { $0.localizedStandardContains(query) }) { return true }
        return tool.children.contains { matches($0, query: query) }
    }

    /// A child matches on the name shown, the name its package manager uses, its version
    /// or its path. `token` matters because a cask row displays the application's name —
    /// typing the formula name it was installed under has to work too.
    static func matches(_ child: ToolChild, query: String) -> Bool {
        guard !query.isEmpty else { return true }
        return [child.name, child.token, child.version, child.path]
            .contains { $0.localizedStandardContains(query) }
    }
}
