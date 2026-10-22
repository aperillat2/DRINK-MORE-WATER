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

    @Test("resetIfNeeded resets on new day")
    func resetIfNeededResetsOnNewDay() {
        let store = IsolatedDefaults(intake: 30, date: "2000-01-01", goal: 80)

        let vm = WaterIntakeViewModel(defaults: store.defaults)
        vm.recordDrink(at: Date(timeIntervalSince1970: 946_728_000)) // 2000-01-01
        vm.markGoalMetToday()
        vm.resetIfNeeded()

        #expect(vm.intakeOz == 0)
        #expect(vm.lastIntakeDateString == DateUtils.todayString())
        #expect(vm.isGoalMetToday == false)
        #expect(vm.lastDrinkDate == nil)
    }

    @Test("resetIfNeeded no-op when already today")
    func resetIfNeededNoOpForToday() {
        let today = DateUtils.todayString()
        let store = IsolatedDefaults(intake: 30, date: today, goal: 80)

        let vm = WaterIntakeViewModel(defaults: store.defaults)
        vm.resetIfNeeded()

        #expect(vm.intakeOz == 30)
        #expect(vm.lastIntakeDateString == today)
    }

    @Test("recordDrink persists the last drink time across launches")
    func recordDrinkPersists() throws {
        let store = IsolatedDefaults()
        let drinkTime = Date().addingTimeInterval(-600).rounded()

        let vm = WaterIntakeViewModel(defaults: store.defaults)
        vm.recordDrink(at: drinkTime)

        let reloaded = WaterIntakeViewModel(defaults: store.defaults)
        let restored = try #require(reloaded.lastDrinkDate)
        #expect(abs(restored.timeIntervalSince(drinkTime)) < 0.001)
    }

    @Test("lastDrinkToday ignores drinks from previous days")
    func lastDrinkTodayIgnoresOldDrinks() throws {
        let store = IsolatedDefaults()
        let vm = WaterIntakeViewModel(defaults: store.defaults)

        #expect(vm.lastDrinkToday == nil)

        let yesterday = try #require(Calendar.current.date(byAdding: .day, value: -1, to: Date()))
        vm.recordDrink(at: yesterday)
        #expect(vm.lastDrinkToday == nil)

        let now = Date()
        vm.recordDrink(at: now)
        #expect(vm.lastDrinkToday == now)
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
}

@Suite("FillFractionCalculator Tests")
struct FillFractionCalculatorTests {
    @MainActor
    @Test("fraction increases with intake and stays within bounds")
    func fractionBasicBehavior() async throws {
        let calc = FillFractionCalculator()
        let bounds = WaterMaskBounds(emptyFraction: 0.1, fullFraction: 0.9)
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
}

private extension Date {
    /// Whole seconds, so the value round-trips exactly through UserDefaults.
    func rounded() -> Date {
        Date(timeIntervalSince1970: timeIntervalSince1970.rounded())
    }
}
