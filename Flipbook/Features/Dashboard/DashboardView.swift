import FlipbookCore
import FlipbookDesignSystem
import SwiftData
import SwiftUI

/// The app's home screen: a warm bento grid sized to fill the fixed library window with no
/// vertical scrolling. Two columns that each run the full height — hero, week chart, and the
/// jump-back-in shelf on the left; streak, minutes, and library totals on the right — so
/// there is never leftover space in any corner. Cards are typographic (big numbers, quiet
/// captions, no icon chips) and share one cream/mocha tile family; the accent does the talking.
struct DashboardView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.colorScheme) private var colorScheme
    @Query private var readingDays: [ReadingDay]
    @State private var animateChart = false

    let books: [Book]
    let openBook: (Book) -> Void

    /// Fixed width of the right-hand card rail.
    private let railWidth: CGFloat = 232

    private var recentInProgress: [Book] {
        books
            .filter { !$0.isMissing && ($0.progress?.currentPageIndex ?? 0) > 0 && !isFinished($0) }
            .sorted { ($0.dateLastOpened ?? .distantPast) > ($1.dateLastOpened ?? .distantPast) }
    }

    private var hero: Book? { recentInProgress.first ?? books.first(where: { !$0.isMissing }) }

    private var minutesToday: Int {
        ReadingStats.minutesToday(in: readingDays) + Int(appModel.liveSessionSeconds / 60)
    }
    private var streak: Int { ReadingStats.currentStreak(in: readingDays) }
    private var weekDays: [ReadingStats.DaySlice] { ReadingStats.recentDays(in: readingDays, count: 7) }
    private var weekTotalMinutes: Int { weekDays.reduce(0) { $0 + $1.minutes } }
    private var finishedCount: Int { books.count(where: isFinished) }

    var body: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.md) {
            header

            HStack(alignment: .top, spacing: SpacingTokens.md) {
                // Left column — fills all remaining width.
                VStack(spacing: SpacingTokens.md) {
                    continueReadingCard
                    weekCard
                    recentStrip
                }

                // Right rail — same full height as the left column, so the grid's bottom
                // edge is one straight line with no orphaned corner.
                VStack(spacing: SpacingTokens.md) {
                    statCard(caption: "Streak", number: "\(streak)",
                             unit: streak == 1 ? "day" : "days", tint: BrandTokens.tileLatte)
                    todayCard
                    libraryCard
                }
                .frame(width: railWidth)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(SpacingTokens.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(BrandTokens.libraryBackground(for: colorScheme))
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.72).delay(0.05)) {
                animateChart = true
            }
        }
    }

    // MARK: - Header

    /// One compact line — greeting in ink, status in secondary — so the grid keeps the room.
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: SpacingTokens.sm) {
            Text(greeting)
                .font(TypographyTokens.bookTitleLarge)
                .foregroundStyle(ColorTokens.ink)
            Text(subtitle)
                .font(TypographyTokens.callout)
                .foregroundStyle(ColorTokens.inkSecondary)
            Spacer(minLength: 0)
        }
        .lineLimit(1)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }

    private var subtitle: String {
        if appModel.isReading { return "You're reading now — the timer's running." }
        if minutesToday > 0 { return "You've read \(minutesToday) min today. Keep it going." }
        if streak > 0 { return "Pick up where you left off and keep your streak alive." }
        return "Ready when you are. Open a book to begin."
    }

    // MARK: - Continue reading hero

    @ViewBuilder
    private var continueReadingCard: some View {
        DashboardCard(tint: BrandTokens.tileCream) {
            if let book = hero {
                HStack(alignment: .top, spacing: SpacingTokens.md) {
                    BookCoverThumbnail(book: book)
                        .shadow(color: .black.opacity(0.22), radius: 10, y: 5)

                    VStack(alignment: .leading, spacing: SpacingTokens.xs) {
                        cardCaption("Continue reading")
                        Text(book.title)
                            .font(TypographyTokens.headline)
                            .foregroundStyle(BrandTokens.deepInk)
                            .lineLimit(2)
                        if let author = book.authorHint, !author.isEmpty {
                            Text(author)
                                .font(TypographyTokens.callout)
                                .foregroundStyle(BrandTokens.deepInk.opacity(0.7))
                                .lineLimit(1)
                        }

                        Spacer(minLength: SpacingTokens.xs)

                        ProgressBar(fraction: progressFraction(book))
                        Text(progressLabel(book))
                            .font(TypographyTokens.caption)
                            .foregroundStyle(BrandTokens.deepInk.opacity(0.65))

                        Button {
                            openBook(book)
                        } label: {
                            Label("Resume", systemImage: "book.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.flipbook(prominent: true))
                        .padding(.top, 2)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }
            } else {
                VStack(alignment: .leading, spacing: SpacingTokens.xs) {
                    cardCaption("Continue reading")
                    Text("Your library is empty")
                        .font(TypographyTokens.headline)
                        .foregroundStyle(BrandTokens.deepInk)
                    Text("Import a PDF to start your first book.")
                        .font(TypographyTokens.callout)
                        .foregroundStyle(BrandTokens.deepInk.opacity(0.7))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Right rail

    private func cardCaption(_ text: String) -> some View {
        Text(text)
            .font(TypographyTokens.caption.weight(.semibold))
            .foregroundStyle(BrandTokens.espresso.opacity(0.75))
            .textCase(.uppercase)
            .kerning(0.6)
    }

    /// Purely typographic stat card: quiet caption, one big accent number, unit after it.
    private func statCard(caption: String, number: String, unit: String, tint: Color) -> some View {
        DashboardCard(tint: tint) {
            VStack(alignment: .leading, spacing: SpacingTokens.xs) {
                cardCaption(caption)
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(number)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(BrandTokens.espresso)
                        .monospacedDigit()
                    if !unit.isEmpty {
                        Text(unit)
                            .font(TypographyTokens.callout)
                            .foregroundStyle(BrandTokens.deepInk.opacity(0.6))
                    }
                }
            }
        }
    }

    /// Minutes today, with progress toward the user's daily goal when one is set.
    private var todayCard: some View {
        let goal = appModel.settings.dailyGoalMinutes
        return DashboardCard(tint: BrandTokens.tileToast) {
            VStack(alignment: .leading, spacing: SpacingTokens.xs) {
                cardCaption(appModel.isReading ? "Reading now" : "Today")
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(appModel.isReading ? liveTimer : "\(minutesToday)")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(BrandTokens.espresso)
                        .monospacedDigit()
                    Text(goal > 0 ? "of \(goal) min" : (appModel.isReading ? "" : "min"))
                        .font(TypographyTokens.callout)
                        .foregroundStyle(BrandTokens.deepInk.opacity(0.6))
                }
                if goal > 0 {
                    ProgressBar(fraction: min(1, Double(minutesToday) / Double(goal)))
                        .padding(.top, 2)
                }
            }
        }
    }

    /// Library totals as ledger rows in a single card — one tile instead of a pastel salad.
    private var libraryCard: some View {
        DashboardCard(tint: BrandTokens.tileCream) {
            VStack(alignment: .leading, spacing: 0) {
                cardCaption("Library")
                Spacer(minLength: SpacingTokens.sm)
                libraryRow("Books", count: books.count)
                ledgerDivider
                libraryRow("Finished", count: finishedCount)
                ledgerDivider
                libraryRow("Favourites", count: books.count(where: { $0.isFavorite }))
            }
        }
    }

    private var ledgerDivider: some View {
        Rectangle()
            .fill(BrandTokens.deepInk.opacity(0.08))
            .frame(height: 1)
            .padding(.vertical, SpacingTokens.sm)
    }

    private func libraryRow(_ label: String, count: Int) -> some View {
        HStack {
            Text(label)
                .font(TypographyTokens.callout)
                .foregroundStyle(BrandTokens.deepInk.opacity(0.75))
            Spacer(minLength: SpacingTokens.sm)
            Text("\(count)")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(BrandTokens.espresso)
                .monospacedDigit()
        }
    }

    private var liveTimer: String {
        let total = Int(appModel.liveSessionSeconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: - Week chart

    private var weekCard: some View {
        DashboardCard(tint: BrandTokens.tileLatte) {
            VStack(alignment: .leading, spacing: SpacingTokens.sm) {
                HStack(alignment: .firstTextBaseline) {
                    cardCaption("This week")
                    Spacer()
                    Text("\(weekTotalMinutes)")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(BrandTokens.espresso)
                        .monospacedDigit()
                    + Text(" min")
                        .font(TypographyTokens.caption)
                        .foregroundStyle(BrandTokens.deepInk.opacity(0.6))
                }

                // The chart flexes to whatever height the card gets, so the bars always
                // fill the tile with no leftover band below.
                GeometryReader { geo in
                    let maxMinutes = max(weekDays.map(\.minutes).max() ?? 0, 1)
                    let barArea = max(geo.size.height - 40, 20)
                    HStack(alignment: .bottom, spacing: SpacingTokens.sm) {
                        ForEach(weekDays) { day in
                            weekBar(day, maxMinutes: maxMinutes, barArea: barArea)
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .bottom)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(BrandTokens.deepInk.opacity(0.12))
                            .frame(height: 1)
                            .padding(.bottom, 17)
                    }
                }
            }
        }
    }

    /// Monochrome bars: muted espresso for past days, full accent for today.
    private func weekBar(_ day: ReadingStats.DaySlice, maxMinutes: Int, barArea: CGFloat) -> some View {
        let fraction = CGFloat(day.minutes) / CGFloat(maxMinutes)
        let fullHeight = max(3, fraction * barArea)

        return VStack(spacing: 4) {
            Text("\(day.minutes)")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(BrandTokens.deepInk.opacity(day.minutes > 0 ? 0.8 : 0.28))
                .monospacedDigit()
            UnevenRoundedRectangle(topLeadingRadius: 5, topTrailingRadius: 5, style: .continuous)
                .fill(day.isToday ? BrandTokens.espresso : BrandTokens.espresso.opacity(0.32))
                .frame(height: animateChart ? fullHeight : 3)
                .frame(maxWidth: .infinity)
            Text(weekdayLetter(day.date))
                .font(.system(size: 10, weight: day.isToday ? .bold : .semibold, design: .rounded))
                .foregroundStyle(day.isToday ? BrandTokens.espresso : BrandTokens.deepInk.opacity(0.5))
                .frame(height: 12)
        }
    }

    private func weekdayLetter(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEEE"
        return f.string(from: date)
    }

    // MARK: - Recent strip

    @ViewBuilder
    private var recentStrip: some View {
        DashboardCard(tint: BrandTokens.tileToast) {
            VStack(alignment: .leading, spacing: SpacingTokens.sm) {
                cardCaption("Jump back in")
                if recentInProgress.isEmpty {
                    Text("Books you start will line up here.")
                        .font(TypographyTokens.callout)
                        .foregroundStyle(BrandTokens.deepInk.opacity(0.55))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: SpacingTokens.md) {
                            ForEach(recentInProgress.prefix(8)) { book in
                                VStack(alignment: .leading, spacing: SpacingTokens.xs) {
                                    BookCoverThumbnail(book: book)
                                        .frame(width: 68)
                                        .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
                                    Text(book.title)
                                        .font(TypographyTokens.caption)
                                        .foregroundStyle(BrandTokens.deepInk)
                                        .lineLimit(1)
                                        .frame(width: 68, alignment: .leading)
                                }
                                .onTapGesture { openBook(book) }
                            }
                        }
                    }
                }
            }
        }
        .frame(height: 168)
    }

    // MARK: - Helpers

    private func isFinished(_ book: Book) -> Bool {
        book.pageCount > 0 && (book.progress?.currentPageIndex ?? 0) >= book.pageCount - 1
    }

    private func progressFraction(_ book: Book) -> Double {
        guard book.pageCount > 0, let p = book.progress else { return 0 }
        return min(1, Double(p.currentPageIndex) / Double(max(book.pageCount - 1, 1)))
    }

    private func progressLabel(_ book: Book) -> String {
        let page = (book.progress?.currentPageIndex ?? 0) + 1
        return "Page \(page) of \(book.pageCount) · \(Int(progressFraction(book) * 100))%"
    }
}

// MARK: - Shared pieces

/// A rounded bento tile with a soft tinted fill and hairline border. Fills whatever slot the
/// grid gives it, so card edges in a row always align flush.
struct DashboardCard<Content: View>: View {
    let tint: Color
    var alignment: Alignment = .topLeading
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(SpacingTokens.md)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .background(
                RoundedRectangle(cornerRadius: SpacingTokens.cornerRadiusLarge, style: .continuous)
                    .fill(tint)
            )
            .overlay(
                RoundedRectangle(cornerRadius: SpacingTokens.cornerRadiusLarge, style: .continuous)
                    .strokeBorder(ColorTokens.creamHairline.opacity(0.25), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
    }
}

/// A thin reading-progress bar in the brand palette.
struct ProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(BrandTokens.espresso.opacity(0.15))
                Capsule().fill(BrandTokens.espresso)
                    .frame(width: max(6, geo.size.width * fraction))
            }
        }
        .frame(height: 6)
    }
}

/// Book cover (or a palette placeholder) at a 0.72 aspect, rounded.
struct BookCoverThumbnail: View {
    let book: Book

    var body: some View {
        Group {
            if let data = book.coverImageData, let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage).resizable()
            } else {
                RoundedRectangle(cornerRadius: SpacingTokens.cornerRadiusSmall, style: .continuous)
                    .fill(BrandTokens.emberGradient)
                    .overlay(
                        Image(systemName: "book.closed.fill")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.85))
                    )
            }
        }
        .aspectRatio(0.72, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: SpacingTokens.cornerRadiusSmall, style: .continuous))
    }
}
