import Foundation
import Testing
@testable import DRINK_MORE_WATER

/// A throwaway UserDefaults suite per test, so tests can run in parallel without
/// sharing state with each other or with the real app's `UserDefaults.standard`.
private final class IsolatedDefaults {
    let suiteName = "WaterIntakeViewModelTests.\(UUID().uuidString)"
    let defaults: UserDefaults

    init(intake: Int? = nil, date: String? = nil, goal: Int? = nil) {
        defaults = UserDefaults(suiteName: suiteName)!
        if let intake { defaults.set(intake, forKey: WaterIntakeViewModel.Keys.intake) }
        if let date { defaults.set(date, forKey: WaterIntakeViewModel.Keys.lastIntakeDate) }
        if let goal { defaults.set(goal, forKey: WaterIntakeViewModel.Keys.dailyGoal) }
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
    }
}

/// A clock the test can move forward, e.g. across midnight.
private final class TestClock {
    var now: Date
    init(_ now: Date) { self.now = now }
}

/// UTC Gregorian calendar so dates in tests mean the same thing everywhere.
private let utc: Calendar = {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(secondsFromGMT: 0)!
    return cal
}()

private func date(_ iso: String) -> Date {
    ISO8601DateFormatter().date(from: iso)!
}

@MainActor
private func makeViewModel(_ store: IsolatedDefaults, clock: TestClock) -> WaterIntakeViewModel {
    WaterIntakeViewModel(defaults: store.defaults, now: { clock.now }, calendar: utc)
}

@MainActor
@Suite("WaterIntakeViewModel Tests")
struct WaterIntakeViewModelTests {

    @Test("Init seeds from stored values")
    func initSeedsFromStorage() {
        let store = IsolatedDefaults(intake: 15, date: "2000-01-01", goal: 100)

        let vm = WaterIntakeViewModel(defaults: store.defaults)
        #expect(vm.intakeOz == 15)
        #expect(vm.lastIntakeDateString == "2000-01-01")
        #expect(vm.dailyGoalOz == 100)
    }

    @Test("Init uses defaults when nothing is stored")
    func initUsesDefaultsWhenEmpty() {
        let store = IsolatedDefaults()

        let vm = WaterIntakeViewModel(defaults: store.defaults)
        #expect(vm.intakeOz == 0)
        #expect(vm.dailyGoalOz == 80)
        #expect(vm.ozPerTap == 10)
        #expect(vm.unit == .oz)
        #expect(vm.lastDrinkDate == nil)
    }

    @Test("Changes are persisted to the injected store")
    func changesArePersisted() {
        let store = IsolatedDefaults()

        let vm = WaterIntakeViewModel(defaults: store.defaults)
        vm.intakeOz = 30
        vm.dailyGoalOz = 120
        vm.ozPerTap = 15

        let reloaded = WaterIntakeViewModel(defaults: store.defaults)
        #expect(reloaded.intakeOz == 30)
        #expect(reloaded.dailyGoalOz == 120)
        #expect(reloaded.ozPerTap == 15)
    }

    @Test("ozPerTap is clamped to the unit's range")
    func perTapIsClamped() {
        let store = IsolatedDefaults()

        let vm = WaterIntakeViewModel(defaults: store.defaults)
        vm.ozPerTap = 100
        #expect(vm.ozPerTap == 20)
        vm.ozPerTap = 1
        #expect(vm.ozPerTap == 5)
    }

    @Test("nextIntakeStep increments and can reach goal")
    func nextIntakeStepReachesGoal() throws {
        let store = IsolatedDefaults(intake: 0, date: "2000-01-01", goal: 100)

        let vm = WaterIntakeViewModel(defaults: store.defaults)
        vm.dailyGoalOz = 20
        vm.intakeOz = 10

        let step = try #require(vm.nextIntakeStep())
        #expect(step.newValue == 20)
        #expect(step.reachedGoal == true)
    }

    @Test("nextIntakeStep returns nil once the goal is reached")
    func nextIntakeStepNilAtGoal() {
        let store = IsolatedDefaults(intake: 80, date: DateUtils.todayString(), goal: 80)

        let vm = WaterIntakeViewModel(defaults: store.defaults)
        #expect(vm.nextIntakeStep() == nil)
    }

