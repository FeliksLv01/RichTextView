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

    private let source: [Character]
    private let parser = RichMarkdownParser(imageSize: CGSize(width: 28, height: 28))
    private let onUpdate: (Update) -> Void
    private var task: Task<Void, Never>?

    init(source: String? = nil, onUpdate: @escaping (Update) -> Void) {
        self.source = Array(source ?? Self.markdownChunks.joined(separator: "\n\n"))
        self.onUpdate = onUpdate
    }

    deinit { task?.cancel() }

    func start() {
        stop()
        task = Task { [weak self] in
            guard let count = self?.source.count else { return }
            var text = ""
            for index in 0..<count {
                do { try await Task.sleep(nanoseconds: 20_000_000) } catch { return }
                guard let self else { return }
                text.append(self.source[index])
                let complete = index + 1 == count
                let document = self.parser.parse(text, documentID: "streaming-example", streaming: !complete).document
                self.onUpdate(Update(document: document, visibleUnitCount: index + 1, totalUnitCount: count, isComplete: complete))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private static let markdownChunks = [
        """
        # Streaming answer

        RichTextView receives **partial Markdown**, reuses unchanged elements, and keeps the previous rendered frame visible while new layout work runs.

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
        | Parser | Parse semantic nodes | Stable IDs |
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
        The source arrives one character every 20 ms. Formula previews temporarily close unfinished environments without changing the source.
        """
    ]
}
