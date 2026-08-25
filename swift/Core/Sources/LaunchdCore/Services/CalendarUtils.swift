import Foundation

/// Schedule formatting and next-run projection for StartCalendarInterval.
/// Mirrors src/lib/calendar-utils.ts.
public enum CalendarUtils {
    public static let weekdayLabels = [
        "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday",
    ]

    public struct HourRange {
        public var base: CalendarInterval
        public var from: Int
        public var to: Int
    }

    /// Detects a contiguous hour range sharing the same minute/weekday/day/month, so
    /// "9,10,11,12" renders as "9:00–12:00" instead of four separate lines.
    public static func detectHourRange(_ intervals: [CalendarInterval]) -> HourRange? {
        guard intervals.count >= 2, let first = intervals.first else { return nil }

        let allSameBase = intervals.allSatisfy {
            $0.minute == first.minute && $0.weekday == first.weekday
                && $0.day == first.day && $0.month == first.month && $0.hour != nil
        }
        guard allSameBase else { return nil }

        let hours = intervals.compactMap(\.hour).sorted()
        for i in 1..<hours.count where hours[i] != hours[i - 1] + 1 { return nil }

        return HourRange(
            base: CalendarInterval(
                minute: first.minute, hour: nil, day: first.day,
                weekday: first.weekday, month: first.month),
            from: hours[0],
            to: hours[hours.count - 1]
        )
    }

    /// Expands a base interval across an inclusive hour range.
    public static func expandHourRange(base: CalendarInterval, from: Int, to: Int) -> [CalendarInterval] {
        guard from <= to else { return [] }
        return (from...to).map { hour in
            var ci = base
            ci.hour = hour
            return ci
        }
    }

    private static func cadence(_ ci: CalendarInterval) -> String {
        if let weekday = ci.weekday, weekdayLabels.indices.contains(weekday) {
            return "Every \(weekdayLabels[weekday])"
        }
        if let day = ci.day { return "Day \(day) of each month" }
        if let month = ci.month { return "Month \(month)" }
        return "Every day"
    }

    private static func pad(_ n: Int) -> String { String(format: "%02d", n) }

    public static func formatSingle(_ ci: CalendarInterval) -> String {
        let minute = ci.minute ?? 0
        guard let hour = ci.hour else {
            return "\(cadence(ci)) every hour at :\(pad(minute))"
        }
        return "\(cadence(ci)) at \(pad(hour)):\(pad(minute))"
    }

    public static func format(_ intervals: [CalendarInterval]) -> String {
        if let range = detectHourRange(intervals) {
            let minute = pad(range.base.minute ?? 0)
            return "\(cadence(range.base)) at :\(minute) (\(range.from):00–\(range.to):00)"
        }
        return intervals.map(formatSingle).joined(separator: ", ")
    }

    /// Next `count` firings of one interval, scanned minute by minute the way the
    /// TypeScript original did (bounded to ~400 days so an impossible spec terminates).
    public static func nextOccurrences(_ ci: CalendarInterval, count: Int) -> [Date] {
        var results: [Date] = []
        let calendar = Calendar.current
        var candidate = calendar.date(
            bySetting: .second, value: 0, of: Date()) ?? Date()
        candidate = calendar.date(byAdding: .minute, value: 1, to: candidate) ?? candidate

        let limit = 400 * 24 * 60
        var i = 0
        while i < limit && results.count < count {
            let parts = calendar.dateComponents(
                [.month, .day, .weekday, .hour, .minute], from: candidate)
            let matches =
                (ci.month == nil || parts.month == ci.month)
                && (ci.day == nil || parts.day == ci.day)
                // Calendar.weekday is 1-based (Sunday == 1); launchd's Weekday is 0-based.
                && (ci.weekday == nil || (parts.weekday.map { $0 - 1 }) == ci.weekday)
                && (ci.hour == nil || parts.hour == ci.hour)
                && (ci.minute == nil || parts.minute == ci.minute)

            if matches { results.append(candidate) }
            candidate = calendar.date(byAdding: .minute, value: 1, to: candidate) ?? candidate
            i += 1
        }
        return results
    }

    public static func nextOccurrences(multi intervals: [CalendarInterval], count: Int) -> [Date] {
        var unique: Set<Date> = []
        for ci in intervals {
            unique.formUnion(nextOccurrences(ci, count: count))
        }
        return unique.sorted().prefix(count).map { $0 }
    }

    public static func formatDateTime(_ date: Date) -> String {
        let c = Calendar.current.dateComponents(
            [.month, .day, .weekday, .hour, .minute], from: date)
        let weekday = weekdayLabels[(c.weekday ?? 1) - 1]
        return "\(c.month ?? 0)/\(c.day ?? 0) (\(weekday)) \(pad(c.hour ?? 0)):\(pad(c.minute ?? 0))"
    }
}
