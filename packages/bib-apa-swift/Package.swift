// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BibAPA",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BibAPA", targets: ["BibAPA"])
    ],
    dependencies: [
        .package(name: "BiblatexAPA", path: "../biblatex-apa-swift"),
    ],
    targets: [
        .target(
            name: "BibAPA",
            dependencies: ["BiblatexAPA"],
            path: "Sources/BibAPA"
        ),
        .testTarget(
            name: "BibAPATests",
            dependencies: ["BibAPA"],
            path: "Tests/BibAPATests"
        )
    ]
)
