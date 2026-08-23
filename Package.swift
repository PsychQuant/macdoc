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
        .package(url: "https://github.com/PsychQuant/word-to-md-swift.git", from: "1.0.0"),
        .package(name: "MarkerWordConverter", path: "packages/marker-word-converter-swift"),
        .package(url: "https://github.com/PsychQuant/pdf-to-latex-swift.git", from: "0.1.0"),
        .package(name: "PDFToMD", path: "packages/pdf-to-md-swift"),
        .package(name: "WordToHTML", path: "packages/word-to-html-swift"),
        .package(name: "HTMLToWord", path: "packages/html-to-word-swift"),
        .package(name: "MDToWord", path: "packages/md-to-word-swift"),
        .package(name: "PDFToDOCX", path: "packages/pdf-to-docx-swift"),
        .package(name: "HTMLToMD", path: "packages/html-to-md-swift"),
        .package(name: "MDToHTML", path: "packages/md-to-html-swift"),
        .package(name: "SRTToHTML", path: "packages/srt-to-html-swift"),
        .package(name: "BibAPAToHTML", path: "packages/bib-apa-to-html-swift"),
        .package(name: "BibAPAToJSON", path: "packages/bib-apa-to-json-swift"),
        .package(name: "BibAPAToMD", path: "packages/bib-apa-to-md-swift"),
        .package(name: "TeXToDOCX", path: "packages/tex-to-docx-swift"),
        .package(name: "DocxWorkflowLib", path: "packages/docx-workflow-swift"),
        .package(url: "https://github.com/PsychQuant/note-to-html-swift.git", from: "0.1.1"),
        .package(url: "https://github.com/PsychQuant/note-to-pdf-swift.git", from: "0.1.3"),
        // NoteCore is transitively pulled via note-to-html-swift/note-to-pdf-swift,
        // but declaring it here lets MacDocCLITests `import NoteCore` to verify
        // synthetic .note generation against the parser (per #100 Plan).
        .package(url: "https://github.com/PsychQuant/note-core-swift.git", from: "0.1.0"),
        // word-builder-swift v1.0.0 is the lens-model API; MacDocCLI does not
        // consume it yet (deferred per word-builder-swift-lens-migration
        // design.md "Out of scope"). Re-add when a CLI target imports
        // WordBuilderSwift.
        .package(url: "https://github.com/PsychQuant/ocr-swift.git", from: "0.1.0"),
        // Direct dependency for `macdoc word reverse` (script transcoder:
        // ScriptExporter / SidecarStore / DocxReader live in OOXMLSwift).
        .package(url: "https://github.com/PsychQuant/ooxml-swift.git", from: "3.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "MacDocCLI",
            dependencies: [
                .product(name: "CommonConverterSwift", package: "common-converter-swift"),
                .product(name: "OOXMLSwift", package: "ooxml-swift"),
                .product(name: "WordToMD", package: "word-to-md-swift"),
                .product(name: "PDFToMD", package: "PDFToMD"),
                .product(name: "WordToHTML", package: "WordToHTML"),
                .product(name: "HTMLToWord", package: "HTMLToWord"),
                .product(name: "MDToWord", package: "MDToWord"),
                .product(name: "PDFToDOCX", package: "PDFToDOCX"),
                .product(name: "HTMLToMD", package: "HTMLToMD"),
                .product(name: "MDToHTML", package: "MDToHTML"),
                .product(name: "SRTToHTML", package: "SRTToHTML"),
                .product(name: "MarkerWordConverter", package: "MarkerWordConverter"),
                .product(name: "PDFToLaTeXCore", package: "pdf-to-latex-swift"),
                .product(name: "BibAPAToHTML", package: "BibAPAToHTML"),
                .product(name: "BibAPAToJSON", package: "BibAPAToJSON"),
                .product(name: "BibAPAToMD", package: "BibAPAToMD"),
                .product(name: "TeXToDOCX", package: "TeXToDOCX"),
                .product(name: "DocxWorkflowLib", package: "DocxWorkflowLib"),
                .product(name: "NoteToHTML", package: "note-to-html-swift"),
                .product(name: "NoteToPDF", package: "note-to-pdf-swift"),
                .product(name: "OCRCore", package: "ocr-swift"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "MacDocCLITests",
            dependencies: [
                .product(name: "NoteCore", package: "note-core-swift"),
                // Authoring API for building synthetic docx fixtures in tests
                // (WordReverseCoverageTests → emptyAuthoringDocument).
                .product(name: "OOXMLSwift", package: "ooxml-swift"),
            ]
        ),
    ]
)
