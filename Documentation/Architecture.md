# RichTextView Architecture

RichTextView is a unified rich-text node-tree renderer for UIKit, backed by
CoreText. Its primary semantic contract is `RichContentDocument`: Markdown and
custom structured inputs can be normalized into that tree before rendering.
Markdown is one built-in input adapter, not the renderer's data model.
`RichTextView` also has convenience `String` and `NSAttributedString` paths.

## Products and source layout

The core product is `RichTextView`. The optional `RichTextViewMarkdown` SwiftPM
product adds the Markdown input adapter and depends on the core product.
CocoaPods exposes the same boundary through the default `Core` subspec and the
opt-in `Markdown` subspec.

Source code is grouped by responsibility:

```text
Sources
├── Core
│   ├── Model       Immutable unified node-tree values
│   └── Transform   Reconciliation and projection
├── Rendering
│   ├── Adapter     Semantic document to render-element bridge
│   ├── Builder     Element builders
│   ├── Element     Render input model
│   ├── Layout      CoreText layout and run boxes
│   ├── Render      Retained render tree and drawing layer
│   └── View        UIKit host, interaction, and selection
└── Markdown
    ├── Adapter     Parser and converter registry
    └── Converter   swift-markdown AST converters
```

## Data flow

```text
Application models ── custom adapter ──┐
Markdown ── RichMarkdownParser ────────┼── RichContentDocument
Other formats ── custom parser ───────┘
    ↓ RichContentRenderer
RichElementSnapshot
    ↓ RichTextLayoutEngine
RichTextLayout
    ↓ RichTextView
CALayer drawing + hosted attachment views
```

The renderer only consumes the unified node tree. Applications may construct it
directly or add adapters for any source format. Node types are open-ended:
applications define `RichContentNodeType(rawValue:)` values and register a
`RichContentElementBuilding` implementation with
`RichContentElementBuilderRegistry`. Built-in builders can also be replaced by
node type when a product needs different presentation.

## Core model

`RichContentDocument` is the semantic representation. Nodes carry IDs, typed
equatable content and children. Callers should keep an ID stable for the same
logical node across updates. The model has no UIKit dependency and is safe to
prepare away from the main thread.

`RichContentDocumentRevealProjector` creates a visible projection for
progressive rendering without mutating the source document. This is optional:
the Example typewriter instead appends to its source and reparses the current
prefix. The projector's `previousProjection` parameter does not currently
affect the result.

## Input adapters

An input adapter converts structured source data into `RichContentDocument`.
Application models, server schemas, and document formats can share the renderer
once they produce stable node IDs, typed equatable content and children. Direct
`String` and `NSAttributedString` assignment is a separate convenience path.

### Markdown

`RichMarkdownParser` is the built-in adapter from Markdown into the node tree.
It parses through a registry of small node converters. Callers can register
custom converters and provide an HTML resolver without changing the built-in
pipeline.

Each parser call parses the supplied source in full. The `previousDocument`
parameter is accepted but does not currently drive parsing or reuse. Markdown
node IDs are based on AST paths, so inserting a block before an existing block
can change the latter's ID.

The adapter's `Markdown` dependency is a statically linked XCFramework built
from the official `swift-markdown` tag plus the documented double-tilde
strikethrough patch. Applications that use only the core renderer do not link
that binary.

## Rendering and layout

`RichContentRenderer` resolves semantic values into rendering elements using an
injected configuration and builder registry. The immutable
`RichElementSnapshot` feeds `RichTextLayoutEngine`, which produces all text,
decoration, image, and attachment geometry before views are created.

Text is measured and drawn with CoreText. Stable element IDs, content equality,
builder inputs, and unchanged child elements allow render objects and cached
text layouts to be reused across updates.

Tables are built-in block attachments with a horizontal `UIScrollView`. Each
cell is rendered from its child elements by the same CoreText pipeline; column
widths are clamped, row heights expand to their richest cell, and the table
attachment keeps stable identity across streaming updates. Table colors,
padding, borders, column bounds, and row height are supplied by
`RichTableStyle`.

For streaming input through the lower-level API, callers retain a renderer and
layout engine per document stream. The renderer recursively builds children and
compares content, builder/resolver inputs, child elements, width, traits, and
configuration before reusing an element. Changes to those inputs can invalidate
reuse. Math measurement uses a bounded cache. The view guards asynchronous
layout results with a generation, and the drawing layer rejects obsolete
display work. When asynchronous drawing is enabled, it keeps the previous
bitmap while changed tiles are prepared. Message lifecycle, stream-part
merging, and typewriter pacing remain application concerns.

The Example typewriter parses each growing source prefix, passes `streaming`
to both parser and renderer, computes a layout with retained renderer/layout
engine instances, then calls `apply(snapshot, layout:)`. It does not use the
reveal projector or the view's `setContent` path for each character. The view
also offers `setContent` for a simpler document integration.

## Attachments and images

Attachments use `RichAttachmentViewProvider`. The renderer owns their geometry
and lifecycle, while the application creates and configures the UIKit views.

Remote image loading is abstracted by `RichImageLoader`. RichTextView does not
depend on a networking or image-cache library. Loaded pixels invalidate display
without changing the declared image geometry.

## Interaction and selection

`RichTextViewInteractionDelegate` receives element actions and selection
callbacks. Selection uses semantic positions and ranges to map a selection
across CoreText runs and rebase it after layout changes while element IDs and
intra-element offsets remain valid. Applications can customize selection menus
through `RichSelectionMenuPresenting`.

## Threading

Semantic conversion and layout are background-capable. UIKit view creation,
view hierarchy mutation, selection UI, and final layer-content assignment run
on the main thread. Asynchronous drawing is guarded by a monotonically changing
display token so obsolete work cannot replace newer content.

## Dependency boundaries

The library intentionally does not own application routing, analytics, theme,
networking, image caching, message models, or persistence. Those concerns enter
through semantic documents, rendering configuration, image loaders, attachment
providers, and interaction delegates.
