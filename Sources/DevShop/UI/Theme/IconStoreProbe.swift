import Foundation

/// Whether a brand mark exists for a slug, without touching the main-actor icon cache.
/// Used by the diagnostics dump to report which icon source a package would get.
enum IconStoreProbe {
    private static let slugs: Set<String> = {
        guard let url = ResourceBundle.url(forResource: "icons", withExtension: "json"),
              let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let map = try? JSONDecoder().decode([String: String].self, from: data) else {
            return []
        }
        return Set(map.keys)
    }()

    static func has(_ slug: String) -> Bool { slugs.contains(slug) }
}
