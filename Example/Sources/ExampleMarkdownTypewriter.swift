import RichTextView
import RichTextViewMarkdown
import UIKit

@MainActor
final class ExampleMarkdownTypewriter {
    struct Update {
        let document: RichContentDocument
        let visibleUnitCount: Int
        let totalUnitCount: Int
        let isComplete: Bool
    }

    private static let tickIntervalNanoseconds: UInt64 = 30_000_000
    private static let chunkIntervalInTicks = 35

    private let chunks = ExampleMarkdownTypewriter.markdownChunks
    private let parser = RichMarkdownParser(imageSize: CGSize(width: 28, height: 28))
    private let projector = RichContentDocumentRevealProjector(configuration: .init(
        entryUnitNodeTypes: [.table],
        unmeteredSubtreeNodeTypes: [.tableHead]
    ))
    private let onUpdate: (Update) -> Void
    private var task: Task<Void, Never>?
    private var receivedChunkCount = 0
    private var visibleUnitCount = 0
    private var tickCount = 0
    private var parsedDocument: RichContentDocument?
    private var projectedDocument: RichContentDocument?

    init(onUpdate: @escaping (Update) -> Void) {
        self.onUpdate = onUpdate
    }

    deinit {
        task?.cancel()
    }

    func start() {
        stop()
        receivedChunkCount = 0
        visibleUnitCount = 0
        tickCount = 0
        parsedDocument = nil
        projectedDocument = nil
        advance()
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.tickIntervalNanoseconds)
                guard !Task.isCancelled, let self else { return }
                self.advance()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func advance() {
        tickCount += 1
        if tickCount == 1 || tickCount.isMultiple(of: Self.chunkIntervalInTicks) {
            receiveNextChunk()
        }
        guard let parsedDocument else { return }
        let totalUnitCount = projector.unitCount(in: parsedDocument)
        visibleUnitCount = min(visibleUnitCount + 1, totalUnitCount)
        let projection = projector.project(
            parsedDocument,
            visibleUnitCount: visibleUnitCount,
            previousProjection: projectedDocument
        )
        visibleUnitCount = projection.visibleUnitCount
        projectedDocument = projection.document
        let isComplete = receivedChunkCount == chunks.count
            && projection.visibleUnitCount == projection.totalUnitCount
        onUpdate(Update(
            document: projection.document,
            visibleUnitCount: projection.visibleUnitCount,
            totalUnitCount: projection.totalUnitCount,
            isComplete: isComplete
        ))
        if isComplete {
            stop()
        }
    }

    private func receiveNextChunk() {
        guard receivedChunkCount < chunks.count else { return }
        receivedChunkCount += 1
        let receivedSource = chunks
            .prefix(receivedChunkCount)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined(separator: "\n\n")
        let result = parser.parse(
            receivedSource,
            documentID: "streaming-example",
            previousDocument: parsedDocument
        )
        parsedDocument = result.document
    }

    private static let markdownChunks = [
        """
        # Streaming answer

        RichTextView receives **partial Markdown**, reconciles stable nodes, and keeps the previous rendered frame visible while new layout work runs.

        """,
        """
        The same stream can contain `inline code`, [a tappable link](https://github.com/FeliksLv01/RichTextView), and an image ![GitHub](https://github.githubassets.com/images/modules/logos_page/GitHub-Mark.png) on one line.

        """,
        """
        > This quote grows one character at a time without replacing the whole view.

        """,
        """
        | Layer | Responsibility | Result |
        | :-- | :-- | --: |
        | Parser | Reconcile semantic nodes | Stable IDs |
        | Layout | Reuse unchanged runs | Less work |
        | Display | Preserve the previous bitmap | No flash |

        """,
        """
        ```swift
        let parsed = parser.parse(chunk, previousDocument: previous)
        richTextView.setContent(parsed.document)
        ```

        """,
        """
        The simulated server emits complete Markdown blocks. The typewriter reveals one semantic unit every 30 ms and continues until it catches up.
        """
    ]
}
