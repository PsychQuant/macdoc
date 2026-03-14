// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HTMLToMDSwift",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "HTMLToMDSwift", targets: ["HTMLToMDSwift"]),
    ],
    dependencies: [
        .package(name: "CommonConverterSwift", path: "../common-converter-swift"),
        .package(url: "https://github.com/PsychQuant/markdown-swift.git", from: "0.1.0"),
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.7.4"),
    ],
    targets: [
        .target(
            name: "HTMLToMDSwift",
            dependencies: [
                .product(name: "CommonConverterSwift", package: "CommonConverterSwift"),
                .product(name: "MarkdownSwift", package: "markdown-swift"),
                .product(name: "SwiftSoup", package: "SwiftSoup"),
            ]
        ),
        .testTarget(
            name: "HTMLToMDSwiftTests",
            dependencies: [
                "HTMLToMDSwift",
                .product(name: "CommonConverterSwift", package: "CommonConverterSwift"),
            ]
        ),
    ]
)
