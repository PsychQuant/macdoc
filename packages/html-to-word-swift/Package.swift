// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HTMLToWordSwift",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "HTMLToWordSwift", targets: ["HTMLToWordSwift"]),
    ],
    dependencies: [
        .package(url: "https://github.com/PsychQuant/doc-converter-swift.git", from: "0.3.0"),
        .package(url: "https://github.com/PsychQuant/ooxml-swift.git", from: "0.5.3"),
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.7.4"),
    ],
    targets: [
        .target(
            name: "HTMLToWordSwift",
            dependencies: [
                .product(name: "DocConverterSwift", package: "doc-converter-swift"),
                .product(name: "OOXMLSwift", package: "ooxml-swift"),
                .product(name: "SwiftSoup", package: "SwiftSoup"),
            ]
        ),
        .testTarget(
            name: "HTMLToWordSwiftTests",
            dependencies: [
                "HTMLToWordSwift",
                .product(name: "OOXMLSwift", package: "ooxml-swift"),
            ]
        ),
    ]
)
