// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MDToHTMLSwift",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "MDToHTMLSwift", targets: ["MDToHTMLSwift"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-markdown.git", from: "0.4.0"),
        .package(url: "https://github.com/PsychQuant/doc-converter-swift.git", from: "0.4.0"),
    ],
    targets: [
        .target(
            name: "MDToHTMLSwift",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "CommonConverterSwift", package: "doc-converter-swift"),
            ]
        ),
        .testTarget(
            name: "MDToHTMLSwiftTests",
            dependencies: [
                "MDToHTMLSwift",
                .product(name: "CommonConverterSwift", package: "doc-converter-swift"),
            ]
        ),
    ]
)
