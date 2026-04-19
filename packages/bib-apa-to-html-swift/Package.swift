// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BibAPAToHTML",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BibAPAToHTML", targets: ["BibAPAToHTML"])
    ],
    dependencies: [
        .package(name: "BibAPA", path: "../bib-apa-swift"),
    ],
    targets: [
        .target(
            name: "BibAPAToHTML",
            dependencies: ["BibAPA"],
            path: "Sources/BibAPAToHTML"
        ),
        .testTarget(
            name: "BibAPAToHTMLTests",
            dependencies: ["BibAPAToHTML"],
            path: "Tests/BibAPAToHTMLTests"
        )
    ]
)
