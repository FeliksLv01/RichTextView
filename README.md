# RichTextView

`RichTextView` is a UIKit rich-text rendering library built on CoreText. It
provides immutable content nodes, reusable layout results, attachment views,
interaction and selection, plus direct Markdown-to-render-tree conversion.

The library does not include application-specific message, routing, analytics,
theme, networking, or image-cache dependencies.

## Structure

```text
Sources
├── Core        Semantic document model and transforms
├── Markdown    swift-markdown AST conversion
└── Rendering   Elements, CoreText layout, drawing, views, and document bridge
```

## Swift Package Manager

Add this repository and link the `RichTextView` product.

```swift
import RichTextView
```

## CocoaPods

```ruby
pod 'RichTextView', '0.1.0'
```

The Markdown parser uses the static `Markdown.xcframework` published by
[`swift-markdown-xcframework`](https://github.com/FeliksLv01/swift-markdown-xcframework).

## Basic usage

```swift
let view = RichTextView()
view.text = "Plain text works without constructing a document."
```

Render Markdown through the semantic document pipeline:

```swift
let parsed = RichMarkdownParser().parse(markdown, documentID: "article")
let rendered = RichContentRenderer().render(
    document: parsed.document,
    constrainedWidth: 320,
    configuration: .standard
)

let view = RichTextView()
view.apply(rendered.snapshot)
```

See [Architecture](Documentation/Architecture.md) for extension points,
threading, attachments, images, interaction, and selection.
