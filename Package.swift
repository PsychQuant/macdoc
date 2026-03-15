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
        .package(url: "https://github.com/PsychQuant/common-converter-swift.git", from: "0.4.0"),
        .package(url: "https://github.com/PsychQuant/word-to-md-swift.git", from: "0.5.1"),
        .package(name: "MarkerWordConverter", path: "packages/marker-word-converter-swift"),
        .package(name: "pdf-to-latex-swift", path: "packages/pdf-to-latex-swift"),
        .package(name: "PDFToMD", path: "packages/pdf-to-md-swift"),
        .package(name: "HTMLToMD", path: "packages/html-to-md-swift"),
        .package(name: "MDToHTML", path: "packages/md-to-html-swift"),
        .package(name: "SRTToHTML", path: "packages/srt-to-html-swift"),
        .package(name: "BibAPAToHTML", path: "packages/bib-apa-to-html-swift"),
        .package(name: "BibAPAToJSON", path: "packages/bib-apa-to-json-swift"),
        .package(name: "BibAPAToMD", path: "packages/bib-apa-to-md-swift"),
    ],
    targets: [
        .executableTarget(
            name: "MacDocCLI",
            dependencies: [
                .product(name: "CommonConverterSwift", package: "common-converter-swift"),
                .product(name: "WordToMDSwift", package: "word-to-md-swift"),
                .product(name: "PDFToMD", package: "PDFToMD"),
                .product(name: "HTMLToMD", package: "HTMLToMD"),
                .product(name: "MDToHTML", package: "MDToHTML"),
                .product(name: "SRTToHTML", package: "SRTToHTML"),
                .product(name: "MarkerWordConverter", package: "MarkerWordConverter"),
                .product(name: "PDFToLaTeXCore", package: "pdf-to-latex-swift"),
                .product(name: "BibAPAToHTML", package: "BibAPAToHTML"),
                .product(name: "BibAPAToJSON", package: "BibAPAToJSON"),
                .product(name: "BibAPAToMD", package: "BibAPAToMD"),
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
