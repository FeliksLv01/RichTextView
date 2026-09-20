import Foundation
import Markdown

enum RichMarkdownStreamingRewriter {
    static func closeMath(in source: String) -> String {
        guard !endsInsideCode(source) else { return source }
        if hasUnclosedPair(in: source, open: "$$", close: "$$") { return source + "\n$$" }
        if hasUnclosedPair(in: source, open: "\\[", close: "\\]") { return source + "\n\\]" }
        if hasUnclosedPair(in: source, open: "\\(", close: "\\)") { return source + "\\)" }
        return source
    }

    static func rewriteEmphasis(in document: Document) -> Document {
        guard let text = document.rightmostDescendant as? Text else { return document }
        var rewriter = PartialEmphasisRewriter(target: text)
        return rewriter.visit(document) as? Document ?? document
    }

    private static func hasUnclosedPair(in source: String, open: String, close: String) -> Bool {
        if open == close {
            return source.allRanges(of: open).count.isMultiple(of: 2) == false
        }
        var depth = 0
        var index = source.startIndex
        while index < source.endIndex {
            if source[index...].hasPrefix(open) {
                depth += 1
                index = source.index(index, offsetBy: open.count)
            } else if source[index...].hasPrefix(close), depth > 0 {
                depth -= 1
                index = source.index(index, offsetBy: close.count)
            } else {
                index = source.index(after: index)
            }
        }
        return depth > 0
    }

    private static func endsInsideCode(_ source: String) -> Bool {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        let fenceCount = lines.filter {
            let line = $0.drop(while: { $0 == " " || $0 == "\t" })
            return line.hasPrefix("```") || line.hasPrefix("~~~")
        }.count
        guard fenceCount.isMultiple(of: 2) else { return true }
        return (lines.last?.filter { $0 == "`" }.count ?? 0).isMultiple(of: 2) == false
    }
}

private final class PartialEmphasisRewriter: MarkupRewriter {
    private let target: Text

    init(target: Text) {
        self.target = target
    }

    func visitParagraph(_ paragraph: Paragraph) -> Markup? { rewrite(paragraph) ?? paragraph }
    func visitHeading(_ heading: Heading) -> Markup? { rewrite(heading) ?? heading }
    func visitTableCell(_ tableCell: Table.Cell) -> Markup? { rewrite(tableCell) ?? tableCell }

    private func rewrite<T: InlineContainer>(_ container: T) -> T? {
        guard
            let last = container.child(at: container.childCount - 1) as? Text,
            last.isIdentical(to: target),
            let match = unmatchedDelimiter(in: last.string)
        else { return nil }

        let prefix = String(last.string[..<match.range.lowerBound])
        let content = String(last.string[match.range.upperBound...])
        let styled: InlineMarkup = match.isStrong ? Strong([Text(content)]) : Emphasis([Text(content)])
        var result = container
        result.replaceChildrenInRange(
            (container.childCount - 1)..<container.childCount,
            with: prefix.isEmpty ? [styled] : [Text(prefix), styled]
        )
        return result
    }

    private func unmatchedDelimiter(in text: String) -> (range: Range<String.Index>, isStrong: Bool)? {
        for delimiter in ["**", "__", "*", "_"] {
            let candidates = text.allRanges(of: delimiter).filter { range in
                guard range.lowerBound == text.startIndex || text[text.index(before: range.lowerBound)].isWhitespace else {
                    return false
                }
                return range.lowerBound == text.startIndex || !text[..<range.lowerBound].hasSuffix("\\")
            }
            if let range = candidates.last, candidates.count.isMultiple(of: 2) == false {
                return (range, delimiter.count == 2)
            }
        }
        return nil
    }
}

private extension Markup {
    var rightmostDescendant: any Markup {
        var node: any Markup = self
        while node.childCount > 0, let child = node.child(at: node.childCount - 1) {
            node = child
        }
        return node
    }
}

private extension String {
    func allRanges(of substring: String) -> [Range<String.Index>] {
        var result: [Range<String.Index>] = []
        var start = startIndex
        while start < endIndex, let range = range(of: substring, range: start..<endIndex) {
            result.append(range)
            start = range.upperBound
        }
        return result
    }
}
