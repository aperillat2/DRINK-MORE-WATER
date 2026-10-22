import Foundation
import UIKit
import UserNotifications

protocol NotificationScheduling {
    func requestAuthorization() async
    func scheduleForTodayAndTomorrow(startHour: Int, endHour: Int, intervalMinutes: Int, soundFile: String, lastDrinkDate: Date?)
    func scheduleForTomorrow(startHour: Int, endHour: Int, intervalMinutes: Int, soundFile: String)
    func cancelAll()
    /// Clears the app icon badge without touching scheduled reminders.
    func clearBadge()
}

protocol UserNotificationCentering {
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func removeAllPendingNotificationRequests()
    func add(_ request: UNNotificationRequest)
    func resetBadge()
}

struct DefaultUserNotificationCenter: UserNotificationCentering {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        try await center.requestAuthorization(options: options)
    }

    func removeAllPendingNotificationRequests() {
        center.removeAllPendingNotificationRequests()
    }

    func add(_ request: UNNotificationRequest) {
        center.add(request)
    }

    func resetBadge() {
        if #available(iOS 17.0, *) {
            center.setBadgeCount(0) { _ in }
        } else {
            DispatchQueue.main.async { UIApplication.shared.applicationIconBadgeNumber = 0 }
        }
    }
}

/// Centralized helper that owns scheduling the hourly reminders.
final class NotificationScheduler: NotificationScheduling {
    static let shared: NotificationScheduling = NotificationScheduler()

    /// iOS keeps at most 64 pending local notifications per app and drops the rest,
    /// so never submit more than this (earliest first).
    static let maxPendingNotifications = 64

    /// Number of days after today to pre-schedule (tomorrow plus 6 more), so reminders
    /// keep coming for a week even if the app isn't opened. Each launch/tap reschedules.
    static let futureDaysToSchedule = 7

    private let centerProvider: () -> UserNotificationCentering
    private let calendar: Calendar
    private let now: () -> Date

    init(
        centerProvider: @escaping () -> UserNotificationCentering = { DefaultUserNotificationCenter() },
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.centerProvider = centerProvider
        self.calendar = calendar
        self.now = now
    }

    func requestAuthorization() async {
        let center = centerProvider()
        do {
            _ = try await center.requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            print("Notification authorization failed: \(error)")
        }
    }

    /// Schedules notifications for the remainder of today, tomorrow, and the following days
    /// (up to `futureDaysToSchedule` days and `maxPendingNotifications` total).
    /// - Parameters:
    ///   - startHour: first hour (0-23) to allow notifications
    ///   - endHour: last hour (0-23) to allow notifications
    ///   - intervalMinutes: spacing between notifications in minutes (0 = once per day, otherwise minimum 1)
    ///   - soundFile: bundle sound filename (e.g., "drink more water.caf")
    ///   - lastDrinkDate: if provided, first notification is intervalMinutes after this time (clamped to window)
    func scheduleForTodayAndTomorrow(startHour: Int, endHour: Int, intervalMinutes: Int, soundFile: String, lastDrinkDate: Date?) {
        let center = centerProvider()
        center.removeAllPendingNotificationRequests()
        center.resetBadge()

        let today = now()
        if intervalMinutes < 0 {
            return
        }
        let minuteStep = intervalMinutes > 0 ? intervalMinutes : 0
        let intervalSeconds: TimeInterval = minuteStep > 0 ? TimeInterval(minuteStep * 60) : 24 * 60 * 60

        let windowStart = calendar.date(bySettingHour: startHour, minute: 0, second: 0, of: today)
        let windowEnd = calendar.date(bySettingHour: endHour, minute: 0, second: 0, of: today)

        func alignDailyReminder(_ date: Date) -> Date? {
            guard let dayStart = calendar.date(bySettingHour: startHour, minute: 0, second: 0, of: date),
                  let dayEnd = calendar.date(bySettingHour: endHour, minute: 0, second: 0, of: date),
                  dayStart <= dayEnd else { return nil }
            if date < dayStart { return dayStart }
            if date > dayEnd {
                guard let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return nil }
                return calendar.date(bySettingHour: startHour, minute: 0, second: 0, of: nextDay)
            }
            let comps = calendar.dateComponents([.hour, .minute], from: date)
            return calendar.date(bySettingHour: comps.hour ?? startHour, minute: comps.minute ?? 0, second: 0, of: date)
        }

