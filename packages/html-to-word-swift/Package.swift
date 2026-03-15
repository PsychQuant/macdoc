// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HTMLToWord",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "HTMLToWord", targets: ["HTMLToWord"]),
    ],
    dependencies: [
        .package(url: "https://github.com/PsychQuant/common-converter-swift.git", from: "0.4.0"),
        .package(url: "https://github.com/PsychQuant/ooxml-swift.git", from: "0.5.3"),
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.7.4"),
    ],
    targets: [
        .target(
            name: "HTMLToWord",
            dependencies: [
                .product(name: "CommonConverterSwift", package: "common-converter-swift"),
                .product(name: "OOXMLSwift", package: "ooxml-swift"),
                .product(name: "SwiftSoup", package: "SwiftSoup"),
            ]
        ),
        .testTarget(
            name: "HTMLToWordTests",
            dependencies: [
                "HTMLToWord",
                .product(name: "OOXMLSwift", package: "ooxml-swift"),
            ]
        ),
    ]
)
