// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HTMLToMDSwift",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "HTMLToMDSwift", targets: ["HTMLToMDSwift"]),
    ],
    dependencies: [
        .package(url: "https://github.com/PsychQuant/doc-converter-swift.git", from: "0.4.0"),
        .package(url: "https://github.com/PsychQuant/markdown-swift.git", from: "0.1.0"),
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.7.4"),
    ],
    targets: [
        .target(
            name: "HTMLToMDSwift",
            dependencies: [
                .product(name: "CommonConverterSwift", package: "doc-converter-swift"),
                .product(name: "MarkdownSwift", package: "markdown-swift"),
                .product(name: "SwiftSoup", package: "SwiftSoup"),
            ]
        ),
        .testTarget(
            name: "HTMLToMDSwiftTests",
            dependencies: [
                "HTMLToMDSwift",
                .product(name: "CommonConverterSwift", package: "doc-converter-swift"),
            ]
        ),
    ]
)
