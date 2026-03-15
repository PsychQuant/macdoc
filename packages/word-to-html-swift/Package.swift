// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WordToHTML",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "WordToHTML", targets: ["WordToHTML"]),
    ],
    dependencies: [
        .package(url: "https://github.com/PsychQuant/common-converter-swift.git", from: "0.4.0"),
        .package(url: "https://github.com/PsychQuant/ooxml-swift.git", from: "0.5.3"),
    ],
    targets: [
        .target(
            name: "WordToHTML",
            dependencies: [
                .product(name: "CommonConverterSwift", package: "common-converter-swift"),
                .product(name: "OOXMLSwift", package: "ooxml-swift"),
            ],
            path: "Sources/WordToHTMLSwift"
        ),
        .testTarget(
            name: "WordToHTMLTests",
            dependencies: ["WordToHTML"],
            path: "Tests/WordToHTMLTests"
        ),
    ]
)
