import AppKit
import FlipbookCore
import FlipbookDesignSystem
import SwiftUI

/// Overlays a spread's sticky notes above the page-turn surface. Notes are positioned by
/// their normalized page coordinates but drawn over the *whole* reading surface (not clipped
/// to the page), so they can rest in the margin / dead space around the book as well as over
/// the text. Each note is independently draggable and collapsible.
struct StickyNotesLayer: View {
    let session: ReadingSession
    let layout: BookSpreadLayout

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(visiblePages, id: \.self) { page in
                let rect = pageRect(for: page)
                ForEach(session.stickyNotes(forPage: page)) { note in
                    StickyNoteView(session: session, note: note, pageRect: rect)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Pages currently on screen for this spread (deduped for single-page layout).
    private var visiblePages: [Int] {
        var pages: [Int] = []
        if !layout.isSingle, let left = layout.leftPageIndex { pages.append(left) }
        if let right = layout.rightPageIndex ?? layout.leftPageIndex, !pages.contains(right) {
            pages.append(right)
        }
        return pages
    }

    private func pageRect(for page: Int) -> CGRect {
        if !layout.isSingle, layout.leftPageIndex == page { return layout.leftRect }
        return layout.rightRect
    }
}

/// Sticky notes for a single page, used by the continuous-scroll mode where each page row
/// is its own coordinate space (the row's bounds *are* the page rect).
struct StickyNotesPageLayer: View {
    let session: ReadingSession
    let pageIndex: Int

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                ForEach(session.stickyNotes(forPage: pageIndex)) { note in
                    StickyNoteView(
                        session: session,
                        note: note,
                        pageRect: CGRect(origin: .zero, size: geo.size)
                    )
                }
            }
        }
    }
}

/// A single sticky note. Collapsed it's a small colored tab; tapping expands it into an
/// editable card with a rich-text mini toolbar. Drag the tab (collapsed) or the note's
/// header (expanded) to reposition.
struct StickyNoteView: View {
    let session: ReadingSession
    let note: StickyNote
    /// The note's page rect in the layer's coordinate space, used to map drags → normalized.
    let pageRect: CGRect

    @State private var dragOffset: CGSize = .zero

    private var entry: StickyNotePalette.Entry { StickyNotePalette.entry(for: note.colorTag) }

    private var basePoint: CGPoint {
        CGPoint(
            x: pageRect.minX + CGFloat(note.normalizedX) * pageRect.width,
            y: pageRect.minY + CGFloat(note.normalizedY) * pageRect.height
        )
    }

    var body: some View {
        Group {
            if note.isExpanded {
                expandedCard
            } else {
                collapsedTab
            }
        }
        .position(x: basePoint.x + dragOffset.width, y: basePoint.y + dragOffset.height)
        .animation(AnimationTokens.quick, value: note.isExpanded)
    }

    // MARK: Collapsed

    private var collapsedTab: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(entry.paper)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(entry.edge.opacity(0.7), lineWidth: 0.5)
                )
            Image(systemName: note.text.isEmpty ? "note.text" : "text.alignleft")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.6))
        }
        .frame(width: 30, height: 30)
        .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
        .rotationEffect(.degrees(-3))
        .contentShape(Rectangle())
        .gesture(dragGesture)
        .onTapGesture { session.setStickyNote(note, expanded: true) }
        .help(note.text.isEmpty ? "Empty note — tap to write" : note.text)
    }

    // MARK: Expanded

    /// The card has one explicit width: without it, the header's `Spacer` makes the card
    /// greedily take the whole proposed size under `.position` — the full-window-banner bug.
    private var expandedCard: some View {
        StickyNoteEditorCard(session: session, note: note) {
            header
        }
        .frame(width: 252)
        .fixedSize()
        .shadow(color: .black.opacity(0.28), radius: 8, y: 4)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.4))

            Menu {
                ForEach(StickyNotePalette.all) { color in
                    Button {
                        session.setStickyNoteColor(note, colorTag: color.id)
                    } label: {
                        Label(color.name, systemImage: note.colorTag == color.id ? "checkmark" : "circle.fill")
                    }
                }
            } label: {
                Circle().fill(entry.edge).frame(width: 12, height: 12)
            }
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()

            Spacer(minLength: 0)

            Button {
                session.setStickyNote(note, expanded: false)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.black.opacity(0.4))
            }
            .buttonStyle(.plain)
            .help("Collapse")

            Button {
                session.removeStickyNote(note)
            } label: {
                Image(systemName: "trash.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.black.opacity(0.4))
            }
            .buttonStyle(.plain)
            .help("Delete note")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(entry.edge.opacity(0.28))
        .contentShape(Rectangle())
        .gesture(dragGesture)
    }

    // MARK: Dragging

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in dragOffset = value.translation }
            .onEnded { value in
                let newX = note.normalizedX + Double(value.translation.width / max(pageRect.width, 1))
                let newY = note.normalizedY + Double(value.translation.height / max(pageRect.height, 1))
                session.moveStickyNote(note, normalizedX: newX, normalizedY: newY)
                dragOffset = .zero
            }
    }
}

