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
        .binaryTarget(
            name: "TreeSitter",
            url: "https://github.com/FeliksLv01/RichTextViewTreeSitter/releases/download/tree-sitter-0.25.10.1/TreeSitter.xcframework.zip",
            checksum: "f2ba9ddb46cf03ea12d769f7299023f73f2e93f84631217e054736bbdc8d9300"
        ),
        .binaryTarget(
            name: "SwiftTreeSitter",
            url: "https://github.com/FeliksLv01/RichTextViewTreeSitter/releases/download/tree-sitter-0.25.10.1/SwiftTreeSitter.xcframework.zip",
            checksum: "89b8df51b14494290bf71de048d5a1da4a65e6736a264244d19075500383b9c6"
        ),
        .binaryTarget(
            name: "TreeSitterSwift",
            url: "https://github.com/FeliksLv01/RichTextViewTreeSitter/releases/download/tree-sitter-0.25.10.1/TreeSitterSwift.xcframework.zip",
            checksum: "f85c2df73fd8365a9d28063363d74630fa2495cd39afa591f5641438793c1260"
        ),
        .target(
            name: "RichTextView",
            dependencies: ["TreeSitter", "SwiftTreeSitter", "TreeSitterSwift"],
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
