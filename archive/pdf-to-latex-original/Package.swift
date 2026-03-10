// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "pdf-to-latex",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "pdf-to-latex", targets: ["pdf-to-latex"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        .executableTarget(
            name: "pdf-to-latex",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
    ]
)
