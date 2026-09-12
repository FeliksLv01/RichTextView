# RichTextView Architecture

RichTextView is a unified rich-text node-tree renderer for UIKit, backed by
CoreText. Its primary contract is `RichContentDocument`: every input format is
normalized into that tree before it reaches layout or drawing. Markdown is one
built-in input adapter, not the renderer's data model.

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
    ↓ RichLayoutEngine
RichLayout
    ↓ RichTextView
CALayer drawing + hosted attachment views
```

The renderer only consumes the unified node tree. Applications may construct it
directly or add adapters for any source format.

## Core model

`RichContentDocument` is the semantic representation. Nodes have stable IDs,
typed content, children, and revisions. The model has no UIKit dependency and is
safe to prepare away from the main thread.

`RichContentDocumentReconciler` preserves stable node identity between document
versions. `RichContentDocumentRevealProjector` creates a visible projection for
progressive rendering without mutating the source document.

## Input adapters

An input adapter converts source data into `RichContentDocument`. Application
models, server schemas, attributed strings, and document formats can all share
the renderer once they produce stable node IDs, typed content, children, and
revisions.

### Markdown

`RichMarkdownParser` is the built-in adapter from Markdown into the node tree.
It parses through a registry of small node converters. Callers can register
custom converters and provide an HTML resolver without changing the built-in
pipeline.

The adapter's `Markdown` dependency is a statically linked XCFramework built
from the official `swift-markdown` tag plus the documented double-tilde
strikethrough patch. Applications that use only the core renderer do not link
that binary.

## Rendering and layout

`RichContentRenderer` resolves semantic values into rendering elements using an
injected configuration and builder registry. The immutable
`RichElementSnapshot` feeds `RichLayoutEngine`, which produces all text,
decoration, image, and attachment geometry before views are created.

Text is measured and drawn with CoreText. Stable element IDs and separate
layout/display revisions allow unchanged render objects and cached text layouts
to be reused across updates.

## Attachments and images

Attachments use `RichAttachmentViewProvider`. The renderer owns their geometry
and lifecycle, while the application creates and configures the UIKit views.

Remote image loading is abstracted by `RichImageLoader`. RichTextView does not
depend on a networking or image-cache library. Loaded pixels invalidate display
without changing the declared image geometry.

## Interaction and selection

`RichTextViewInteractionDelegate` receives element actions. Selection uses
semantic positions and ranges so copy behavior remains stable across individual
CoreText runs. Applications can customize selection menus through
`RichSelectionMenuPresenting`.

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
