import SwiftUI

/// PDF page content is fixed and never restyled by Flipbook. These tokens govern only
/// Flipbook's own chrome (library, sidebar, settings, TOC, toolbar).
public enum TypographyTokens {
    /// Book titles in the Library grid and reader TOC — the one deliberate "bookish" touch.
    /// Uses Apple's system serif (New York), no font download required.
    public static let bookTitle = Font.system(.title3, design: .serif).weight(.semibold)
    public static let bookTitleLarge = Font.system(.title, design: .serif).weight(.semibold)

    /// Everything else uses the system font (SF Pro) for maximum native feel and legibility.
    public static let largeTitle = Font.system(.largeTitle, design: .default).weight(.bold)
    public static let title = Font.system(.title2, design: .default).weight(.semibold)
    public static let headline = Font.system(.headline, design: .default)
    public static let body = Font.system(.body, design: .default)
    public static let callout = Font.system(.callout, design: .default)
    public static let caption = Font.system(.caption, design: .default)
    public static let monospaceCaption = Font.system(.caption, design: .monospaced)
}
