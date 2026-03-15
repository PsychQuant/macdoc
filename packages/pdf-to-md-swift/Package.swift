// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PDFToMD",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PDFToMD", targets: ["PDFToMD"]),
        .executable(name: "pdf-to-md-smoke-tests", targets: ["PDFToMDSmokeTests"]),
    ],
    dependencies: [
        .package(url: "https://github.com/PsychQuant/common-converter-swift.git", from: "0.4.0"),
    ],
    targets: [
        .target(
            name: "PDFToMD",
            dependencies: [
                .product(name: "CommonConverterSwift", package: "common-converter-swift"),
            ],
            path: "Sources/PDFToMDSwift"
        ),
        .executableTarget(
            name: "PDFToMDSmokeTests",
            dependencies: [
                "PDFToMD",
                .product(name: "CommonConverterSwift", package: "common-converter-swift"),
            ],
            path: "Sources/PDFToMDSwiftSmokeTests"
        ),
        .testTarget(
            name: "PDFToMDTests",
            dependencies: [
                "PDFToMD",
                .product(name: "CommonConverterSwift", package: "common-converter-swift"),
            ],
            path: "Tests/PDFToMDTests"
        ),
    ]
)
