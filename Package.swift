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
        .package(url: "https://github.com/kiki830621/ooxml-swift.git", from: "0.1.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "MacDocCore"
        ),
        .target(
            name: "WordToMD",
            dependencies: [
                "MacDocCore",
                .product(name: "OOXMLSwift", package: "ooxml-swift")
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
