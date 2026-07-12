import Foundation

/// A block of reflowable content extracted from the PDF's text layer.
public struct ReflowBlock: Identifiable, Sendable {
    public enum Kind: Sendable, Equatable {
        case paragraph(String)
        /// Marks where a source page begins (0-based index), for progress + navigation.
        case pageBreak(Int)
    }

    public let id: Int
    public let kind: Kind

    public init(id: Int, kind: Kind) {
        self.id = id
        self.kind = kind
    }
}

/// Rebuilds readable paragraphs from PDF text extraction, which hard-wraps every layout
/// line. Pure string logic — no PDFKit — so it's trivially unit-testable; callers feed
/// it per-page strings gathered through the `PageRenderer` actor.
public enum ReflowExtractor {
    public static func blocks(fromPageTexts pageTexts: [String]) -> [ReflowBlock] {
        var blocks: [ReflowBlock] = []
        var nextID = 0

        for (pageIndex, text) in pageTexts.enumerated() {
            blocks.append(ReflowBlock(id: nextID, kind: .pageBreak(pageIndex)))
            nextID += 1
            for paragraph in paragraphs(fromPageText: text) {
                blocks.append(ReflowBlock(id: nextID, kind: .paragraph(paragraph)))
                nextID += 1
            }
        }
        return blocks
    }

    /// Merges hard-wrapped lines back into paragraphs:
    /// - blank lines always split paragraphs;
    /// - a line that ends with terminal punctuation and is noticeably shorter than the
    ///   page's typical line starts a new paragraph after it (classic paragraph tail);
    /// - hyphenated line endings re-join without the hyphen.
    public static func paragraphs(fromPageText text: String) -> [String] {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        let maxLineLength = lines.map(\.count).max() ?? 0
        let shortLineThreshold = Double(maxLineLength) * 0.6

        var paragraphs: [String] = []
        var current = ""

        func flush() {
            let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                paragraphs.append(trimmed)
            }
            current = ""
        }

        for line in lines {
            if line.isEmpty {
                flush()
                continue
            }

            if current.isEmpty {
                current = line
            } else if current.hasSuffix("-") {
                current.removeLast()
                current += line
            } else {
                current += " " + line
            }

            let endsSentence = line.hasSuffix(".") || line.hasSuffix("!") || line.hasSuffix("?")
                || line.hasSuffix(".\"") || line.hasSuffix(".”") || line.hasSuffix(":")
            let isShort = Double(line.count) < shortLineThreshold
            if endsSentence && isShort {
                flush()
            }
        }
        flush()
        return paragraphs
    }
}