        func clampedFirstReminder() -> Date? {
            guard let lastDrinkDate else { return nil }
            let candidate = lastDrinkDate.addingTimeInterval(intervalSeconds)
            if minuteStep == 0 {
                return alignDailyReminder(candidate)
            }
            guard let windowStart, let windowEnd else { return nil }
            if candidate < windowStart { return windowStart }
            if candidate > windowEnd { return nil }
            return candidate
        }

        let firstFromDrink = clampedFirstReminder()
        let todayTimes = dailySlots(for: today, startHour: startHour, endHour: endHour, minuteStep: minuteStep)

        let filteredToday: [Date] = {
            guard let windowEnd else { return todayTimes.filter { $0 > today } }
            if minuteStep == 0 {
                if let first = firstFromDrink, calendar.isDate(first, inSameDayAs: today), first > today {
                    return [first]
                }
                return todayTimes.filter { $0 > today }
            }
            if let first = firstFromDrink {
                var result: [Date] = []
                if first > today { result.append(first) }
                var next = first
                while true {
                    let candidate = calendar.date(byAdding: .minute, value: minuteStep, to: next) ?? next.addingTimeInterval(intervalSeconds)
                    if candidate == next { break }
                    next = candidate
                    if next > windowEnd { break }
                    if next > today { result.append(next) }
                }
                return result
            } else {
                return todayTimes.filter { $0 > today }
            }
        }()

        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(86400)
        let tomorrowTimes: [Date] = {
            if minuteStep == 0, let first = firstFromDrink {
                if calendar.isDate(first, inSameDayAs: tomorrow) {
                    return [first]
                }
                if calendar.isDate(first, inSameDayAs: today),
                   let next = alignDailyReminder(first.addingTimeInterval(intervalSeconds)),
                   calendar.isDate(next, inSameDayAs: tomorrow) {
                    return [next]
                }
            }
            return dailySlots(for: tomorrow, startHour: startHour, endHour: endHour, minuteStep: minuteStep)
        }()

        let groups = [("today", filteredToday), ("tomorrow", tomorrowTimes)]
            + laterDays(after: tomorrow, tomorrowTimes: tomorrowTimes, startHour: startHour, endHour: endHour, minuteStep: minuteStep)
        submit(groups, soundFile: soundFile, to: center)
    }

    func cancelAll() {
        let center = centerProvider()
        center.removeAllPendingNotificationRequests()
        center.resetBadge()
    }

    func clearBadge() {
        centerProvider().resetBadge()
    }

    /// Schedules nothing for today; starts with tomorrow (used once today's goal is met).
    /// - Parameters:
    ///   - startHour: first hour (0-23) to allow notifications
    ///   - endHour: last hour (0-23) to allow notifications
    ///   - intervalMinutes: spacing between notifications in minutes (0 = once per day, otherwise minimum 1)
    ///   - soundFile: bundle sound filename (e.g., "drink more water.caf")
    func scheduleForTomorrow(startHour: Int, endHour: Int, intervalMinutes: Int, soundFile: String) {
        let center = centerProvider()
        center.removeAllPendingNotificationRequests()
        center.resetBadge()

        let today = now()
        if intervalMinutes < 0 {
            return
        }
        let minuteStep = intervalMinutes > 0 ? intervalMinutes : 0
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(86400)
        let tomorrowTimes = dailySlots(for: tomorrow, startHour: startHour, endHour: endHour, minuteStep: minuteStep)

        let groups = [("tomorrow", tomorrowTimes)]
            + laterDays(after: tomorrow, tomorrowTimes: tomorrowTimes, startHour: startHour, endHour: endHour, minuteStep: minuteStep)
        submit(groups, soundFile: soundFile, to: center)
    }
}

