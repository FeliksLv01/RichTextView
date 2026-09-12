# RichTextView

`RichTextView` is a unified rich-text node-tree renderer for UIKit, built on
CoreText. Applications describe content with an immutable
`RichContentDocument`, then use the same rendering pipeline for text, links,
mentions, images, attachments, lists, quotes, code, and custom node types.

Markdown is one built-in input adapter. It converts a Markdown AST into the
same node tree; it is not the renderer's underlying data model.

The library does not include application-specific message, routing, analytics,
theme, networking, or image-cache dependencies.

## Structure

```text
Sources
├── Core        Unified node-tree model and transforms
├── Rendering   Node builders, CoreText layout, drawing, views, and interaction
└── Markdown    Optional input path from swift-markdown AST to the node tree
```

## Swift Package Manager

Add this repository and link the `RichTextView` product. It contains the node
tree and renderer without linking the Markdown binary.

```swift
import RichTextView
```

To parse Markdown, also link and import the `RichTextViewMarkdown` product:

```swift
import RichTextView
import RichTextViewMarkdown
```

## CocoaPods

```ruby
pod 'RichTextView', '0.1.0'
```

Add the Markdown input adapter only when needed:

```ruby
pod 'RichTextView/Markdown', '0.1.0'
```

The adapter uses the static `Markdown.xcframework` published by
[`swift-markdown-xcframework`](https://github.com/FeliksLv01/swift-markdown-xcframework).

## Render a node tree

```swift
let document = RichContentDocument(
    root: RichContentNode(
        id: "article",
        type: .root,
        children: [
            RichContentNode(
                id: "paragraph-1",
                type: .paragraph,
                children: [
                    RichContentNode(
                        id: "text-1",
                        type: .text,
                        content: RichTextContent(text: "A unified rich-text tree")
                    )
                ]
            )
        ]
    )
)
let rendered = RichContentRenderer().render(
    document: document,
    constrainedWidth: 320,
    configuration: .standard
)

let view = RichTextView()
view.apply(rendered.snapshot)
```

For simple labels, `RichTextView` also accepts `String` and
`NSAttributedString` directly.

## Markdown input adapter

Markdown is normalized into the same node tree before rendering:

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

Enable native long-press selection and copy for any rendered input, including
Markdown normalized through `RichTextViewMarkdown`:

```swift
richTextView.isTextSelectionEnabled = true
```

## Example app

The [Example](Example) app uses the iOS 15 scene lifecycle and consumes this
repository as a local Swift package. Its table-based catalog opens a detail page
for each integration style: `String`, attributed image-text mixing, a complex
typed node tree, and selectable Markdown.
Generate and build its Xcode project with:

```bash
./Scripts/test-example.sh
```

`Example/RichTextViewExample.xcodeproj` is generated from
`Example/project.yml` by XcodeGen and is intentionally not committed.
