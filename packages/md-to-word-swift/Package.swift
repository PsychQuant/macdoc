// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MDToWordSwift",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MDToWordSwift", targets: ["MDToWordSwift"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-markdown.git", from: "0.4.0"),
        .package(url: "https://github.com/PsychQuant/doc-converter-swift.git", from: "0.3.0"),
        .package(url: "https://github.com/PsychQuant/ooxml-swift.git", from: "0.5.1"),
    ],
    targets: [
        .target(
            name: "MDToWordSwift",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "DocConverterSwift", package: "doc-converter-swift"),
                .product(name: "OOXMLSwift", package: "ooxml-swift"),
            ]
        ),
        .testTarget(
            name: "MDToWordSwiftTests",
            dependencies: ["MDToWordSwift"]
        ),
    ]
)
