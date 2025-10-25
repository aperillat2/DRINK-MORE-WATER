import Foundation
import UserNotifications
#if os(iOS)
import UIKit
#endif

/// Centralized helper that owns scheduling the hourly reminders.
final class NotificationScheduler {
    static let shared = NotificationScheduler()

    private init() {}

    func requestAuthorization() async {
        let center = UNUserNotificationCenter.current()
        do {
            try await center.requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            print("Notification authorization failed: \(error)")
        }
    }

    /// Schedules notifications for the remainder of today and all of tomorrow.
    /// - Parameters:
    ///   - startHour: first hour (0-23) to allow notifications
    ///   - endHour: last hour (0-23) to allow notifications
    ///   - soundFile: bundle sound filename (e.g., "drink more water.caf")
    ///   - lastDrinkDate: if provided, first notification is 1 hour after this time (clamped to window)
    func scheduleForTodayAndTomorrow(startHour: Int, endHour: Int, soundFile: String, lastDrinkDate: Date?) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        #if os(iOS)
        if #available(iOS 17.0, *) {
            center.setBadgeCount(0) { _ in }
        } else {
            DispatchQueue.main.async { UIApplication.shared.applicationIconBadgeNumber = 0 }
        }
        #endif

        let calendar = Calendar.current
        let now = Date()

        func hourlyTimes(for day: Date) -> [Date] {
            guard let start = calendar.date(bySettingHour: startHour, minute: 0, second: 0, of: day),
                  let end = calendar.date(bySettingHour: endHour, minute: 0, second: 0, of: day) else { return [] }
            var times: [Date] = []
            var t = start
            while t <= end {
                times.append(t)
                t = calendar.date(byAdding: .hour, value: 1, to: t) ?? t.addingTimeInterval(3600)
            }
            return times
        }

        let windowStart = calendar.date(bySettingHour: startHour, minute: 0, second: 0, of: now)
        let windowEnd = calendar.date(bySettingHour: endHour, minute: 0, second: 0, of: now)

        func clampedFirstReminder() -> Date? {
            guard let lastDrinkDate else { return nil }
            let candidate = lastDrinkDate.addingTimeInterval(3600)
            guard let windowStart, let windowEnd else { return nil }
            if candidate < windowStart { return windowStart }
            if candidate > windowEnd { return nil }
            return candidate
        }

        let firstFromDrink = clampedFirstReminder()
        let todayTimes = hourlyTimes(for: now)

        let filteredToday: [Date] = {
            if let first = firstFromDrink {
                var result: [Date] = [first]
                var next = calendar.nextDate(after: first, matching: DateComponents(minute: 0, second: 0), matchingPolicy: .strict, direction: .forward) ?? first.addingTimeInterval(3600)
                while let end = windowEnd, next <= end {
                    if next > first { result.append(next) }
                    next = calendar.date(byAdding: .hour, value: 1, to: next) ?? next.addingTimeInterval(3600)
                }
                return result.filter { $0 > now }
            } else {
                return todayTimes.filter { $0 > now }
            }
        }()

        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(86400)
        let tomorrowTimes = hourlyTimes(for: tomorrow)

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

        let resolvedName = resolveSoundFilename(baseName: soundFile)
        let sound: UNNotificationSound? = {
            if let name = resolvedName {
                return UNNotificationSound(named: UNNotificationSoundName(name))
            }
            return .default
        }()

        func makeContent(badge: Int) -> UNMutableNotificationContent {
            let content = UNMutableNotificationContent()
            content.title = "Drink more water"
            content.body = "Tap the glass when you've had a drink."
            content.sound = sound
            content.badge = NSNumber(value: badge)
            return content
        }

        var badgeCount = 0
        func schedule(date: Date, id: String) {
            badgeCount += 1
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: id, content: makeContent(badge: badgeCount), trigger: trigger)
            center.add(request)
        }

        for (index, time) in filteredToday.enumerated() {
            schedule(date: time, id: "today_\(index)")
        }
        for (index, time) in tomorrowTimes.enumerated() {
            schedule(date: time, id: "tomorrow_\(index)")
        }
    }
}
