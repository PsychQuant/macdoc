// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HTMLToMD",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "HTMLToMD", targets: ["HTMLToMD"]),
    ],
    dependencies: [
        .package(url: "https://github.com/PsychQuant/common-converter-swift.git", from: "0.4.0"),
        .package(url: "https://github.com/PsychQuant/markdown-swift.git", from: "0.1.0"),
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.7.4"),
    ],
    targets: [
        .target(
            name: "HTMLToMD",
            dependencies: [
                .product(name: "CommonConverterSwift", package: "common-converter-swift"),
                .product(name: "MarkdownSwift", package: "markdown-swift"),
                .product(name: "SwiftSoup", package: "SwiftSoup"),
            ],
            path: "Sources/HTMLToMD"
        ),
        .testTarget(
            name: "HTMLToMDTests",
            dependencies: [
                "HTMLToMD",
                .product(name: "CommonConverterSwift", package: "common-converter-swift"),
            ],
            path: "Tests/HTMLToMDTests"
        ),
    ]
)
