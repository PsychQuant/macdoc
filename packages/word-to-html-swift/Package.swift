// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WordToHTMLSwift",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "WordToHTMLSwift", targets: ["WordToHTMLSwift"]),
    ],
    dependencies: [
        .package(url: "https://github.com/PsychQuant/doc-converter-swift.git", from: "0.3.0"),
        .package(url: "https://github.com/PsychQuant/ooxml-swift.git", from: "0.5.3"),
    ],
    targets: [
        .target(
            name: "WordToHTMLSwift",
            dependencies: [
                .product(name: "DocConverterSwift", package: "doc-converter-swift"),
                .product(name: "OOXMLSwift", package: "ooxml-swift"),
            ]
        ),
        .testTarget(
            name: "WordToHTMLSwiftTests",
            dependencies: ["WordToHTMLSwift"]
        ),
    ]
)
