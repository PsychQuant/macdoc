// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SRTToHTML",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SRTToHTML", targets: ["SRTToHTML"]),
    ],
    dependencies: [
        .package(url: "https://github.com/PsychQuant/common-converter-swift.git", from: "0.4.0"),
    ],
    targets: [
        .target(
            name: "SRTToHTML",
            dependencies: [
                .product(name: "CommonConverterSwift", package: "common-converter-swift"),
            ],
            path: "Sources/SRTToHTML"
        ),
        .testTarget(
            name: "SRTToHTMLTests",
            dependencies: [
                "SRTToHTML",
                .product(name: "CommonConverterSwift", package: "common-converter-swift"),
            ],
            path: "Tests/SRTToHTMLTests"
        ),
    ]
)
