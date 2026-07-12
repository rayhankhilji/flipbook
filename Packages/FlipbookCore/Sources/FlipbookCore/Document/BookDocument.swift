import Foundation
import PDFKit

/// Wraps `PDFKit.PDFDocument` as a data/geometry source. Never exposed to the UI layer
/// directly — views talk to `ReadingSession`/`PageRenderer`, which own one of these.
///
/// `@unchecked Sendable`: the wrapped `PDFDocument` is never mutated after init, page
/// rasterization is serialized through the `PageRenderer` actor, and main-thread access
/// is limited to metadata/geometry reads (page count, bounds, outline) captured here.
public final class BookDocument: @unchecked Sendable {
    public let url: URL
    public let pdfDocument: PDFDocument

    /// Point-space page sizes captured eagerly so layout code never touches PDFKit.
    public let pageSizes: [CGSize]

    /// Table of contents, resolved once at open.
    public let outline: [OutlineNode]

    public init?(url: URL) {
        guard let document = PDFDocument(url: url) else { return nil }
        self.url = url
        self.pdfDocument = document
        self.outline = OutlineNode.extract(from: document)
        self.pageSizes = (0..<document.pageCount).map { index in
            guard let page = document.page(at: index) else { return CGSize(width: 612, height: 792) }
            let bounds = page.bounds(for: .mediaBox)
            // A 90°/270° page rotation swaps the displayed width/height.
            if page.rotation % 180 != 0 {
                return CGSize(width: bounds.height, height: bounds.width)
            }
            return bounds.size
        }
    }

    public func pageSize(at index: Int) -> CGSize {
        guard pageSizes.indices.contains(index) else { return CGSize(width: 612, height: 792) }
        return pageSizes[index]
    }

    public var pageCount: Int {
        pdfDocument.pageCount
    }

    public var title: String {
        if let title = pdfDocument.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String,
           !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return title
        }
        return url.deletingPathExtension().lastPathComponent
    }

    public var authorHint: String? {
        pdfDocument.documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String
    }

    public func page(at index: Int) -> PDFPage? {
        pdfDocument.page(at: index)
    }

    /// Whether the page has an extractable text layer (drives text-selection vs.
    /// region-based highlighting for scanned pages).
    public func pageHasText(at index: Int) -> Bool {
        guard let page = page(at: index) else { return false }
        let text = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !text.isEmpty
    }

    /// Extracted text for one page, trimmed. Used to ground the AI assistant in what's
    /// on screen without handing PDFKit types up to the UI/AI layers.
    public func pageText(at index: Int) -> String? {
        guard let page = page(at: index) else { return nil }
        let text = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }

    /// Builds a text selection between two points in PDF page space (bottom-left origin),
    /// returning per-line bounds ready for highlight quads plus the selected text.
    public func textSelection(
        pageIndex: Int,
        from start: CGPoint,
        to end: CGPoint
    ) -> (rects: [CGRect], text: String)? {
        guard let page = page(at: pageIndex) else { return nil }
        guard let selection = pdfDocument.selection(
            from: page, at: start,
            to: page, at: end
        ) else { return nil }

        let lineRects = selection.selectionsByLine()
            .map { $0.bounds(for: page) }
            .filter { !$0.isEmpty }
        guard !lineRects.isEmpty else { return nil }

        return (lineRects, selection.string ?? "")
    }

    /// Text contained within a rectangle in PDF page space (bottom-left origin). Used to
    /// capture the words under a free-form marker highlight for its note snippet, without
    /// snapping the visible highlight to the text runs.
    public func text(inRect rect: CGRect, pageIndex: Int) -> String? {
        guard let page = page(at: pageIndex), let selection = page.selection(for: rect) else { return nil }
        let text = selection.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }

    /// Renders a low-res cover thumbnail from the first page, used for the Library grid.
    public func renderCoverThumbnail(maxDimension: CGFloat = 480) -> CGImage? {
        guard let page = pdfDocument.page(at: 0) else { return nil }
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        let scale = maxDimension / max(bounds.width, bounds.height)
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let thumbnail = page.thumbnail(of: size, for: .mediaBox)
        return thumbnail.cgImageForProxy()
    }
}
