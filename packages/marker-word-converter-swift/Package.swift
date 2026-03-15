// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MarkerWordConverter",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MarkerWordConverter", targets: ["MarkerWordConverter"]),
    ],
    dependencies: [
        .package(url: "https://github.com/PsychQuant/common-converter-swift.git", from: "0.4.0"),
        .package(url: "https://github.com/PsychQuant/ooxml-swift.git", from: "0.5.1"),
        .package(url: "https://github.com/PsychQuant/markdown-swift.git", from: "0.1.0"),
        .package(url: "https://github.com/PsychQuant/marker-swift.git", from: "0.1.0"),
    ],
    targets: [
        .target(
            name: "MarkerWordConverter",
            dependencies: [
                .product(name: "CommonConverterSwift", package: "common-converter-swift"),
                .product(name: "OOXMLSwift", package: "ooxml-swift"),
                .product(name: "MarkdownSwift", package: "markdown-swift"),
                .product(name: "MarkerSwift", package: "marker-swift"),
            ]
        ),
    ]
)
