// swift-tools-version: 5.9
//
// docx-workflow-swift v0.1.0 — Layer 3 manifest-driven docx-edit library
// on top of word-builder-swift v1.0.0.
// See openspec/changes/macdoc-docx-workflow-cli/ for the design.

import PackageDescription

let package = Package(
    name: "DocxWorkflowLib",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "DocxWorkflowLib", targets: ["DocxWorkflowLib"])
    ],
    dependencies: [
        // Branch-track main per the word-builder-swift v1.0.0 policy:
        // always pull the latest Edit-algebra runtime + Phase 2c Reducer
        // cases. Deploy-via-download semantics preserved.
        .package(url: "https://github.com/PsychQuant/word-builder-swift.git", branch: "main"),
    ],
    targets: [
        .target(
            name: "DocxWorkflowLib",
            dependencies: [
                .product(name: "WordBuilderSwift", package: "word-builder-swift"),
            ]
        ),
        .testTarget(
            name: "DocxWorkflowLibTests",
            dependencies: ["DocxWorkflowLib"]
        ),
    ]
)
