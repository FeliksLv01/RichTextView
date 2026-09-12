// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "RichTextView",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "RichTextView", targets: ["RichTextView"]),
        .library(name: "RichTextViewMarkdown", targets: ["RichTextViewMarkdown"])
    ],
    targets: [
        .binaryTarget(
            name: "Markdown",
            url: "https://github.com/FeliksLv01/swift-markdown-xcframework/releases/download/swift-markdown-0.8.0-patch.1/Markdown.xcframework.zip",
            checksum: "9eda1d78bad380856aa966d68e4cae89a461c619e3e0e2266cb2effc4b77d736"
        ),
        .target(
            name: "RichTextView",
            path: "Sources",
            exclude: ["Markdown"]
        ),
        .target(
            name: "RichTextViewMarkdown",
            dependencies: ["RichTextView", "Markdown"],
            path: "Sources/Markdown"
        ),
        .testTarget(
            name: "RichTextViewTests",
            dependencies: ["RichTextView", "RichTextViewMarkdown"],
            path: "Tests/RichTextViewTests"
        )
    ]
)
