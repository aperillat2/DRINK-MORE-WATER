import Foundation

/// Storage shared by the app and its widget extension (an App Group).
///
/// Shared with the widget target: the widget reads today's progress from here, and its
/// "Add water" button writes to it.
nonisolated enum SharedStore {
    static let appGroupID = "group.com.dreampuddle.drinkmorewater"

    /// Falls back to `.standard` only if the App Group isn't configured (e.g. a misconfigured build),
    /// so the app keeps working rather than losing data.
    static let defaults: UserDefaults = UserDefaults(suiteName: appGroupID) ?? .standard

    /// Every key the app persists. Versions up to 1.5 stored these in `UserDefaults.standard`.
    static let allKeys: [String] = [
        WaterIntakeViewModel.Keys.intake,
        WaterIntakeViewModel.Keys.lastIntakeDate,
        WaterIntakeViewModel.Keys.dailyGoal,
        WaterIntakeViewModel.Keys.goalMetDate,
        WaterIntakeViewModel.Keys.perTap,
        WaterIntakeViewModel.Keys.unit,
        WaterIntakeViewModel.Keys.lastDrinkTimestamp,
        ReminderSettings.Keys.startHour,
        ReminderSettings.Keys.endHour,
        ReminderSettings.Keys.intervalMinutes,
        ReminderSettings.Keys.soundFile,
        ReminderSettings.Keys.muted,
        "muteTapSound",
        "hasCompletedWalkthrough",
        "hasLaunchedBefore",
    ]

    private static let migratedKey = "didMigrateToAppGroup"

    /// One-time copy of data saved by version 1.5 and earlier into the shared store,
    /// so updating the app keeps the user's intake, goal and settings. Safe to call every launch.
    static func migrateFromStandardDefaultsIfNeeded() {
        migrate(from: .standard, to: defaults)
    }

    /// Copies each key that's missing in `shared` from `old`, once. Existing shared values win.
    static func migrate(from old: UserDefaults, to shared: UserDefaults) {
        guard shared !== old, !shared.bool(forKey: migratedKey) else { return }
        for key in allKeys {
            if shared.object(forKey: key) == nil, let value = old.object(forKey: key) {
                shared.set(value, forKey: key)
            }
        }
        shared.set(true, forKey: migratedKey)
    }
}

/// Read-only view of today's progress, for the widget's timeline.
/// Applies the same "new day starts empty" rule as `WaterIntakeViewModel.resetIfNeeded()`.
nonisolated struct WaterSnapshot: Sendable, Equatable {
    var intake: Int
    var goal: Int
    var perTap: Int
    var unit: VolumeUnit

    var isGoalMet: Bool { intake >= goal }

    static func load(from defaults: UserDefaults = SharedStore.defaults, at date: Date = Date(),
                     calendar: Calendar = .current) -> WaterSnapshot {
        typealias Keys = WaterIntakeViewModel.Keys
        let unit = VolumeUnit(rawValue: defaults.string(forKey: Keys.unit) ?? "") ?? .oz
        let today = DateUtils.dayString(for: date, calendar: calendar)
        let storedDay = defaults.string(forKey: Keys.lastIntakeDate) ?? ""
        let intake = storedDay == today ? defaults.integer(forKey: Keys.intake) : 0
        return WaterSnapshot(
            intake: intake,
            goal: defaults.object(forKey: Keys.dailyGoal) as? Int ?? 80,
            perTap: defaults.object(forKey: Keys.perTap) as? Int ?? 10,
            unit: unit
        )
    }

    /// Same snapshot, but as it will look at the start of the next day (glass emptied).
    func startingNewDay() -> WaterSnapshot {
        var copy = self
        copy.intake = 0
        return copy
    }
}
