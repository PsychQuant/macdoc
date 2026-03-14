// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SRTToHTMLSwift",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SRTToHTMLSwift", targets: ["SRTToHTMLSwift"]),
    ],
    dependencies: [
        .package(name: "CommonConverterSwift", path: "../common-converter-swift"),
    ],
    targets: [
        .target(
            name: "SRTToHTMLSwift",
            dependencies: [
                .product(name: "CommonConverterSwift", package: "CommonConverterSwift"),
            ]
        ),
        .testTarget(
            name: "SRTToHTMLSwiftTests",
            dependencies: [
                "SRTToHTMLSwift",
                .product(name: "CommonConverterSwift", package: "CommonConverterSwift"),
            ]
        ),
    ]
)
