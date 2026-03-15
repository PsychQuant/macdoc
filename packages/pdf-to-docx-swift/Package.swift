// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PDFToDOCX",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PDFToDOCX", targets: ["PDFToDOCX"]),
    ],
    dependencies: [
        .package(url: "https://github.com/PsychQuant/common-converter-swift.git", from: "0.4.0"),
        .package(url: "https://github.com/PsychQuant/ooxml-swift.git", from: "0.5.3"),
    ],
    targets: [
        .target(
            name: "PDFToDOCX",
            dependencies: [
                .product(name: "CommonConverterSwift", package: "common-converter-swift"),
                .product(name: "OOXMLSwift", package: "ooxml-swift"),
            ]
        ),
        .testTarget(
            name: "PDFToDOCXTests",
            dependencies: [
                "PDFToDOCX",
                .product(name: "OOXMLSwift", package: "ooxml-swift"),
            ]
        ),
    ]
)
