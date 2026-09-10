import Foundation

/// Locates the SwiftPM resource bundle that carries `catalog.json` and `icons.json`.
///
/// This exists because `Bundle.module` cannot be used from a shipped app. The accessor SwiftPM
/// generates for it has exactly two candidates:
///
///   1. `Bundle.main.bundleURL/DevShop_DevShop.bundle` — inside DevShop.app that is the bundle
///      root, and `codesign` refuses to seal anything there ("unsealed contents present in the
///      bundle root"), so the resources cannot be shipped at that path.
///   2. An absolute path into the `.build` directory of the machine that compiled the binary.
///
/// On the build machine candidate 2 resolves and everything works. On any other Mac both fail
/// and the accessor calls `fatalError` from inside a lazy static, which crashed the app a few
/// seconds after launch — see `Scripts/make-app.sh` for where the bundle is actually placed.
///
/// This looks in the standard locations instead, and returns nil rather than trapping, so a
/// missing resource degrades to an empty catalog that the caller can report.
enum ResourceBundle {
    static let shared: Bundle? = resolve()

    static func url(forResource name: String, withExtension ext: String) -> URL? {
        shared?.url(forResource: name, withExtension: ext)
    }

    private static let name = "DevShop_DevShop.bundle"

    private static func resolve() -> Bundle? {
        let token = Bundle(for: BundleToken.self)
        let roots: [URL] = [
            // DevShop.app/Contents/Resources — where Scripts/make-app.sh puts it.
            Bundle.main.resourceURL,
            // Alongside a bare `swift build` executable.
            Bundle.main.bundleURL,
            token.resourceURL,
            token.bundleURL,
            // `swift test`: the bundle sits next to the .xctest bundle, not inside it.
            token.bundleURL.deletingLastPathComponent()
        ].compactMap { $0 }

        for root in roots {
            if let bundle = Bundle(url: root.appendingPathComponent(name)) { return bundle }
        }
        return nil
    }
}

/// `Bundle(for:)` needs a class defined in this module to locate the module's own bundle.
private final class BundleToken {}