// MARK: - Shared editor card

/// The expanded note body — palette paper, caller-supplied header row, formatting toolbar,
/// and the rich text editor. Shared between the floating page card and the reflow popover.
struct StickyNoteEditorCard<Header: View>: View {
    let session: ReadingSession
    let note: StickyNote
    @ViewBuilder let headerContent: () -> Header

    @State private var controller = RichNoteController()

    private var entry: StickyNotePalette.Entry { StickyNotePalette.entry(for: note.colorTag) }

    var body: some View {
        VStack(spacing: 0) {
            headerContent()
            formattingBar
            RichNoteEditor(session: session, note: note, controller: controller)
                .frame(height: 128)
                .padding(.horizontal, 4)
                .padding(.bottom, 4)
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(entry.paper)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(entry.edge.opacity(0.7), lineWidth: 0.5)
        )
    }

    /// The "tiptap" row: character formatting that applies to the selection (or the
    /// typing style when nothing is selected).
    private var formattingBar: some View {
        HStack(spacing: 2) {
            formatButton("bold", help: "Bold (⌘B)") { controller.toggleBold() }
            formatButton("italic", help: "Italic (⌘I)") { controller.toggleItalic() }
            formatButton("underline", help: "Underline (⌘U)") { controller.toggleUnderline() }
            formatButton("strikethrough", help: "Strikethrough") { controller.toggleStrikethrough() }
            Divider().frame(height: 12)
            formatButton("list.bullet", help: "Bulleted list") { controller.toggleBullets() }
            formatButton("textformat.size.smaller", help: "Smaller text") { controller.adjustFontSize(by: -1) }
            formatButton("textformat.size.larger", help: "Larger text") { controller.adjustFontSize(by: 1) }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(entry.edge.opacity(0.14))
    }

    private func formatButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.62))
                .frame(width: 20, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - Reflow chip

/// Reflow re-typesets the text, so a note's on-page position is meaningless there. Instead
/// each page's notes appear as small sticky chips at that page's break marker; tapping one
/// opens the same rich editor in a popover.
struct ReflowNoteChip: View {
    let session: ReadingSession
    let note: StickyNote

    @State private var showEditor = false

    private var entry: StickyNotePalette.Entry { StickyNotePalette.entry(for: note.colorTag) }

    var body: some View {
        Button {
            showEditor = true
        } label: {
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(entry.edge)
                    .frame(width: 8, height: 8)
                Text(note.text.isEmpty ? "Note" : note.text)
                    .font(TypographyTokens.caption)
                    .foregroundStyle(Color.black.opacity(0.7))
                    .lineLimit(1)
                    .frame(maxWidth: 140, alignment: .leading)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(entry.paper)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(entry.edge.opacity(0.6), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showEditor, arrowEdge: .bottom) {
            StickyNoteEditorCard(session: session, note: note) {
                HStack(spacing: 6) {
                    Menu {
                        ForEach(StickyNotePalette.all) { color in
                            Button {
                                session.setStickyNoteColor(note, colorTag: color.id)
                            } label: {
                                Label(color.name, systemImage: note.colorTag == color.id ? "checkmark" : "circle.fill")
                            }
                        }
                    } label: {
                        Circle().fill(entry.edge).frame(width: 12, height: 12)
                    }
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    .fixedSize()

                    Spacer(minLength: 0)

                    Button {
                        showEditor = false
                        session.removeStickyNote(note)
                    } label: {
                        Image(systemName: "trash.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.black.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                    .help("Delete note")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(entry.edge.opacity(0.28))
            }
            .frame(width: 252)
        }
    }
}

// MARK: - Rich text engine

/// Formatting operations targeting the live `NSTextView`. Held by the card so toolbar
/// buttons (SwiftUI) can message the AppKit editor.
@MainActor
final class RichNoteController {
    weak var textView: NSTextView?
    var save: (() -> Void)?

    private func withStorage(_ body: (NSTextStorage, NSRange) -> Void) {
        guard let textView, let storage = textView.textStorage else { return }
        body(storage, textView.selectedRange())
        save?()
    }

    func toggleBold() { toggleFontTrait(.boldFontMask, trait: .bold) }
    func toggleItalic() { toggleFontTrait(.italicFontMask, trait: .italic) }

    private func toggleFontTrait(_ mask: NSFontTraitMask, trait: NSFontDescriptor.SymbolicTraits) {
        withStorage { storage, range in
            let manager = NSFontManager.shared
            guard range.length > 0 else {
                if let textView {
                    let current = (textView.typingAttributes[.font] as? NSFont) ?? .systemFont(ofSize: 13)
                    let has = current.fontDescriptor.symbolicTraits.contains(trait)
                    textView.typingAttributes[.font] = has
                        ? manager.convert(current, toNotHaveTrait: mask)
                        : manager.convert(current, toHaveTrait: mask)
                }
                return
            }
            // If every run already has the trait, remove it; otherwise add it everywhere.
            var allHave = true
            storage.enumerateAttribute(.font, in: range) { value, _, _ in
                let font = (value as? NSFont) ?? .systemFont(ofSize: 13)
                if !font.fontDescriptor.symbolicTraits.contains(trait) { allHave = false }
            }
            storage.beginEditing()
            storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
                let font = (value as? NSFont) ?? .systemFont(ofSize: 13)
                let converted = allHave
                    ? manager.convert(font, toNotHaveTrait: mask)
                    : manager.convert(font, toHaveTrait: mask)
                storage.addAttribute(.font, value: converted, range: subrange)
            }
            storage.endEditing()
        }
    }

    func toggleUnderline() { toggleFlag(.underlineStyle) }
    func toggleStrikethrough() { toggleFlag(.strikethroughStyle) }

    private func toggleFlag(_ key: NSAttributedString.Key) {
        withStorage { storage, range in
            guard range.length > 0 else {
                if let textView {
                    let on = (textView.typingAttributes[key] as? Int ?? 0) != 0
                    textView.typingAttributes[key] = on ? 0 : NSUnderlineStyle.single.rawValue
                }
                return
            }
            var allOn = true
            storage.enumerateAttribute(key, in: range) { value, _, _ in
                if (value as? Int ?? 0) == 0 { allOn = false }
            }
            storage.addAttribute(key, value: allOn ? 0 : NSUnderlineStyle.single.rawValue, range: range)
        }
    }

    /// Simple text-level bullets: prefix each selected line with "•  " (or strip it).
    func toggleBullets() {
        guard let textView, let storage = textView.textStorage else { return }
        let text = storage.string as NSString
        let lineRange = text.lineRange(for: textView.selectedRange())
        let lines = text.substring(with: lineRange).components(separatedBy: "\n")
        let contentLines = lines.last == "" ? Array(lines.dropLast()) : lines
        guard !contentLines.isEmpty else { return }

        let allBulleted = contentLines.allSatisfy { $0.hasPrefix("•  ") || $0.isEmpty }
        let transformed = contentLines.map { line -> String in
            if allBulleted {
                return line.hasPrefix("•  ") ? String(line.dropFirst(3)) : line
            }
            return line.isEmpty ? line : "•  " + line
        }
        let replacement = transformed.joined(separator: "\n") + (lines.last == "" ? "\n" : "")
        if textView.shouldChangeText(in: lineRange, replacementString: replacement) {
            storage.replaceCharacters(in: lineRange, with: replacement)
            textView.didChangeText()
        }
        save?()
    }

    func adjustFontSize(by delta: CGFloat) {
        withStorage { storage, range in
            guard range.length > 0 else {
                if let textView {
                    let font = (textView.typingAttributes[.font] as? NSFont) ?? .systemFont(ofSize: 13)
                    let size = min(max(font.pointSize + delta, 9), 28)
                    textView.typingAttributes[.font] = NSFont(descriptor: font.fontDescriptor, size: size) ?? font
                }
                return
            }
            storage.beginEditing()
            storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
                let font = (value as? NSFont) ?? .systemFont(ofSize: 13)
                let size = min(max(font.pointSize + delta, 9), 28)
                if let resized = NSFont(descriptor: font.fontDescriptor, size: size) {
                    storage.addAttribute(.font, value: resized, range: subrange)
                }
            }
            storage.endEditing()
        }
    }
}

/// `NSTextView`-backed rich editor for a sticky note. Loads RTF (falling back to the plain
/// text), saves both representations on every edit, and supports the standard ⌘B/⌘I/⌘U keys.
struct RichNoteEditor: NSViewRepresentable {
    let session: ReadingSession
    let note: StickyNote
    let controller: RichNoteController

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session, note: note)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.verticalScrollElasticity = .none

        guard let textView = scroll.documentView as? NSTextView else { return scroll }
        textView.delegate = context.coordinator
        textView.isRichText = true
        textView.allowsUndo = true
        textView.usesFontPanel = true
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: 13)
        textView.textColor = NSColor.black.withAlphaComponent(0.85)
        textView.insertionPointColor = NSColor.black.withAlphaComponent(0.85)
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.isAutomaticQuoteSubstitutionEnabled = false

        if let rtf = note.rtfData,
           let attributed = NSAttributedString(rtf: rtf, documentAttributes: nil) {
            textView.textStorage?.setAttributedString(attributed)
        } else {
            textView.string = note.text
        }

        controller.textView = textView
        context.coordinator.textView = textView
        controller.save = { [weak coordinator = context.coordinator] in coordinator?.persist() }
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        // Content is pushed model→view only on creation; edits flow view→model. Re-applying
        // the model here would fight the user's cursor mid-keystroke.
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        let session: ReadingSession
        let note: StickyNote
        weak var textView: NSTextView?

        init(session: ReadingSession, note: StickyNote) {
            self.session = session
            self.note = note
        }

        func textDidChange(_ notification: Notification) {
            textView = notification.object as? NSTextView
            persist()
        }

        func persist() {
            guard let storage = textView?.textStorage else { return }
            let rtf = storage.rtf(from: NSRange(location: 0, length: storage.length),
                                  documentAttributes: [:])
            session.updateStickyNote(note, plainText: storage.string, rtfData: rtf)
        }
    }
}
