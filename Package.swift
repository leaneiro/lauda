// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "MarkEditor",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.5.0"),
    ],
    targets: [
        .executableTarget(
            name: "MarkEditor",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
            ],
            path: "Sources/MarkEditor"
        ),
        .testTarget(
            name: "MarkEditorTests",
            dependencies: ["MarkEditor"],
            path: "Tests/MarkEditorTests"
        ),
    ]
)
