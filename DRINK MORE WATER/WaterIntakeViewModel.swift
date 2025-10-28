import Foundation
import SwiftUI
import Combine

@MainActor
final class WaterIntakeViewModel: ObservableObject {
    @AppStorage("intakeOz") private var storedIntakeOz: Int = 0
    @AppStorage("lastIntakeDate") private var storedLastIntakeDateString: String = ""
    @AppStorage("dailyGoalOz") private var storedDailyGoalOz: Int = 80
    @AppStorage("goalMetDate") private var storedGoalMetDateString: String = ""

    @Published var intakeOz: Int = 0 {
        didSet { storedIntakeOz = intakeOz }
    }
    @Published var lastIntakeDateString: String = "" {
        didSet { storedLastIntakeDateString = lastIntakeDateString }
    }
    @Published var dailyGoalOz: Int = 80 {
        didSet { storedDailyGoalOz = dailyGoalOz }
    }
    @Published var goalMetDateString: String = "" {
        didSet { storedGoalMetDateString = goalMetDateString }
    }

    init() {
        intakeOz = storedIntakeOz
        lastIntakeDateString = storedLastIntakeDateString
        dailyGoalOz = storedDailyGoalOz
        goalMetDateString = storedGoalMetDateString
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

    let ozPerTap: Int = 10

    func resetIfNeeded() {
        let today = DateUtils.todayString()
        if lastIntakeDateString != today {
            intakeOz = 0
            lastIntakeDateString = today
            clearGoalMetFlag()
        }
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
