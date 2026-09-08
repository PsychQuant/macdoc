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
        // Version range, not `branch:` — the "v1.0.0 policy" this used to cite
        // was itself the defect (macdoc#184): a branch requirement freezes the
        // resolved revision and overrides the graph's version ranges, and
        // copying it here is how the anti-pattern propagated one level up.
        .package(url: "https://github.com/PsychQuant/word-builder-swift.git", from: "1.0.2"),
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
