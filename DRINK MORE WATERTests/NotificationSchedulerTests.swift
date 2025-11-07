import Foundation
import Testing
import UserNotifications
@testable import DRINK_MORE_WATER

@MainActor
@Suite("NotificationScheduler")
struct NotificationSchedulerTests {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    private func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    @Test("schedules reminders after now using selected interval", arguments: [
        ("2000-01-01T07:30:00Z", 7, 9, 60, [(8, 0), (9, 0)], [(7, 0), (8, 0), (9, 0)]),
        ("2000-01-01T07:10:00Z", 7, 9, 30, [(7, 30), (8, 0), (8, 30), (9, 0)], [(7, 0), (7, 30), (8, 0), (8, 30), (9, 0)]),
        ("2000-01-01T07:10:00Z", 7, 9, 0, [], [(7, 0)])
    ])
    func scheduleWithoutLastDrink(nowString: String, startHour: Int, endHour: Int, intervalMinutes: Int, expectedTodayTimes: [(Int, Int)], expectedTomorrowTimes: [(Int, Int)]) async throws {
        let nowDate = date(nowString)
        let fakeCenter = FakeUserNotificationCenter()
        let scheduler = NotificationScheduler(
            centerProvider: { fakeCenter },
            calendar: calendar,
            now: { nowDate }
        )

        scheduler.scheduleForTodayAndTomorrow(startHour: startHour, endHour: endHour, intervalMinutes: intervalMinutes, soundFile: "sound", lastDrinkDate: nil)

        #expect(fakeCenter.removedPending == true)
        let scheduled = try #require(fakeCenter.requests)
        let today = scheduled.filter { $0.identifier.hasPrefix("today_") }
        let tomorrow = scheduled.filter { $0.identifier.hasPrefix("tomorrow_") }

        let todayTimes = today.compactMap { timeComponents(from: $0) }
        let tomorrowTimes = tomorrow.compactMap { timeComponents(from: $0) }
        #expect(formattedTimes(todayTimes) == formattedTimes(expectedTodayTimes))
        #expect(formattedTimes(tomorrowTimes) == formattedTimes(expectedTomorrowTimes))
    }

    @Test("uses window start when last drink is before notification window")
    func scheduleClampsLastDrink() async throws {
        let nowDate = date("2000-01-01T06:15:00Z")
        let lastDrink = date("2000-01-01T05:45:00Z")
        let fakeCenter = FakeUserNotificationCenter()
        let scheduler = NotificationScheduler(
            centerProvider: { fakeCenter },
            calendar: calendar,
            now: { nowDate }
        )

        scheduler.scheduleForTodayAndTomorrow(startHour: 7, endHour: 9, intervalMinutes: 60, soundFile: "sound", lastDrinkDate: lastDrink)

        let scheduled = try #require(fakeCenter.requests)
        let today = scheduled.filter { $0.identifier.hasPrefix("today_") }
        let firstTrigger = today.first.flatMap { timeComponents(from: $0) }
        #expect(formattedTime(firstTrigger) == Optional("07:00"))
    }

    @Test("daily reminders schedule 24h after last drink within window")
    func scheduleDailyUsesLastDrink() async throws {
        let nowDate = date("2000-01-01T10:00:00Z")
        let lastDrink = date("2000-01-01T08:15:00Z")
        let fakeCenter = FakeUserNotificationCenter()
        let scheduler = NotificationScheduler(
            centerProvider: { fakeCenter },
            calendar: calendar,
            now: { nowDate }
        )

        scheduler.scheduleForTodayAndTomorrow(startHour: 7, endHour: 21, intervalMinutes: 0, soundFile: "sound", lastDrinkDate: lastDrink)

        let scheduled = try #require(fakeCenter.requests)
        let today = scheduled.filter { $0.identifier.hasPrefix("today_") }
        let tomorrow = scheduled.filter { $0.identifier.hasPrefix("tomorrow_") }
        #expect(today.isEmpty)
        let tomorrowTimes = tomorrow.compactMap { timeComponents(from: $0) }
        #expect(formattedTimes(tomorrowTimes) == ["08:15"])
    }

    @Test("scheduleForTomorrow clears pending and only schedules tomorrow")
    func scheduleForTomorrowOnlySchedulesNextDay() async throws {
        let nowDate = date("2000-01-01T12:00:00Z")
        let fakeCenter = FakeUserNotificationCenter()
        let scheduler = NotificationScheduler(
            centerProvider: { fakeCenter },
            calendar: calendar,
            now: { nowDate }
        )

        scheduler.scheduleForTomorrow(startHour: 7, endHour: 9, intervalMinutes: 60, soundFile: "sound")

        #expect(fakeCenter.removedPending == true)
        #expect(fakeCenter.badgeResetCount == 1)
        let scheduled = try #require(fakeCenter.requests)
        let today = scheduled.filter { $0.identifier.hasPrefix("today_") }
        let tomorrow = scheduled.filter { $0.identifier.hasPrefix("tomorrow_") }
        #expect(today.isEmpty)
        let times = tomorrow.compactMap { timeComponents(from: $0) }
        #expect(formattedTimes(times) == ["07:00", "08:00", "09:00"])
    }
}

private final class FakeUserNotificationCenter: UserNotificationCentering {
    private(set) var authorizationOptions: UNAuthorizationOptions?
    private(set) var removedPending = false
    private(set) var badgeResetCount = 0
    private(set) var storedRequests: [UNNotificationRequest] = []

    var requests: [UNNotificationRequest]? { storedRequests.isEmpty ? nil : storedRequests }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        authorizationOptions = options
        return true
    }

    func removeAllPendingNotificationRequests() {
        removedPending = true
        storedRequests.removeAll()
    }

    func add(_ request: UNNotificationRequest) {
        storedRequests.append(request)
    }

    func resetBadge() {
        badgeResetCount += 1
    }
}

private func timeComponents(from request: UNNotificationRequest) -> (Int, Int)? {
    guard let trigger = request.trigger as? UNCalendarNotificationTrigger else { return nil }
    guard let hour = trigger.dateComponents.hour, let minute = trigger.dateComponents.minute else { return nil }
    return (hour, minute)
}

private func formattedTimes(_ times: [(Int, Int)]) -> [String] {
    times.map(formattedTime)
}

private func formattedTime(_ time: (Int, Int)) -> String {
    String(format: "%02d:%02d", time.0, time.1)
}

private func formattedTime(_ time: (Int, Int)?) -> String? {
    time.map(formattedTime)
}
