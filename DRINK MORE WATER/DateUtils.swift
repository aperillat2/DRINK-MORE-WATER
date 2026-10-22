import Foundation

enum DateUtils {
    static let dayFormatter: DateFormatter = makeDayFormatter(calendar: .current)

    static func todayString() -> String {
        dayString(for: Date())
    }

    /// "yyyy-MM-dd" key for the day containing `date`. Used to detect when a new day starts.
    static func dayString(for date: Date, calendar: Calendar = .current) -> String {
        let formatter = calendar == .current ? dayFormatter : makeDayFormatter(calendar: calendar)
        return formatter.string(from: date)
    }

    private static func makeDayFormatter(calendar: Calendar) -> DateFormatter {
        let df = DateFormatter()
        df.calendar = calendar
        df.locale = .current
        df.timeZone = calendar.timeZone
        df.dateFormat = "yyyy-MM-dd"
        return df
    }
}
