// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "token-counter-swift",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TokenCounter", targets: ["TokenCounter"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/DePasqualeOrg/swift-tiktoken.git",
            revision: "b4310ee520995ddff45b055de19e6605e0f8e5b6"
        ),
    ],
    targets: [
        .target(
            name: "TokenCounter",
            dependencies: [
                .product(name: "SwiftTiktoken", package: "swift-tiktoken"),
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "TokenCounterTests",
            dependencies: ["TokenCounter"]
        ),
    ]
)
