// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HTMLToMDSwift",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "HTMLToMDSwift", targets: ["HTMLToMDSwift"]),
    ],
    dependencies: [
        .package(url: "https://github.com/PsychQuant/doc-converter-swift.git", from: "0.3.0"),
        .package(url: "https://github.com/PsychQuant/markdown-swift.git", from: "0.1.0"),
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.7.4"),
    ],
    targets: [
        .target(
            name: "HTMLToMDSwift",
            dependencies: [
                .product(name: "DocConverterSwift", package: "doc-converter-swift"),
                .product(name: "MarkdownSwift", package: "markdown-swift"),
                .product(name: "SwiftSoup", package: "SwiftSoup"),
            ]
        ),
        .executableTarget(
            name: "HTMLToMDSwiftSelfTest",
            dependencies: [
                "HTMLToMDSwift",
                .product(name: "DocConverterSwift", package: "doc-converter-swift"),
            ],
            path: "Tests/HTMLToMDSwiftSelfTest"
        ),
    ]
)
