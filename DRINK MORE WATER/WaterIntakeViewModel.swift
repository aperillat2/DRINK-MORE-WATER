import Foundation
import SwiftUI
import Combine

@MainActor
final class WaterIntakeViewModel: ObservableObject {
    /// UserDefaults keys. Shared with the UI-test reset in `DRINK_MORE_WATERApp`.
    enum Keys {
        static let intake = "intakeOz"
        static let lastIntakeDate = "lastIntakeDate"
        static let dailyGoal = "dailyGoalOz"
        static let goalMetDate = "goalMetDate"
        static let perTap = "ozPerTap"
        static let unit = "volumeUnit"
        static let lastDrinkTimestamp = "lastDrinkTimestamp"
    }

    /// Injected so tests can use an isolated store instead of `UserDefaults.standard`.
    private let defaults: UserDefaults

    /// Unit that all stored amounts (intake, goal, per tap) are expressed in.
    /// Change it with `setUnit(_:)` so existing values get converted.
    @Published private(set) var unit: VolumeUnit = .oz {
        didSet { defaults.set(unit.rawValue, forKey: Keys.unit) }
    }

    // Amounts below are in the current `unit` (property/storage names predate ml support).
    @Published var intakeOz: Int = 0 {
        didSet { defaults.set(intakeOz, forKey: Keys.intake) }
    }
    @Published var lastIntakeDateString: String = "" {
        didSet { defaults.set(lastIntakeDateString, forKey: Keys.lastIntakeDate) }
    }
    @Published var dailyGoalOz: Int = 80 {
        didSet { defaults.set(dailyGoalOz, forKey: Keys.dailyGoal) }
    }
    @Published var goalMetDateString: String = "" {
        didSet { defaults.set(goalMetDateString, forKey: Keys.goalMetDate) }
    }
    @Published var ozPerTap: Int = 10 {
        didSet {
            let range = unit.perTapRange
            let clamped = min(max(ozPerTap, range.lowerBound), range.upperBound)
            if clamped != ozPerTap {
                ozPerTap = clamped
                return
            }
            defaults.set(ozPerTap, forKey: Keys.perTap)
        }
    }

    /// When the user last tapped the glass. Used to time the next reminder.
    @Published private(set) var lastDrinkDate: Date? = nil {
        didSet {
            if let lastDrinkDate {
                defaults.set(lastDrinkDate.timeIntervalSince1970, forKey: Keys.lastDrinkTimestamp)
            } else {
                defaults.removeObject(forKey: Keys.lastDrinkTimestamp)
            }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Unit must be set first so the per-tap clamp uses the right range.
        unit = VolumeUnit(rawValue: defaults.string(forKey: Keys.unit) ?? "") ?? .oz
        intakeOz = defaults.integer(forKey: Keys.intake)
        lastIntakeDateString = defaults.string(forKey: Keys.lastIntakeDate) ?? ""
        dailyGoalOz = defaults.object(forKey: Keys.dailyGoal) as? Int ?? 80
        goalMetDateString = defaults.string(forKey: Keys.goalMetDate) ?? ""
        ozPerTap = defaults.object(forKey: Keys.perTap) as? Int ?? 10
        if let timestamp = defaults.object(forKey: Keys.lastDrinkTimestamp) as? Double {
            lastDrinkDate = Date(timeIntervalSince1970: timestamp)
        }
    }

    /// The last drink time, but only if it happened today; otherwise nil.
    var lastDrinkToday: Date? {
        guard let lastDrinkDate, Calendar.current.isDateInToday(lastDrinkDate) else { return nil }
        return lastDrinkDate
    }

    func recordDrink(at date: Date = Date()) {
        lastDrinkDate = date
    }

    var isGoalMetToday: Bool {
        goalMetDateString == DateUtils.todayString()
    }

    func markGoalMetToday() {
        goalMetDateString = DateUtils.todayString()
    }

    func clearGoalMetFlag() {
        goalMetDateString = ""
    }

    func resetIfNeeded() {
        let today = DateUtils.todayString()
        if lastIntakeDateString != today {
            intakeOz = 0
            lastIntakeDateString = today
            clearGoalMetFlag()
            lastDrinkDate = nil
        }
    }

    /// Switches units, converting the goal, per-tap amount and today's intake.
    /// Goal and per-tap are snapped to the new unit's slider steps; a met goal stays met.
    func setUnit(_ newUnit: VolumeUnit) {
        guard newUnit != unit else { return }
        let oldUnit = unit
        let wasAtGoal = intakeOz >= dailyGoalOz

        let newGoal = VolumeUnit.snap(
            newUnit.convert(dailyGoalOz, from: oldUnit),
            step: newUnit.goalStep,
            range: newUnit.goalRange
        )
        let newPerTap = VolumeUnit.snap(
            newUnit.convert(ozPerTap, from: oldUnit),
            step: newUnit.perTapStep,
            range: newUnit.perTapRange
        )
        let convertedIntake = Int(newUnit.convert(intakeOz, from: oldUnit).rounded())

        unit = newUnit
        dailyGoalOz = newGoal
        ozPerTap = newPerTap
        // Rounding must not flip the goal state in either direction.
        intakeOz = wasAtGoal ? newGoal : min(convertedIntake, newGoal - 1)
    }

    /// Returns the next intake value and whether this step reaches the goal.
    /// Returns nil if already at or above the goal.
    func nextIntakeStep() -> (newValue: Int, reachedGoal: Bool)? {
        guard intakeOz < dailyGoalOz else { return nil }
        let newValue = min(intakeOz + ozPerTap, dailyGoalOz)
        let reached = newValue >= dailyGoalOz
        return (newValue, reached)
    }
}
