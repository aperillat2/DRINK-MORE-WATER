import Foundation
import Testing
@testable import DRINK_MORE_WATER

@Suite("WaterIntakeViewModel Tests")
struct WaterIntakeViewModelTests {

    private func setDefaults(intake: Int, date: String, goal: Int) {
        let d = UserDefaults.standard
        d.set(intake, forKey: "intakeOz")
        d.set(date, forKey: "lastIntakeDate")
        d.set(goal, forKey: "dailyGoalOz")
        d.synchronize()
    }

    private func clearDefaults() {
        let d = UserDefaults.standard
        d.removeObject(forKey: "intakeOz")
        d.removeObject(forKey: "lastIntakeDate")
        d.removeObject(forKey: "dailyGoalOz")
        d.synchronize()
    }

    @MainActor
    @Test("Init seeds from AppStorage")
    func initSeedsFromAppStorage() async throws {
        clearDefaults()
        setDefaults(intake: 15, date: "2000-01-01", goal: 100)

        let vm = WaterIntakeViewModel()
        #expect(vm.intakeOz == 15)
        #expect(vm.lastIntakeDateString == "2000-01-01")
        #expect(vm.dailyGoalOz == 100)

        clearDefaults()
    }

    @MainActor
    @Test("nextIntakeStep increments and can reach goal")
    func nextIntakeStepReachesGoal() async throws {
        clearDefaults()
        setDefaults(intake: 0, date: "2000-01-01", goal: 100)

        let vm = WaterIntakeViewModel()
        vm.dailyGoalOz = 20
        vm.intakeOz = 10

        let step = try #require(vm.nextIntakeStep())
        #expect(step.newValue == 20)
        #expect(step.reachedGoal == true)

        clearDefaults()
    }

    @MainActor
    @Test("resetIfNeeded resets on new day")
    func resetIfNeededResetsOnNewDay() async throws {
        clearDefaults()
        setDefaults(intake: 30, date: "2000-01-01", goal: 80)

        let vm = WaterIntakeViewModel()
        vm.resetIfNeeded()

        #expect(vm.intakeOz == 0)
        #expect(vm.lastIntakeDateString == DateUtils.todayString())

        clearDefaults()
    }

    @MainActor
    @Test("resetIfNeeded no-op when already today")
    func resetIfNeededNoOpForToday() async throws {
        clearDefaults()
        let today = DateUtils.todayString()
        setDefaults(intake: 30, date: today, goal: 80)

        let vm = WaterIntakeViewModel()
        vm.resetIfNeeded()

        #expect(vm.intakeOz == 30)
        #expect(vm.lastIntakeDateString == today)

        clearDefaults()
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
