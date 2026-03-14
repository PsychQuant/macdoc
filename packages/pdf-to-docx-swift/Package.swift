// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PDFToDOCXSwift",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PDFToDOCXSwift", targets: ["PDFToDOCXSwift"]),
    ],
    dependencies: [
        .package(url: "https://github.com/PsychQuant/doc-converter-swift.git", from: "0.4.0"),
        .package(url: "https://github.com/PsychQuant/ooxml-swift.git", from: "0.5.3"),
    ],
    targets: [
        .target(
            name: "PDFToDOCXSwift",
            dependencies: [
                .product(name: "CommonConverterSwift", package: "doc-converter-swift"),
                .product(name: "OOXMLSwift", package: "ooxml-swift"),
            ]
        ),
        .testTarget(
            name: "PDFToDOCXSwiftTests",
            dependencies: [
                "PDFToDOCXSwift",
                .product(name: "OOXMLSwift", package: "ooxml-swift"),
            ]
        ),
    ]
)
