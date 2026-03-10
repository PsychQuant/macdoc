// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "macdoc",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "macdoc", targets: ["MacDocCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        .package(url: "https://github.com/PsychQuant/doc-converter-swift.git", from: "0.1.0"),
        .package(url: "https://github.com/PsychQuant/word-to-md-swift.git", from: "0.1.0"),
        .package(url: "https://github.com/PsychQuant/ooxml-swift.git", from: "0.5.0"),
        .package(url: "https://github.com/PsychQuant/markdown-swift.git", from: "0.1.0"),
        .package(url: "https://github.com/PsychQuant/marker-swift.git", from: "0.1.0"),
        .package(name: "pdf-to-latex-swift", path: "packages/pdf-to-latex-swift"),
    ],
    targets: [
        .target(
            name: "MarkerWordConverter",
            dependencies: [
                .product(name: "DocConverterSwift", package: "doc-converter-swift"),
                .product(name: "OOXMLSwift", package: "ooxml-swift"),
                .product(name: "MarkdownSwift", package: "markdown-swift"),
                .product(name: "MarkerSwift", package: "marker-swift"),
            ]
        ),
        .executableTarget(
            name: "MacDocCLI",
            dependencies: [
                .product(name: "DocConverterSwift", package: "doc-converter-swift"),
                .product(name: "WordToMDSwift", package: "word-to-md-swift"),
                "MarkerWordConverter",
                .product(name: "PDFToLaTeXCore", package: "pdf-to-latex-swift"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "WordToMDTests",
            dependencies: [
                .product(name: "WordToMDSwift", package: "word-to-md-swift"),
            ],
            resources: [.copy("Fixtures")]
        ),
    ]
)
