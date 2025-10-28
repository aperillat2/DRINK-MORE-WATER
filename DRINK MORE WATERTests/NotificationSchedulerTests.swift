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

    @Test("schedules hourly reminders after now when no last drink", arguments: [
        ("2000-01-01T07:30:00Z", 7, 9, [8, 9], [7, 8, 9])
    ])
    func scheduleWithoutLastDrink(nowString: String, startHour: Int, endHour: Int, expectedTodayHours: [Int], expectedTomorrowHours: [Int]) async throws {
        let nowDate = date(nowString)
        let fakeCenter = FakeUserNotificationCenter()
        let scheduler = NotificationScheduler(
            centerProvider: { fakeCenter },
            calendar: calendar,
            now: { nowDate }
        )

        scheduler.scheduleForTodayAndTomorrow(startHour: startHour, endHour: endHour, soundFile: "sound", lastDrinkDate: nil)

        #expect(fakeCenter.removedPending == true)
        let scheduled = try #require(fakeCenter.requests)
        let today = scheduled.filter { $0.identifier.hasPrefix("today_") }
        let tomorrow = scheduled.filter { $0.identifier.hasPrefix("tomorrow_") }

        let todayHours = today.compactMap { hour(from: $0) }
        let tomorrowHours = tomorrow.compactMap { hour(from: $0) }
        #expect(todayHours == expectedTodayHours)
        #expect(tomorrowHours == expectedTomorrowHours)
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

        scheduler.scheduleForTodayAndTomorrow(startHour: 7, endHour: 9, soundFile: "sound", lastDrinkDate: lastDrink)

        let scheduled = try #require(fakeCenter.requests)
        let today = scheduled.filter { $0.identifier.hasPrefix("today_") }
        let firstTriggerHour = today.first.flatMap { hour(from: $0) }
        #expect(firstTriggerHour == 7)
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

        scheduler.scheduleForTomorrow(startHour: 7, endHour: 9, soundFile: "sound")

        #expect(fakeCenter.removedPending == true)
        #expect(fakeCenter.badgeResetCount == 1)
        let scheduled = try #require(fakeCenter.requests)
        let today = scheduled.filter { $0.identifier.hasPrefix("today_") }
        let tomorrow = scheduled.filter { $0.identifier.hasPrefix("tomorrow_") }
        #expect(today.isEmpty)
        let hours = tomorrow.compactMap { hour(from: $0) }
        #expect(hours == [7, 8, 9])
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

private func hour(from request: UNNotificationRequest) -> Int? {
    guard let trigger = request.trigger as? UNCalendarNotificationTrigger else { return nil }
    return trigger.dateComponents.hour
}
