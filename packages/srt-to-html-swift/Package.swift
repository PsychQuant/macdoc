// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SRTToHTMLSwift",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SRTToHTMLSwift", targets: ["SRTToHTMLSwift"]),
    ],
    dependencies: [
        .package(url: "https://github.com/PsychQuant/doc-converter-swift.git", from: "0.4.0"),
    ],
    targets: [
        .target(
            name: "SRTToHTMLSwift",
            dependencies: [
                .product(name: "CommonConverterSwift", package: "doc-converter-swift"),
            ]
        ),
        .testTarget(
            name: "SRTToHTMLSwiftTests",
            dependencies: [
                "SRTToHTMLSwift",
                .product(name: "CommonConverterSwift", package: "doc-converter-swift"),
            ]
        ),
    ]
)
