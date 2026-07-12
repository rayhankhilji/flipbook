import Foundation
import PDFKit

/// A resolved node of the PDF's table of contents, decoupled from PDFKit so the
/// sidebar UI never touches `PDFOutline` directly.
public struct OutlineNode: Identifiable, Sendable {
    public let id: UUID
    public let title: String
    public let pageIndex: Int?
    public let children: [OutlineNode]

    public init(id: UUID = UUID(), title: String, pageIndex: Int?, children: [OutlineNode]) {
        self.id = id
        self.title = title
        self.pageIndex = pageIndex
        self.children = children
    }

    /// Walks a document's outline tree. Returns an empty array when the PDF has no TOC.
    public static func extract(from document: PDFDocument) -> [OutlineNode] {
        guard let root = document.outlineRoot else { return [] }
        return childNodes(of: root, in: document)
    }

    private static func childNodes(of outline: PDFOutline, in document: PDFDocument) -> [OutlineNode] {
        (0..<outline.numberOfChildren).compactMap { index in
            guard let child = outline.child(at: index) else { return nil }
            let title = child.label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let pageIndex = child.destination?.page.map { document.index(for: $0) }
            let children = childNodes(of: child, in: document)
            guard !title.isEmpty || !children.isEmpty else { return nil }
            return OutlineNode(
                title: title.isEmpty ? "Untitled" : title,
                pageIndex: pageIndex,
                children: children
            )
        }
    }
}