    @Test("resetIfNeeded resets when the clock passes midnight")
    func resetIfNeededAcrossMidnight() {
        let clock = TestClock(date("2000-01-01T23:50:00Z"))
        let store = IsolatedDefaults(intake: 30, date: "2000-01-01", goal: 80)
        let vm = makeViewModel(store, clock: clock)
        vm.recordDrink()
        vm.intakeOz = 80
        vm.markGoalMetToday()

        // Still the same day: nothing changes.
        vm.resetIfNeeded()
        #expect(vm.intakeOz == 80)
        #expect(vm.isGoalMetToday)
        #expect(vm.lastDrinkToday != nil)

        // Ten minutes later it's a new day.
        clock.now = date("2000-01-02T00:00:00Z")
        #expect(vm.isGoalMetToday == false, "Yesterday's goal doesn't count today")
        #expect(vm.lastDrinkToday == nil, "Yesterday's drink doesn't time today's reminders")
        vm.resetIfNeeded()

        #expect(vm.intakeOz == 0)
        #expect(vm.lastIntakeDateString == "2000-01-02")
        #expect(vm.lastDrinkDate == nil)
    }

    @Test("resetToday empties the glass and clears today's drink")
    func resetTodayClearsEverything() {
        let clock = TestClock(date("2000-01-01T12:00:00Z"))
        let store = IsolatedDefaults(intake: 80, date: "2000-01-01", goal: 80)
        let vm = makeViewModel(store, clock: clock)
        vm.recordDrink()
        vm.markGoalMetToday()

        vm.resetToday()

        #expect(vm.intakeOz == 0)
        #expect(vm.isGoalMetToday == false)
        #expect(vm.lastDrinkDate == nil)
    }

    @Test("recordDrink persists the last drink time across launches")
    func recordDrinkPersists() throws {
        let drinkTime = date("2000-01-01T12:34:56Z")
        let clock = TestClock(drinkTime)
        let store = IsolatedDefaults()

        makeViewModel(store, clock: clock).recordDrink()

        let reloaded = makeViewModel(store, clock: clock)
        let restored = try #require(reloaded.lastDrinkDate)
        #expect(abs(restored.timeIntervalSince(drinkTime)) < 0.001)
        #expect(reloaded.lastDrinkToday == restored)
    }

    @Test("Lowering the goal to or below today's intake meets it")
    func loweringGoalMeetsIt() {
        let clock = TestClock(date("2000-01-01T12:00:00Z"))
        let store = IsolatedDefaults(intake: 60, date: "2000-01-01", goal: 80)
        let vm = makeViewModel(store, clock: clock)

        vm.dailyGoalOz = 50
        #expect(vm.syncGoalMetState() == true)
        #expect(vm.isGoalMetToday)
        #expect(vm.intakeOz == 60, "Intake isn't lost when the goal is lowered")
        #expect(vm.nextIntakeStep() == nil)

        // Calling again without a change reports nothing new.
        #expect(vm.syncGoalMetState() == false)
    }

    @Test("Raising the goal above today's intake un-meets it")
    func raisingGoalUnmeetsIt() throws {
        let clock = TestClock(date("2000-01-01T12:00:00Z"))
        let store = IsolatedDefaults(intake: 80, date: "2000-01-01", goal: 80)
        let vm = makeViewModel(store, clock: clock)
        vm.markGoalMetToday()

        vm.dailyGoalOz = 100
        #expect(vm.syncGoalMetState() == true)
        #expect(vm.isGoalMetToday == false)
        let step = try #require(vm.nextIntakeStep(), "Tapping works again")
        #expect(step.newValue == 90)
    }

    @Test("setUnit converts amounts between oz and ml")
    func setUnitConvertsAmounts() {
        let store = IsolatedDefaults(intake: 40, date: DateUtils.todayString(), goal: 80)

        let vm = WaterIntakeViewModel(defaults: store.defaults)
        vm.ozPerTap = 10
        vm.setUnit(.ml)
        #expect(vm.unit == .ml)
        #expect(vm.dailyGoalOz == 2400)
        #expect(vm.ozPerTap == 300)
        #expect(vm.intakeOz == 1183)

        // A met goal stays met after switching back.
        vm.intakeOz = vm.dailyGoalOz
        vm.setUnit(.oz)
        #expect(vm.unit == .oz)
        #expect(vm.dailyGoalOz == 80)
        #expect(vm.ozPerTap == 10)
        #expect(vm.intakeOz == vm.dailyGoalOz)

        // The chosen unit survives a relaunch.
        vm.setUnit(.ml)
        #expect(WaterIntakeViewModel(defaults: store.defaults).unit == .ml)
    }