private extension NotificationScheduler {
    /// Reminder times for one day: start hour, then every `minuteStep` minutes up to the end hour.
    /// Once-a-day mode (`minuteStep == 0`) returns just the start hour.
    func dailySlots(for day: Date, startHour: Int, endHour: Int, minuteStep: Int) -> [Date] {
        guard let start = calendar.date(bySettingHour: startHour, minute: 0, second: 0, of: day),
              let end = calendar.date(bySettingHour: endHour, minute: 0, second: 0, of: day),
              start <= end else { return [] }
        if minuteStep == 0 {
            return [start]
        }
        var slots: [Date] = []
        var t = start
        while t <= end {
            slots.append(t)
            let next = calendar.date(byAdding: .minute, value: minuteStep, to: t) ?? t.addingTimeInterval(TimeInterval(minuteStep * 60))
            if next == t { break }
            t = next
        }
        return slots
    }

    /// Reminder groups for the days after tomorrow, identified as "day2", "day3", ...
    /// In once-a-day mode they reuse tomorrow's time of day so the daily reminder stays consistent.
    func laterDays(after tomorrow: Date, tomorrowTimes: [Date], startHour: Int, endHour: Int, minuteStep: Int) -> [(String, [Date])] {
        guard Self.futureDaysToSchedule > 1 else { return [] }
        return (1..<Self.futureDaysToSchedule).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: tomorrow) else { return nil }
            let times: [Date]
            if minuteStep == 0, let tomorrowTime = tomorrowTimes.first {
                let comps = calendar.dateComponents([.hour, .minute], from: tomorrowTime)
                times = calendar.date(bySettingHour: comps.hour ?? startHour, minute: comps.minute ?? 0, second: 0, of: day).map { [$0] } ?? []
            } else {
                times = dailySlots(for: day, startHour: startHour, endHour: endHour, minuteStep: minuteStep)
            }
            return ("day\(offset + 1)", times)
        }
    }

    /// Adds the requests in order, stopping at the iOS pending-notification limit
    /// so the earliest reminders are always the ones kept.
    func submit(_ groups: [(String, [Date])], soundFile: String, to center: UserNotificationCentering) {
        let sound = notificationSound(for: soundFile)
        var remaining = Self.maxPendingNotifications

        for (prefix, times) in groups {
            for (index, time) in times.enumerated() {
                guard remaining > 0 else { return }
                let content = UNMutableNotificationContent()
                content.title = "Drink more water"
                content.body = "Tap the glass when you've had a drink."
                content.sound = sound
                // A plain "1" means "you have a reminder". A running count would keep climbing
                // across days because it can't know which earlier reminders were seen.
                content.badge = 1

                let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: time)
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                center.add(UNNotificationRequest(identifier: "\(prefix)_\(index)", content: content, trigger: trigger))
                remaining -= 1
            }
        }
    }

    func notificationSound(for soundFile: String) -> UNNotificationSound? {
        // Empty selection means no sound
        if soundFile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return nil
        }
        if let name = resolveSoundFilename(baseName: soundFile) {
            return UNNotificationSound(named: UNNotificationSoundName(name))
        }
        return .default
    }

    func resolveSoundFilename(baseName: String) -> String? {
        guard !baseName.isEmpty else { return nil }
        let fm = FileManager.default
        let exts = ["caf", "aiff", "wav"]

        func search(in path: String) -> String? {
            guard let items = try? fm.contentsOfDirectory(atPath: path) else { return nil }
            for ext in exts {
                if let match = items.first(where: { ($0 as NSString).deletingPathExtension.caseInsensitiveCompare(baseName) == .orderedSame && ($0 as NSString).pathExtension.lowercased() == ext }) {
                    return match
                }
            }
            if let any = items.first(where: { ($0 as NSString).deletingPathExtension.caseInsensitiveCompare(baseName) == .orderedSame }) {
                return any
            }
            return nil
        }

        if let base = Bundle.main.resourcePath {
            let soundsPath = (base as NSString).appendingPathComponent("Sounds")
            if let fromSounds = search(in: soundsPath) { return fromSounds }
            if let fromRoot = search(in: base) { return fromRoot }
        }
        return nil
    }
}
