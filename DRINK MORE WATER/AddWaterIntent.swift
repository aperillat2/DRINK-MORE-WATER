import AppIntents
import WidgetKit

/// Adds one tap's worth of water — the widgets' and controls' "Add" button.
///
/// Shared with the widget target. When the button is tapped, this runs in the widget
/// extension's process (not the app), so it works directly on the shared store.
// `nonisolated`: App Intent requirements aren't main-actor isolated (the project defaults
// types to the main actor, which would conflict).
nonisolated struct AddWaterIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Water"
    static let description = IntentDescription("Adds your per-tap amount of water to today's total.")
    /// Logging a drink is harmless and private, so allow it straight from the Lock Screen
    /// without unlocking (Lock Screen widgets, Lock Screen/Control Center controls, Action button).
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    func perform() async throws -> some IntentResult {
        await WaterLogger.logOneTap()
        return .result()
    }
}

/// The "log a drink without opening the app" logic, shared by the widget/control button
/// (`AddWaterIntent`) and the reminder notification's "Log a drink" action.
nonisolated enum WaterLogger {
    /// Adds one tap's worth of water to today's total, updates reminders, and refreshes widgets.
    /// At or past the goal there's nothing to add, so calling it again is a no-op.
    /// - Returns: true if water was added.
    @discardableResult
    static func logOneTap() async -> Bool {
        // The view model is main-actor isolated; callers here aren't, so hop explicitly.
        let update = await MainActor.run { () -> (goalMet: Bool, lastDrink: Date?)? in
            let model = WaterIntakeViewModel(defaults: SharedStore.defaults)
            model.resetIfNeeded()
            guard let step = model.nextIntakeStep() else { return nil }
            model.intakeOz = step.newValue
            model.recordDrink()
            if step.reachedGoal { model.markGoalMetToday() }
            return (model.isGoalMetToday, model.lastDrinkToday)
        }

        if let update {
            // Reminders: skip the rest of today once the goal is met; otherwise the next one
            // comes one interval after this drink. Wait for it, since the process may be
            // suspended right after this returns.
            ReminderSettings.load().apply(
                to: NotificationScheduler.shared,
                goalMetToday: update.goalMet,
                lastDrinkDate: update.lastDrink,
                waitUntilDone: true
            )
        }
        // Interactive widget buttons reload their own widget automatically; this refreshes
        // the rest (e.g. Lock Screen widgets), and all of them when logged from a notification.
        WidgetCenter.shared.reloadAllTimelines()
        return update != nil
    }
}
