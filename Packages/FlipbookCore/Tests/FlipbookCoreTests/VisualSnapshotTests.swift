import CoreGraphics
import CoreText
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import FlipbookCore

/// Renders a realistic text PDF through the full PageRenderer + ThemeCompositor pipeline
/// and writes themed PNGs for human inspection. Runs only when SNAPSHOT_DIR is set —
/// it's a visual-verification aid, not an assertion suite.
@Suite struct VisualSnapshotTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] != nil))
    func writeThemedPageSnapshots() async throws {
        let snapshotDir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SNAPSHOT_DIR"]!)
        try FileManager.default.createDirectory(at: snapshotDir, withIntermediateDirectories: true)

        let pdfURL = snapshotDir.appendingPathComponent("fixture-text.pdf")
        try makeTextPDF(at: pdfURL)
        defer { try? FileManager.default.removeItem(at: pdfURL) }

        let document = try #require(BookDocument(url: pdfURL))
        let renderer = PageRenderer(
            bookID: UUID(),
            document: document,
            compositor: ThemeCompositor.shared.makeRendererHook()
        )

        for theme in [BuiltInThemes.original, BuiltInThemes.warmPaper, BuiltInThemes.sepia, BuiltInThemes.midnight, BuiltInThemes.trueBlack] {
            let image = try #require(
                await renderer.image(pageIndex: 0, zoom: 1.0, themeID: theme.id, screenScale: 2)
            )
            let outURL = snapshotDir.appendingPathComponent("page-\(theme.id).png")
            let destination = try #require(
                CGImageDestinationCreateWithURL(outURL as CFURL, UTType.png.identifier as CFString, 1, nil)
            )
            CGImageDestinationAddImage(destination, image, nil)
            #expect(CGImageDestinationFinalize(destination))
        }
    }

    private func makeTextPDF(at url: URL) throws {
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let context = try #require(CGContext(url as CFURL, mediaBox: &mediaBox, nil))

        let body = Array(
            repeating: "The quick brown fox jumps over the lazy dog, a sentence long used by " +
                "typesetters to exercise every letter of the alphabet in a single elegant line. ",
            count: 24
        ).joined()

        let text = NSMutableAttributedString()
        text.append(NSAttributedString(
            string: "Chapter One\n\n",
            attributes: [.font: CTFontCreateWithName("Georgia-Bold" as CFString, 24, nil)]
        ))
        text.append(NSAttributedString(
            string: body,
            attributes: [.font: CTFontCreateWithName("Georgia" as CFString, 12, nil)]
        ))

        context.beginPDFPage(nil)
        let framesetter = CTFramesetterCreateWithAttributedString(text)
        let path = CGPath(rect: mediaBox.insetBy(dx: 60, dy: 60), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        CTFrameDraw(frame, context)
        context.endPDFPage()
        context.closePDF()
    }
}
