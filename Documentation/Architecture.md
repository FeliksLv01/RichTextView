# RichTextView Architecture

RichTextView is a UIKit rich-text rendering library backed by CoreText. It keeps
the semantic document, Markdown conversion, layout, drawing, and hosted UIKit
views separate so applications can replace content-specific behavior without
forking the renderer.

## Modules

The package exposes one Swift module so CocoaPods and Swift Package Manager have
the same import and API surface. Source code is grouped by responsibility:

```text
Sources
├── Core
│   ├── Model       Immutable semantic document values
│   └── Transform   Reconciliation and projection
├── Markdown
│   ├── Adapter     Parser and converter registry
│   └── Converter   swift-markdown AST converters
└── Rendering
    ├── Adapter     Semantic document to render-element bridge
    ├── Builder     Element builders
    ├── Element     Render input model
    ├── Layout      CoreText layout and run boxes
    ├── Render      Retained render tree and drawing layer
    └── View        UIKit host, interaction, and selection
```

## Data flow

```text
Markdown source
    ↓ RichMarkdownParser
RichContentDocument
    ↓ RichContentRenderer
RichElementSnapshot
    ↓ RichLayoutEngine
RichLayout
    ↓ RichTextView
CALayer drawing + hosted attachment views
```

Applications may bypass Markdown and construct `RichContentDocument` or
`RichElementSnapshot` directly.

## Core model

`RichContentDocument` is the semantic representation. Nodes have stable IDs,
typed content, children, and revisions. The model has no UIKit dependency and is
safe to prepare away from the main thread.

`RichContentDocumentReconciler` preserves stable node identity between document
versions. `RichContentDocumentRevealProjector` creates a visible projection for
progressive rendering without mutating the source document.

## Markdown conversion

`RichMarkdownParser` parses Markdown into the semantic document through a
registry of small node converters. Callers can register custom converters and
provide an HTML resolver without changing the built-in pipeline.

The `Markdown` binary dependency is a statically linked XCFramework built from
the official `swift-markdown` tag plus the documented double-tilde
strikethrough patch.

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
