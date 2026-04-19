// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BibAPAToMD",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BibAPAToMD", targets: ["BibAPAToMD"])
    ],
    dependencies: [
        .package(name: "BibAPA", path: "../bib-apa-swift"),
    ],
    targets: [
        .target(
            name: "BibAPAToMD",
            dependencies: ["BibAPA"],
            path: "Sources/BibAPAToMD"
        ),
        .testTarget(
            name: "BibAPAToMDTests",
            dependencies: ["BibAPAToMD"],
            path: "Tests/BibAPAToMDTests"
        )
    ]
)
