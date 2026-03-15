// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MDToWord",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MDToWord", targets: ["MDToWord"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-markdown.git", from: "0.4.0"),
        .package(url: "https://github.com/PsychQuant/common-converter-swift.git", from: "0.4.0"),
        .package(url: "https://github.com/PsychQuant/ooxml-swift.git", from: "0.5.1"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
    ],
    targets: [
        .target(
            name: "MDToWord",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "CommonConverterSwift", package: "common-converter-swift"),
                .product(name: "OOXMLSwift", package: "ooxml-swift"),
                .product(name: "Yams", package: "Yams"),
            ]
        ),
        .testTarget(
            name: "MDToWordTests",
            dependencies: ["MDToWord"]
        ),
    ]
)
