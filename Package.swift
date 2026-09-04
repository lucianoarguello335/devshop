// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DevShop",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "DevShop",
            path: "Sources/DevShop",
            resources: [
                .copy("Catalog/catalog.json"),
                .copy("UI/Theme/icons.json")
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "DevShopTests",
            dependencies: ["DevShop"],
            path: "Tests/DevShopTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
