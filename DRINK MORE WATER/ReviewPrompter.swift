import Foundation

/// Decides when to ask for an App Store rating. The ask comes right after the goal is met
/// (when people feel best about the app), only once they've met it on a few different days,
/// and at most once per app version. iOS adds its own limit of 3 prompts a year.
struct ReviewPrompter {
    nonisolated enum Keys {
        static let goalDayCount = "reviewGoalDayCount"
        static let lastGoalDay = "reviewLastGoalDay"
        static let lastPromptedVersion = "reviewLastPromptedVersion"
    }

    /// Days with the goal met before the first ask.
    static let goalDaysBeforePrompt = 3

    /// The app's App Store page, opened on the "Write a Review" sheet.
    static let writeReviewURL = URL(string: "https://apps.apple.com/app/id6754523869?action=write-review")

    let defaults: UserDefaults
    let now: () -> Date
    let calendar: Calendar
    let appVersion: String

    init(
        defaults: UserDefaults = SharedStore.defaults,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current,
        appVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    ) {
        self.defaults = defaults
        self.now = now
        self.calendar = calendar
        self.appVersion = appVersion
    }

    /// Call when a tap meets today's goal. Each day counts once, even if the goal is
    /// reset and met again. Returns true if the app should ask for a rating now
    /// (and records that it asked for this version).
    func goalMet() -> Bool {
        let today = DateUtils.dayString(for: now(), calendar: calendar)
        guard defaults.string(forKey: Keys.lastGoalDay) != today else { return false }
        defaults.set(today, forKey: Keys.lastGoalDay)
        let count = defaults.integer(forKey: Keys.goalDayCount) + 1
        defaults.set(count, forKey: Keys.goalDayCount)

        guard count >= Self.goalDaysBeforePrompt,
              defaults.string(forKey: Keys.lastPromptedVersion) != appVersion else { return false }
        defaults.set(appVersion, forKey: Keys.lastPromptedVersion)
        return true
    }
}
