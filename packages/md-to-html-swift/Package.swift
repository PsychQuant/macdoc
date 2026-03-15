// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MDToHTML",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "MDToHTML", targets: ["MDToHTML"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-markdown.git", from: "0.4.0"),
        .package(url: "https://github.com/PsychQuant/common-converter-swift.git", from: "0.4.0"),
    ],
    targets: [
        .target(
            name: "MDToHTML",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "CommonConverterSwift", package: "common-converter-swift"),
            ],
            path: "Sources/MDToHTML"
        ),
        .testTarget(
            name: "MDToHTMLTests",
            dependencies: [
                "MDToHTML",
                .product(name: "CommonConverterSwift", package: "common-converter-swift"),
            ],
            path: "Tests/MDToHTMLTests"
        ),
    ]
)
