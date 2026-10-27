import Foundation
import Testing
@testable import DRINK_MORE_WATER

/// A throwaway UserDefaults suite, removed when the test finishes.
private final class TempDefaults {
    let name = "SharedStoreTests.\(UUID().uuidString)"
    lazy var defaults = UserDefaults(suiteName: name)!
    deinit { defaults.removePersistentDomain(forName: name) }
}

private let utc: Calendar = {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(secondsFromGMT: 0)!
    return cal
}()

private func date(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

@Suite("WaterSnapshot (widget data)")
struct WaterSnapshotTests {
    typealias Keys = WaterIntakeViewModel.Keys

    @Test("reads today's intake, goal, per-tap amount and unit")
    func readsToday() {
        let store = TempDefaults()
        store.defaults.set(40, forKey: Keys.intake)
        store.defaults.set("2000-01-01", forKey: Keys.lastIntakeDate)
        store.defaults.set(100, forKey: Keys.dailyGoal)
        store.defaults.set(15, forKey: Keys.perTap)
        store.defaults.set("ml", forKey: Keys.unit)

        let snap = WaterSnapshot.load(from: store.defaults, at: date("2000-01-01T15:00:00Z"), calendar: utc)
        #expect(snap == WaterSnapshot(intake: 40, goal: 100, perTap: 15, unit: .ml))
        #expect(snap.isGoalMet == false)
    }

    @Test("yesterday's intake shows as an empty glass today")
    func newDayIsEmpty() {
        let store = TempDefaults()
        store.defaults.set(80, forKey: Keys.intake)
        store.defaults.set("2000-01-01", forKey: Keys.lastIntakeDate)

        let snap = WaterSnapshot.load(from: store.defaults, at: date("2000-01-02T00:05:00Z"), calendar: utc)
        #expect(snap.intake == 0)
    }

    @Test("uses the app's defaults when nothing is stored")
    func defaultsWhenEmpty() {
        let snap = WaterSnapshot.load(from: TempDefaults().defaults, at: Date(), calendar: utc)
        #expect(snap == WaterSnapshot(intake: 0, goal: 80, perTap: 10, unit: .oz))
    }

    @Test("the midnight entry empties the glass but keeps the goal and unit")
    func startingNewDay() {
        let snap = WaterSnapshot(intake: 2400, goal: 2400, perTap: 300, unit: .ml)
        #expect(snap.isGoalMet)
        #expect(snap.startingNewDay() == WaterSnapshot(intake: 0, goal: 2400, perTap: 300, unit: .ml))
    }
}

@Suite("SharedStore migration from 1.5")
struct SharedStoreMigrationTests {
    @Test("copies saved data and settings into the shared store")
    func copiesOldValues() {
        let old = TempDefaults(), shared = TempDefaults()
        old.defaults.set(30, forKey: WaterIntakeViewModel.Keys.intake)
        old.defaults.set(120, forKey: WaterIntakeViewModel.Keys.dailyGoal)
        old.defaults.set(9, forKey: ReminderSettings.Keys.startHour)
        old.defaults.set(true, forKey: "hasCompletedWalkthrough")

        SharedStore.migrate(from: old.defaults, to: shared.defaults)

        #expect(shared.defaults.integer(forKey: WaterIntakeViewModel.Keys.intake) == 30)
        #expect(shared.defaults.integer(forKey: WaterIntakeViewModel.Keys.dailyGoal) == 120)
        #expect(ReminderSettings.load(from: shared.defaults).startHour == 9)
        #expect(shared.defaults.bool(forKey: "hasCompletedWalkthrough"))
    }

    @Test("runs only once and never overwrites newer shared values")
    func runsOnce() {
        let old = TempDefaults(), shared = TempDefaults()
        old.defaults.set(30, forKey: WaterIntakeViewModel.Keys.intake)
        shared.defaults.set(50, forKey: WaterIntakeViewModel.Keys.intake) // e.g. added from the widget

        SharedStore.migrate(from: old.defaults, to: shared.defaults)
        #expect(shared.defaults.integer(forKey: WaterIntakeViewModel.Keys.intake) == 50)

        // A later change in the old store isn't copied again.
        old.defaults.set(99, forKey: WaterIntakeViewModel.Keys.dailyGoal)
        SharedStore.migrate(from: old.defaults, to: shared.defaults)
        #expect(shared.defaults.object(forKey: WaterIntakeViewModel.Keys.dailyGoal) == nil)
    }
}

@Suite("ReminderSettings storage")
struct ReminderSettingsStorageTests {
    @Test("loads the same defaults the app's Settings screen uses")
    func defaultsMatchApp() {
        let settings = ReminderSettings.load(from: TempDefaults().defaults)
        #expect(settings == ReminderSettings(startHour: 7, endHour: 20, intervalMinutes: 60,
                                             soundFile: "drink more water", muted: false))
    }
}

@MainActor
@Suite("WaterIntakeViewModel.reload")
struct ViewModelReloadTests {
    @Test("picks up water added by the widget")
    func reloadPicksUpWidgetChanges() {
        let store = TempDefaults()
        let vm = WaterIntakeViewModel(defaults: store.defaults)
        vm.intakeOz = 20

        // The widget's Add button writes straight to the shared store.
        store.defaults.set(30, forKey: WaterIntakeViewModel.Keys.intake)
        vm.reload()
        #expect(vm.intakeOz == 30)
    }
}
