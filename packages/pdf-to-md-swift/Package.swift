// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PDFToMDSwift",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PDFToMDSwift", targets: ["PDFToMDSwift"]),
        .executable(name: "pdf-to-md-smoke-tests", targets: ["PDFToMDSwiftSmokeTests"]),
    ],
    dependencies: [
        .package(url: "https://github.com/PsychQuant/doc-converter-swift.git", from: "0.3.0"),
    ],
    targets: [
        .target(
            name: "PDFToMDSwift",
            dependencies: [
                .product(name: "DocConverterSwift", package: "doc-converter-swift"),
            ]
        ),
        .executableTarget(
            name: "PDFToMDSwiftSmokeTests",
            dependencies: [
                "PDFToMDSwift",
                .product(name: "DocConverterSwift", package: "doc-converter-swift"),
            ]
        ),
        .testTarget(
            name: "PDFToMDSwiftTests",
            dependencies: [
                "PDFToMDSwift",
                .product(name: "DocConverterSwift", package: "doc-converter-swift"),
            ]
        ),
    ]
)
