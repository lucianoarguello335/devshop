import Foundation

/// The list of things DevShop knows how to look for, loaded once from the bundled JSON.
enum Catalog {
    static let all: [ToolDefinition] = load()

    private static func load() -> [ToolDefinition] {
        guard let url = ResourceBundle.url(forResource: "catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            assertionFailure("catalog.json is missing from the bundle")
            return []
        }
        do {
            return try JSONDecoder().decode([ToolDefinition].self, from: data)
        } catch {
            assertionFailure("catalog.json failed to decode: \(error)")
            return []
        }
    }
}
