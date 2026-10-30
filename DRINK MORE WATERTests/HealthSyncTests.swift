import Foundation
import Testing
@testable import DRINK_MORE_WATER

/// A throwaway UserDefaults suite, removed when the test finishes.
private final class TempDefaults {
    let name = "HealthSyncTests.\(UUID().uuidString)"
    lazy var defaults = UserDefaults(suiteName: name)!
    deinit { defaults.removePersistentDomain(forName: name) }
}

private let utc: Calendar = {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(secondsFromGMT: 0)!
    return cal
}()

private func date(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

/// Covers the queue only; the test host has no Health permission, so nothing is actually saved.
@Suite("HealthSync queue")
struct HealthSyncTests {
    @Test("nothing is queued while saving to Health is off")
    func offQueuesNothing() async {
        let store = TempDefaults()
        await HealthSync.log(10, unit: .oz, at: date("2000-01-01T09:00:00Z"), defaults: store.defaults)
        #expect(HealthSync.pending(in: store.defaults).isEmpty)
    }

    @Test("a drink is queued in milliliters when saving is on")
    func onQueuesInMilliliters() async throws {
        let store = TempDefaults()
        store.defaults.set(true, forKey: HealthSync.Keys.enabled)
        await HealthSync.log(10, unit: .oz, at: date("2000-01-01T09:00:00Z"), defaults: store.defaults)

        let drink = try #require(HealthSync.pending(in: store.defaults).first)
        #expect(abs(drink.milliliters - 295.735) < 0.001)
        #expect(drink.date == date("2000-01-01T09:00:00Z"))
    }

    @Test("drinks older than a week are dropped when another is queued")
    func oldDrinksDropped() {
        let store = TempDefaults()
        let old = HealthSync.Drink(id: UUID(), date: date("2000-01-01T09:00:00Z"), milliliters: 250)
        let recent = HealthSync.Drink(id: UUID(), date: date("2000-01-07T09:00:00Z"), milliliters: 250)
        let new = HealthSync.Drink(id: UUID(), date: date("2000-01-08T10:00:00Z"), milliliters: 250)
        HealthSync.enqueue(old, now: old.date, in: store.defaults)
        HealthSync.enqueue(recent, now: recent.date, in: store.defaults)
        HealthSync.enqueue(new, now: new.date, in: store.defaults)

        #expect(HealthSync.pending(in: store.defaults) == [recent, new])
    }

    @Test("resetting a day removes only that day's queued drinks")
    func resetRemovesThatDay() async {
        let store = TempDefaults()
        let yesterday = HealthSync.Drink(id: UUID(), date: date("2000-01-01T23:30:00Z"), milliliters: 250)
        let today = HealthSync.Drink(id: UUID(), date: date("2000-01-02T08:00:00Z"), milliliters: 250)
        HealthSync.enqueue(yesterday, now: today.date, in: store.defaults)
        HealthSync.enqueue(today, now: today.date, in: store.defaults)

        await HealthSync.deleteDrinks(onDayOf: date("2000-01-02T12:00:00Z"), calendar: utc, defaults: store.defaults)
        #expect(HealthSync.pending(in: store.defaults) == [yesterday])
    }

    @Test("turning saving off empties the queue")
    func clearEmpties() {
        let store = TempDefaults()
        let drink = HealthSync.Drink(id: UUID(), date: date("2000-01-01T09:00:00Z"), milliliters: 250)
        HealthSync.enqueue(drink, now: drink.date, in: store.defaults)
        HealthSync.clearPending(in: store.defaults)
        #expect(HealthSync.pending(in: store.defaults).isEmpty)
    }
}
