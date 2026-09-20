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
            url: "https://github.com/FeliksLv01/RichTextViewBinaries/releases/download/swift-markdown-0.8.0-patch.1/Markdown.xcframework.zip",
            checksum: "9eda1d78bad380856aa966d68e4cae89a461c619e3e0e2266cb2effc4b77d736"
        ),
        .binaryTarget(
            name: "TreeSitter",
            url: "https://github.com/FeliksLv01/RichTextViewBinaries/releases/download/tree-sitter-0.25.10.2/TreeSitter.xcframework.zip",
            checksum: "5fac4aff46f9f37a9a6b84f013a0f10f1262a10707a61c08d3a847197cb44fbf"
        ),
        .binaryTarget(
            name: "SwiftTreeSitter",
            url: "https://github.com/FeliksLv01/RichTextViewBinaries/releases/download/tree-sitter-0.25.10.2/SwiftTreeSitter.xcframework.zip",
            checksum: "9654d1151b6f6da90186bfd1ceab146f0b1e779294226602da1741d2a7750653"
        ),
        .binaryTarget(
            name: "TreeSitterSwift",
            url: "https://github.com/FeliksLv01/RichTextViewBinaries/releases/download/tree-sitter-0.25.10.2/TreeSitterSwift.xcframework.zip",
            checksum: "5f49f40984a4258c10ffd24eb401cee5bd18ee048ce63a3b2e1a94d8b20fffe8"
        ),
        .binaryTarget(
            name: "iosMath",
            url: "https://github.com/FeliksLv01/RichTextViewBinaries/releases/download/iosMath-2.5.0.1/iosMath.xcframework.zip",
            checksum: "71b31789af1911f47e820d0c00367bf98837ce462217a93c5a07b7ecaa49a260"
        ),
        .target(
            name: "RichTextView",
            dependencies: [
                "TreeSitter",
                "SwiftTreeSitter",
                "TreeSitterSwift",
                "iosMath"
            ],
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
