import Foundation
import Testing
@testable import DRINK_MORE_WATER

/// A throwaway UserDefaults suite, removed when the test finishes.
private final class TempDefaults {
    let name = "ReviewPrompterTests.\(UUID().uuidString)"
    lazy var defaults = UserDefaults(suiteName: name)!
    deinit { defaults.removePersistentDomain(forName: name) }
}

private let utc: Calendar = {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(secondsFromGMT: 0)!
    return cal
}()

private func date(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

@Suite("ReviewPrompter")
struct ReviewPrompterTests {
    private func prompter(_ store: TempDefaults, on iso: String, version: String = "2.2") -> ReviewPrompter {
        ReviewPrompter(defaults: store.defaults, now: { date(iso) }, calendar: utc, appVersion: version)
    }

    @Test("asks on the third day the goal is met, not before")
    func asksOnThirdGoalDay() {
        let store = TempDefaults()
        #expect(prompter(store, on: "2000-01-01T12:00:00Z").goalMet() == false)
        #expect(prompter(store, on: "2000-01-02T12:00:00Z").goalMet() == false)
        #expect(prompter(store, on: "2000-01-03T12:00:00Z").goalMet() == true)
    }

    @Test("meeting the goal again the same day doesn't count twice")
    func sameDayCountsOnce() {
        let store = TempDefaults()
        for hour in ["08", "12", "18"] {
            #expect(prompter(store, on: "2000-01-01T\(hour):00:00Z").goalMet() == false)
        }
        #expect(store.defaults.integer(forKey: ReviewPrompter.Keys.goalDayCount) == 1)
    }

    @Test("asks only once per app version")
    func oncePerVersion() {
        let store = TempDefaults()
        _ = prompter(store, on: "2000-01-01T12:00:00Z").goalMet()
        _ = prompter(store, on: "2000-01-02T12:00:00Z").goalMet()
        #expect(prompter(store, on: "2000-01-03T12:00:00Z").goalMet() == true)
        #expect(prompter(store, on: "2000-01-04T12:00:00Z").goalMet() == false)
        // A new version may ask again on the next goal day.
        #expect(prompter(store, on: "2000-01-05T12:00:00Z", version: "2.3").goalMet() == true)
    }
}
