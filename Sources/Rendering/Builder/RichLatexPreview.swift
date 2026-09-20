import Foundation

/// Closes structures in a display-only copy. The original LaTeX remains authoritative.
enum RichLatexPreview {
    static func complete(_ source: String) -> String? {
        let characters = Array(source)
        var closing: [String] = []
        var index = 0
        var end = characters.count
        while index < characters.count {
            let character = characters[index]
            if character == "\\" {
                let start = index
                index += 1
                guard index < characters.count else { end = start; break }
                guard characters[index].isASCII && characters[index].isLetter else {
                    index += 1 // Escaped braces, spaces and row separators are not groups.
                    continue
                }
                let commandStart = index
                while index < characters.count, characters[index].isASCII, characters[index].isLetter { index += 1 }
                let command = String(characters[commandStart..<index])
                if command == "begin" || command == "end" {
                    while index < characters.count, characters[index].isWhitespace { index += 1 }
                    guard index < characters.count, characters[index] == "{",
                          let close = characters[index...].firstIndex(of: "}") else { end = start; break }
                    let environment = String(characters[(index + 1)..<close])
                    let terminator = "\\end{\(environment)}"
                    if command == "begin" {
                        closing.append(terminator)
                    } else {
                        guard closing.last == terminator else { return nil }
                        closing.removeLast()
                    }
                    index = close + 1
                } else if command == "left" {
                    closing.append("\\right.")
                } else if command == "right" {
                    guard closing.last == "\\right." else { return nil }
                    closing.removeLast()
                }
                continue
            }
            if character == "%" { return nil } // Comments need a separate lexer; keep the last valid frame.
            if character == "{" { closing.append("}") }
            if character == "}" {
                guard closing.last == "}" else { return nil }
                closing.removeLast()
            }
            index += 1
        }
        guard !closing.isEmpty || end < characters.count else { return nil }
        return String(characters[..<end]) + closing.reversed().joined()
    }
}
