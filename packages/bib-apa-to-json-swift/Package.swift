// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BibAPAToJSON",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BibAPAToJSON", targets: ["BibAPAToJSON"])
    ],
    dependencies: [
        .package(name: "BibAPAToHTML", path: "../bib-apa-to-html-swift"),
    ],
    targets: [
        .target(
            name: "BibAPAToJSON",
            dependencies: ["BibAPAToHTML"],
            path: "Sources/BibAPAToJSON"
        ),
        .testTarget(
            name: "BibAPAToJSONTests",
            dependencies: ["BibAPAToJSON"],
            path: "Tests/BibAPAToJSONTests"
        )
    ]
)
