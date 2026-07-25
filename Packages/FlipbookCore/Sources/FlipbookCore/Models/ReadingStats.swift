import Foundation
import SwiftData

/// Read-side helpers over the `ReadingDay` history: today's time, the current streak, and a
/// trailing-week series for the dashboard. All pure given a set of days.
public enum ReadingStats {
    public struct DaySlice: Identifiable, Sendable {
        public let id: String
        public let date: Date
        public let minutes: Int
        public let isToday: Bool
    }

    /// Seconds recorded for `date` (0 if none).
    public static func seconds(on date: Date, in days: [ReadingDay]) -> Double {
        let key = ReadingDay.key(for: date)
        return days.first(where: { $0.dayKey == key })?.seconds ?? 0
    }

    public static func minutesToday(in days: [ReadingDay], now: Date = .now) -> Int {
        Int(seconds(on: now, in: days) / 60)
    }

    /// Consecutive days ending today (or yesterday, so a not-yet-read today doesn't reset it)
    /// with at least `threshold` seconds read.
    public static func currentStreak(
        in days: [ReadingDay],
        now: Date = .now,
        threshold: Double = 60,
        calendar: Calendar = .current
    ) -> Int {
        let keys = Set(days.filter { $0.seconds >= threshold }.map(\.dayKey))
        guard !keys.isEmpty else { return 0 }

        // Anchor: today if it counts, else yesterday (so an unread today doesn't break a run).
        var cursor = calendar.startOfDay(for: now)
        if !keys.contains(ReadingDay.key(for: cursor, calendar: calendar)) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) else { return 0 }
            cursor = yesterday
        }

        var streak = 0
        while keys.contains(ReadingDay.key(for: cursor, calendar: calendar)) {
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return streak
    }

    /// The trailing `count` days (oldest → newest), each with its minutes, for a bar strip.
    public static func recentDays(
        in days: [ReadingDay],
        count: Int = 7,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [DaySlice] {
        let today = calendar.startOfDay(for: now)
        let todayKey = ReadingDay.key(for: today, calendar: calendar)
        return (0..<count).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let key = ReadingDay.key(for: date, calendar: calendar)
            let seconds = days.first(where: { $0.dayKey == key })?.seconds ?? 0
            return DaySlice(id: key, date: date, minutes: Int(seconds / 60), isToday: key == todayKey)
        }
    }

    public static func totalMinutes(in days: [ReadingDay]) -> Int {
        Int(days.reduce(0) { $0 + $1.seconds } / 60)
    }
}
