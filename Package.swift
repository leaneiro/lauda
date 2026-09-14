// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Lauda",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.5.0"),
    ],
    targets: [
        .executableTarget(
            name: "Lauda",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
            ],
            path: "Sources/Lauda",
            resources: [
                .copy("Preview/preview.css"),
                .copy("Preview/preview.js"),
                .copy("Preview/LaudaWordmark.woff"),
                .copy("Preview/Newsreader-OFL.txt"),
            ]
        ),
        .testTarget(
            name: "LaudaTests",
            dependencies: ["Lauda"],
            path: "Tests/LaudaTests"
        ),
    ]
)