    @Test("setUnit never turns an unfinished day into a met goal by rounding")
    func setUnitDoesNotRoundIntoGoal() {
        // 79 oz is 2336 ml, but the goal snaps to 2400 ml; intake must stay below it.
        let store = IsolatedDefaults(intake: 79, date: DateUtils.todayString(), goal: 80)
        let vm = WaterIntakeViewModel(defaults: store.defaults)

        vm.setUnit(.ml)
        #expect(vm.intakeOz < vm.dailyGoalOz)
    }
}

@Suite("FillFractionCalculator Tests")
struct FillFractionCalculatorTests {
    private let calc = FillFractionCalculator()
    private let bounds = WaterMaskBounds(emptyFraction: 0.1, fullFraction: 0.9)

    @Test("fraction increases with intake and stays within bounds")
    func fractionBasicBehavior() {
        let goal: CGFloat = 80
        let perTap: CGFloat = 10

        let f0 = calc.fraction(intakeOz: 0, goalOz: goal, bounds: bounds, perTapOz: perTap)
        let f1 = calc.fraction(intakeOz: 10, goalOz: goal, bounds: bounds, perTapOz: perTap)
        let f4 = calc.fraction(intakeOz: 40, goalOz: goal, bounds: bounds, perTapOz: perTap)
        let f8 = calc.fraction(intakeOz: 80, goalOz: goal, bounds: bounds, perTapOz: perTap)

        #expect(f0 >= bounds.emptyFraction)
        #expect(f1 > f0)
        #expect(f4 > f1)
        #expect(f8 <= bounds.fullFraction)
    }

    @Test("every tap raises the level, and the last one stays below the rim",
          arguments: [(80, 10), (200, 5), (40, 20), (2400, 300)])
    func monotonicUpToGoal(goal: Int, perTap: Int) {
        var previous = calc.fraction(intakeOz: 0, goalOz: CGFloat(goal), bounds: bounds, perTapOz: CGFloat(perTap))
        var intake = 0
        while intake < goal {
            intake = min(intake + perTap, goal)
            let current = calc.fraction(intakeOz: CGFloat(intake), goalOz: CGFloat(goal), bounds: bounds, perTapOz: CGFloat(perTap))
            #expect(current > previous, "Level should rise at \(intake)/\(goal)")
            previous = current
        }
        #expect(previous <= bounds.fullFraction)
    }

    @Test("a zero goal shows an empty glass")
    func zeroGoalIsEmpty() {
        #expect(calc.fraction(intakeOz: 10, goalOz: 0, bounds: bounds, perTapOz: 10) == bounds.emptyFraction)
    }

    @Test("intake above the goal shows a full glass, not more")
    func intakeAboveGoalIsFull() {
        let atGoal = calc.fraction(intakeOz: 60, goalOz: 60, bounds: bounds, perTapOz: 10)
        let aboveGoal = calc.fraction(intakeOz: 90, goalOz: 60, bounds: bounds, perTapOz: 10)
        #expect(aboveGoal == atGoal)
    }

    @Test("a per-tap amount bigger than the goal fills in one tap")
    func perTapBiggerThanGoal() {
        let full = calc.fraction(intakeOz: 40, goalOz: 40, bounds: bounds, perTapOz: 100)
        #expect(full > bounds.emptyFraction)
        #expect(full <= bounds.fullFraction)
    }
}

@Suite("VolumeUnit Tests")
struct VolumeUnitTests {
    @Test("snap rounds to the step and clamps to the range")
    func snapRoundsAndClamps() {
        #expect(VolumeUnit.snap(2366, step: 100, range: 1200...6000) == 2400)
        #expect(VolumeUnit.snap(296, step: 10, range: 150...600) == 300)
        #expect(VolumeUnit.snap(50, step: 10, range: 150...600) == 150)
        #expect(VolumeUnit.snap(9000, step: 100, range: 1200...6000) == 6000)
    }

    @Test("converting oz to ml and back returns the original amount")
    func roundTrip() {
        for oz in [5, 10, 80, 200] {
            let ml = VolumeUnit.ml.convert(oz, from: .oz)
            let back = VolumeUnit.oz.convert(Int(ml.rounded()), from: .ml)
            #expect(Int(back.rounded()) == oz)
        }
        #expect(VolumeUnit.oz.convert(42, from: .oz) == 42)
    }

    @Test("default goal and per-tap amounts fit inside both units' slider ranges")
    func defaultsFitRanges() {
        for unit in VolumeUnit.allCases {
            #expect(unit.goalRange.lowerBound % unit.goalStep == 0)
            #expect(unit.perTapRange.lowerBound % unit.perTapStep == 0)
        }
        #expect(VolumeUnit.oz.goalRange.contains(80))
        #expect(VolumeUnit.oz.perTapRange.contains(10))
    }
}
