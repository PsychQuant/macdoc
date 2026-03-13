// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BiblatexAPA",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BiblatexAPA", targets: ["BiblatexAPA"])
    ],
    targets: [
        .target(
            name: "BiblatexAPA",
            path: "Sources/BiblatexAPA"
        ),
        .testTarget(
            name: "BiblatexAPATests",
            dependencies: ["BiblatexAPA"],
            path: "Tests/BiblatexAPATests"
        )
    ]
)
