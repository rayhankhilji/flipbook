import Foundation
import SwiftData

/// One calendar day's accumulated reading time. Written by the app-wide reading timer, which
/// only advances while a book is actually open. Powers the dashboard's "minutes today",
/// streaks, and history.
@Model
public final class ReadingDay {
    /// `yyyy-MM-dd` in the user's current calendar — the unique per-day key.
    @Attribute(.unique) public var dayKey: String
    public var date: Date
    public var seconds: Double

    public init(dayKey: String, date: Date = .now, seconds: Double = 0) {
        self.dayKey = dayKey
        self.date = date
        self.seconds = seconds
    }

    public var minutes: Int { Int(seconds / 60) }

    /// Stable key for `date` in the current calendar.
    public static func key(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
