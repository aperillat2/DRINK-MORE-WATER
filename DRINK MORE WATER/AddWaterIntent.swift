import AppIntents
import WidgetKit

/// Adds one tap's worth of water — the widget's "Add" button.
///
/// Shared with the widget target. When the button is tapped, this runs in the widget
/// extension's process (not the app), so it works directly on the shared store.
// `nonisolated`: App Intent requirements aren't main-actor isolated (the project defaults
// types to the main actor, which would conflict).
nonisolated struct AddWaterIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Water"
    static let description = IntentDescription("Adds your per-tap amount of water to today's total.")

    func perform() async throws -> some IntentResult {
        // The view model is main-actor isolated; perform() isn't, so hop explicitly.
        let update = await MainActor.run { () -> (goalMet: Bool, lastDrink: Date?)? in
            let model = WaterIntakeViewModel(defaults: SharedStore.defaults)
            model.resetIfNeeded()
            // At or past the goal: nothing to add, and repeating the intent is a no-op.
            guard let step = model.nextIntakeStep() else { return nil }
            model.intakeOz = step.newValue
            model.recordDrink()
            if step.reachedGoal { model.markGoalMetToday() }
            return (model.isGoalMetToday, model.lastDrinkToday)
        }

        if let update {
            // Reminders: skip the rest of today once the goal is met; otherwise the next one
            // comes one interval after this drink. Wait for it, since the extension may be
            // suspended right after this returns.
            ReminderSettings.load().apply(
                to: NotificationScheduler.shared,
                goalMetToday: update.goalMet,
                lastDrinkDate: update.lastDrink,
                waitUntilDone: true
            )
        }
        // Interactive widget buttons reload their widget automatically after perform();
        // this also refreshes the app's other widgets (e.g. Lock Screen).
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
