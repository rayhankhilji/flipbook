# Flipbook

A native macOS app that turns PDFs into an immersive, book-like reading experience — calm, minimal, and comfortable for long sessions.

## Features

- **Library** — drag-and-drop PDF import (or ⌘O), cover grid with reading-progress rings, graceful "Locate File…" relinking when files move.
- **Two reading modes** — a gesture-driven page turn (two-finger swipe tracks the page 1:1, spring-settles on release) and continuous scrolling with pinch-to-zoom.
- **Nine reading themes** — from Warm Paper to True Black. Themes restyle the actual PDF pixels via a Core Image pipeline: light themes tint paper warmth, dark themes use a lightness-preserving smart invert, and photo-heavy pages are detected and dimmed instead of color-negated.
- **Bookmarks & highlights** — ⌘D bookmark ribbon, press-and-hold-then-drag highlighting with real text selection on text PDFs and region selection on scans, all in a four-tab sidebar (Contents / Thumbnails / Bookmarks / Highlights).
- **Book presentation** — two-page spread with cover board, spine gutter shadow, stacked page-edge hints that shift as you read, and a true two-sided page flip over the spine. Narrow windows fall back to one large readable page.
- **Reflow mode** — re-typesets the book's text natively with your choice of font (serif/sans/rounded/mono) and size, colored by the active theme. Fully programmatic, no AI.
- **Auto topic detection** — PDFs without a TOC get one synthesized from font-metric heading detection, navigable in the sidebar.
- **Focus mode** (⇧⌘F) — chrome melts away, just the page.
- **Settings** — theme, warmth/brightness, animation speed, gestures, accent color; all applied live.

## Development

Requires Xcode 26+ on macOS 26+.

```sh
brew install xcodegen   # once
xcodegen generate       # regenerate Flipbook.xcodeproj after adding/removing files
open Flipbook.xcodeproj
```

The project is defined declaratively in `project.yml`. Source layout:

- `Flipbook/` — app target: `App/` (entry point, app model, menu commands) and `Features/` (Library, Reader, Highlights, Settings), organized by feature.
- `Packages/FlipbookCore` — SwiftData models, `BookDocument` (PDFKit wrapper), `PageRenderer` (actor-isolated rasterization + cache), `ThemeCompositor` (Core Image theming). No SwiftUI dependency.
- `Packages/FlipbookDesignSystem` — design tokens (color, typography, spacing, animation) and reusable components.

Tests: `cd Packages/FlipbookCore && swift test` (Swift Testing). Themed-page snapshot PNGs for visual inspection: `SNAPSHOT_DIR=/tmp/snaps swift test --filter VisualSnapshotTests`.

## Deferred (architecture supports, not yet built)

Quick Look preview extension, Sparkle auto-updates, Developer ID signing/notarization pipeline, per-book theme overrides, cloud sync (SwiftData → CloudKit path kept clean), annotations export, OCR for scanned-PDF accessibility.
