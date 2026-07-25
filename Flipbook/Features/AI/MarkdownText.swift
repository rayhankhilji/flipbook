import SwiftUI

/// A block-level Markdown renderer tuned for chat replies. SwiftUI's `Text(markdown:)` only
/// handles inline styling; this adds headings, bullet/numbered lists, blockquotes, and code
/// blocks so assistant messages read as structured prose rather than one flat paragraph.
/// Inline emphasis (bold/italic/code) is delegated to `AttributedString`.
struct MarkdownText: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    // MARK: - Rendering

    @ViewBuilder
    private func view(for block: Block) -> some View {
        switch block {
        case .heading(let level, let text):
            inline(text)
                .font(.system(level == 1 ? .title3 : level == 2 ? .headline : .subheadline).weight(.semibold))
                .padding(.top, level <= 2 ? 2 : 0)

        case .paragraph(let text):
            inline(text)
                .font(.system(.body))
                .lineSpacing(2)

        case .bullet(let items):
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle().fill(.secondary)
                            .frame(width: 4, height: 4)
                            .offset(y: -3)
                        inline(item).font(.system(.body)).lineSpacing(2)
                    }
                }
            }

        case .numbered(let items):
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(index + 1).")
                            .font(.system(.body).monospacedDigit())
                            .foregroundStyle(.secondary)
                        inline(item).font(.system(.body)).lineSpacing(2)
                    }
                }
            }

        case .quote(let text):
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2).fill(.secondary.opacity(0.4)).frame(width: 3)
                inline(text).font(.system(.body)).foregroundStyle(.secondary).italic()
            }

        case .code(let text):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(text)
                    .font(.system(.callout, design: .monospaced))
                    .padding(10)
            }
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func inline(_ string: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: string,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(attributed)
        }
        return Text(string)
    }

    // MARK: - Parsing

    private enum Block {
        case heading(level: Int, text: String)
        case paragraph(String)
        case bullet([String])
        case numbered([String])
        case quote(String)
        case code(String)
    }

    private var blocks: [Block] {
        var result: [Block] = []
        var paragraph: [String] = []
        var bullets: [String] = []
        var numbers: [String] = []
        var codeLines: [String] = []
        var inCode = false

        func flushParagraph() {
            if !paragraph.isEmpty {
                result.append(.paragraph(paragraph.joined(separator: " ")))
                paragraph = []
            }
        }
        func flushLists() {
            if !bullets.isEmpty { result.append(.bullet(bullets)); bullets = [] }
            if !numbers.isEmpty { result.append(.numbered(numbers)); numbers = [] }
        }

        for rawLine in markdown.components(separatedBy: .newlines) {
            if rawLine.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if inCode {
                    result.append(.code(codeLines.joined(separator: "\n")))
                    codeLines = []
                    inCode = false
                } else {
                    flushParagraph(); flushLists()
                    inCode = true
                }
                continue
            }
            if inCode { codeLines.append(rawLine); continue }

            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                flushParagraph(); flushLists()
            } else if let heading = Self.heading(trimmed) {
                flushParagraph(); flushLists()
                result.append(.heading(level: heading.0, text: heading.1))
            } else if let bullet = Self.bulletContent(trimmed) {
                flushParagraph()
                if !numbers.isEmpty { result.append(.numbered(numbers)); numbers = [] }
                bullets.append(bullet)
            } else if let number = Self.numberedContent(trimmed) {
                flushParagraph()
                if !bullets.isEmpty { result.append(.bullet(bullets)); bullets = [] }
                numbers.append(number)
            } else if trimmed.hasPrefix("> ") {
                flushParagraph(); flushLists()
                result.append(.quote(String(trimmed.dropFirst(2))))
            } else {
                flushLists()
                paragraph.append(trimmed)
            }
        }

        if inCode, !codeLines.isEmpty { result.append(.code(codeLines.joined(separator: "\n"))) }
        flushParagraph(); flushLists()
        return result
    }

    private static func heading(_ line: String) -> (Int, String)? {
        guard line.hasPrefix("#") else { return nil }
        let hashes = line.prefix { $0 == "#" }.count
        guard hashes <= 4 else { return nil }
        let text = line.dropFirst(hashes).trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : (min(hashes, 3), text)
    }

    private static func bulletContent(_ line: String) -> String? {
        for marker in ["- ", "* ", "• "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count))
        }
        return nil
    }

    /// Matches "1. " / "12) " style list markers.
    private static func numberedContent(_ line: String) -> String? {
        let digits = line.prefix { $0.isNumber }
        guard !digits.isEmpty else { return nil }
        let rest = line.dropFirst(digits.count)
        guard rest.hasPrefix(". ") || rest.hasPrefix(") ") else { return nil }
        return String(rest.dropFirst(2))
    }
}
