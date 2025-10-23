import Foundation

enum DateUtils {
    static let dayFormatter: DateFormatter = {
        let df = DateFormatter()
        df.calendar = .current
        df.locale = .current
        df.timeZone = .current
        df.dateFormat = "yyyy-MM-dd"
        return df
    }()

    static func todayString() -> String {
        dayFormatter.string(from: Date())
    }

    static func isToday(storedDayString: String) -> Bool {
        guard let date = dayFormatter.date(from: storedDayString) else { return false }
        return Calendar.current.isDateInToday(date)
    }
}
