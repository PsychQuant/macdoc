// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "macdoc",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "macdoc", targets: ["MacDocCLI"]),
        .library(name: "MacDocCore", targets: ["MacDocCore"]),
        .library(name: "WordToMD", targets: ["WordToMD"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        // Local path dependencies during development
        .package(path: "packages/ooxml-swift"),
        .package(path: "packages/markdown-swift"),
        .package(path: "packages/marker-swift"),
    ],
    targets: [
        .target(
            name: "MacDocCore"
        ),
        .target(
            name: "WordToMD",
            dependencies: [
                "MacDocCore",
                .product(name: "OOXMLSwift", package: "ooxml-swift"),
                .product(name: "MarkdownSwift", package: "markdown-swift"),
                .product(name: "MarkerSwift", package: "marker-swift"),
            ]
        ),
        .executableTarget(
            name: "MacDocCLI",
            dependencies: [
                "MacDocCore",
                "WordToMD",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "MacDocCoreTests",
            dependencies: ["MacDocCore"]
        ),
        .testTarget(
            name: "WordToMDTests",
            dependencies: ["WordToMD"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
