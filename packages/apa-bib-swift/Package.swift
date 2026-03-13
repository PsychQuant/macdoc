// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "APABib",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "APABib", targets: ["APABib"])
    ],
    dependencies: [
        .package(name: "BiblatexAPA", path: "../biblatex-apa-swift"),
    ],
    targets: [
        .target(
            name: "APABib",
            dependencies: ["BiblatexAPA"],
            path: "Sources/APABib"
        ),
        .testTarget(
            name: "APABibTests",
            dependencies: ["APABib"],
            path: "Tests/APABibTests"
        )
    ]
)
