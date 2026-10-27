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

    @Test("scheduleForTomorrow clears pending, skips today, and starts with tomorrow's times")
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

    @Test("never schedules more than the iOS limit, keeping the earliest reminders")
    func capsAtPendingLimit() throws {
        // Every 15 minutes from 7 AM to 8 PM is 53 reminders a day, so two days would be 106.
        let nowDate = date("2000-01-01T06:00:00Z")
        let fakeCenter = FakeUserNotificationCenter()
        let scheduler = makeScheduler(center: fakeCenter, now: nowDate)

        scheduler.scheduleForTodayAndTomorrow(startHour: 7, endHour: 20, intervalMinutes: 15, soundFile: "sound", lastDrinkDate: nil)

        let scheduled = try #require(fakeCenter.requests)
        #expect(scheduled.count == NotificationScheduler.maxPendingNotifications)

        let dates = scheduled.compactMap { triggerDate(from: $0) }
        #expect(dates.count == scheduled.count)
        #expect(dates == dates.sorted(), "Requests should be added earliest first")
        #expect(scheduled.filter { $0.identifier.hasPrefix("today_") }.count == 53)
        #expect(dates.first == date("2000-01-01T07:00:00Z"))
    }

    @Test("schedules reminders for the coming week, not just tomorrow")
    func schedulesFutureDays() throws {
        // After today's window has closed: nothing today, then 3 reminders a day for 7 days.
        let nowDate = date("2000-01-01T12:00:00Z")
        let fakeCenter = FakeUserNotificationCenter()
        let scheduler = makeScheduler(center: fakeCenter, now: nowDate)

        scheduler.scheduleForTodayAndTomorrow(startHour: 7, endHour: 9, intervalMinutes: 60, soundFile: "sound", lastDrinkDate: nil)

        let scheduled = try #require(fakeCenter.requests)
        #expect(scheduled.filter { $0.identifier.hasPrefix("today_") }.isEmpty)
        #expect(scheduled.count == 3 * NotificationScheduler.futureDaysToSchedule)

        let dates = scheduled.compactMap { triggerDate(from: $0) }
        #expect(dates.first == date("2000-01-02T07:00:00Z"))
        #expect(dates.last == date("2000-01-08T09:00:00Z"))
        #expect(Set(scheduled.map(\.identifier)).count == scheduled.count, "Identifiers must be unique")
    }

    @Test("scheduleForTomorrow also covers the following days")
    func scheduleForTomorrowCoversFutureDays() throws {
        let nowDate = date("2000-01-01T12:00:00Z")
        let fakeCenter = FakeUserNotificationCenter()
        let scheduler = makeScheduler(center: fakeCenter, now: nowDate)

        scheduler.scheduleForTomorrow(startHour: 7, endHour: 9, intervalMinutes: 60, soundFile: "sound")

        let scheduled = try #require(fakeCenter.requests)
        #expect(scheduled.count == 3 * NotificationScheduler.futureDaysToSchedule)
        #expect(triggerDate(from: scheduled[0]) == date("2000-01-02T07:00:00Z"))
    }

    @Test("once-a-day mode keeps the same time on later days")
    func dailyModeRepeatsTomorrowsTime() throws {
        let nowDate = date("2000-01-01T10:00:00Z")
        let lastDrink = date("2000-01-01T08:15:00Z")
        let fakeCenter = FakeUserNotificationCenter()
        let scheduler = makeScheduler(center: fakeCenter, now: nowDate)

        scheduler.scheduleForTodayAndTomorrow(startHour: 7, endHour: 21, intervalMinutes: 0, soundFile: "sound", lastDrinkDate: lastDrink)

        let scheduled = try #require(fakeCenter.requests)
        #expect(scheduled.count == NotificationScheduler.futureDaysToSchedule)
        let times = scheduled.compactMap { timeComponents(from: $0) }
        #expect(Set(formattedTimes(times)) == ["08:15"])
    }

    @Test("every reminder sets the badge to 1 instead of a running count")
    func badgeIsAlwaysOne() throws {
        let nowDate = date("2000-01-01T06:00:00Z")
        let fakeCenter = FakeUserNotificationCenter()
        let scheduler = makeScheduler(center: fakeCenter, now: nowDate)

        scheduler.scheduleForTodayAndTomorrow(startHour: 7, endHour: 20, intervalMinutes: 60, soundFile: "sound", lastDrinkDate: nil)

        let scheduled = try #require(fakeCenter.requests)
        #expect(scheduled.allSatisfy { $0.content.badge == 1 })
    }

    @Test("every reminder has the \"Log a drink\" button category")
    func remindersHaveLogDrinkCategory() throws {
        let nowDate = date("2000-01-01T06:00:00Z")
        let fakeCenter = FakeUserNotificationCenter()
        let scheduler = makeScheduler(center: fakeCenter, now: nowDate)

        scheduler.scheduleForTodayAndTomorrow(startHour: 7, endHour: 9, intervalMinutes: 60, soundFile: "sound", lastDrinkDate: nil)
        scheduler.scheduleForTomorrow(startHour: 7, endHour: 9, intervalMinutes: 60, soundFile: "sound")

        let scheduled = try #require(fakeCenter.requests)
        #expect(scheduled.allSatisfy { $0.content.categoryIdentifier == ReminderNotification.categoryID })
    }

    @Test("clearBadge resets the badge but keeps scheduled reminders")
    func clearBadgeKeepsReminders() throws {
        let nowDate = date("2000-01-01T06:00:00Z")
        let fakeCenter = FakeUserNotificationCenter()
        let scheduler = makeScheduler(center: fakeCenter, now: nowDate)

        scheduler.scheduleForTodayAndTomorrow(startHour: 7, endHour: 9, intervalMinutes: 60, soundFile: "sound", lastDrinkDate: nil)
        let countBefore = try #require(fakeCenter.requests).count
        let badgeResetsBefore = fakeCenter.badgeResetCount

        scheduler.clearBadge()

        #expect(fakeCenter.badgeResetCount == badgeResetsBefore + 1)
        #expect(fakeCenter.requests?.count == countBefore)
    }

    @Test("a start hour after the end hour schedules nothing instead of misbehaving")
    func invertedWindowSchedulesNothing() {
        let nowDate = date("2000-01-01T06:00:00Z")
        let fakeCenter = FakeUserNotificationCenter()
        let scheduler = makeScheduler(center: fakeCenter, now: nowDate)

        scheduler.scheduleForTodayAndTomorrow(startHour: 22, endHour: 6, intervalMinutes: 60, soundFile: "sound", lastDrinkDate: nil)

        #expect(fakeCenter.removedPending == true)
        #expect(fakeCenter.requests == nil)
    }

    @Test("a drink after today's window closes skips the rest of today")
    func lastDrinkAfterWindow() throws {
        let nowDate = date("2000-01-01T21:30:00Z")
        let lastDrink = date("2000-01-01T21:15:00Z")
        let fakeCenter = FakeUserNotificationCenter()
        let scheduler = makeScheduler(center: fakeCenter, now: nowDate)

        scheduler.scheduleForTodayAndTomorrow(startHour: 7, endHour: 21, intervalMinutes: 60, soundFile: "sound", lastDrinkDate: lastDrink)

        let scheduled = try #require(fakeCenter.requests)
        #expect(scheduled.filter { $0.identifier.hasPrefix("today_") }.isEmpty)
        #expect(triggerDate(from: scheduled[0]) == date("2000-01-02T07:00:00Z"))
    }

    @Test("reminders continue one interval after the last drink")
    func remindersFollowLastDrink() throws {
        let nowDate = date("2000-01-01T10:20:00Z")
        let lastDrink = date("2000-01-01T10:10:00Z")
        let fakeCenter = FakeUserNotificationCenter()
        let scheduler = makeScheduler(center: fakeCenter, now: nowDate)

        scheduler.scheduleForTodayAndTomorrow(startHour: 7, endHour: 12, intervalMinutes: 30, soundFile: "sound", lastDrinkDate: lastDrink)

        let scheduled = try #require(fakeCenter.requests)
        let today = scheduled.filter { $0.identifier.hasPrefix("today_") }.compactMap { timeComponents(from: $0) }
        #expect(formattedTimes(today) == ["10:40", "11:10", "11:40"])
    }

    @Test("cancelAll removes pending reminders and clears the badge")
    func cancelAllClearsEverything() {
        let nowDate = date("2000-01-01T06:00:00Z")
        let fakeCenter = FakeUserNotificationCenter()
        let scheduler = makeScheduler(center: fakeCenter, now: nowDate)
        scheduler.scheduleForTodayAndTomorrow(startHour: 7, endHour: 9, intervalMinutes: 60, soundFile: "sound", lastDrinkDate: nil)
        let badgeResetsBefore = fakeCenter.badgeResetCount

        scheduler.cancelAll()

        #expect(fakeCenter.requests == nil)
        #expect(fakeCenter.badgeResetCount == badgeResetsBefore + 1)
    }

    private func makeScheduler(center: FakeUserNotificationCenter, now nowDate: Date) -> NotificationScheduler {
        NotificationScheduler(centerProvider: { center }, calendar: calendar, now: { nowDate })
    }

    private func triggerDate(from request: UNNotificationRequest) -> Date? {
        guard let trigger = request.trigger as? UNCalendarNotificationTrigger else { return nil }
        return calendar.date(from: trigger.dateComponents)
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

    func authorizationStatus() async -> UNAuthorizationStatus {
        .authorized
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
