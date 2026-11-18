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
    /// Adds one tap's worth of water to today's total (past the goal too), updates reminders,
    /// clears reminders already showing, and refreshes widgets.
    static func logOneTap() async {
        // The view model is main-actor isolated; callers here aren't, so hop explicitly.
        let update = await MainActor.run {
            () -> (goalMet: Bool, lastDrink: Date?, added: Int, unit: VolumeUnit) in
            let model = WaterIntakeViewModel(defaults: SharedStore.defaults)
            model.resetIfNeeded()
            let step = model.nextIntakeStep()
            let added = step.newValue - model.intakeOz
            model.intakeOz = step.newValue
            model.recordDrink()
            if step.reachedGoal { model.markGoalMetToday() }
            return (model.isGoalMetToday, model.lastDrinkToday, added, model.unit)
        }

        await HealthSync.log(update.added, unit: update.unit, at: update.lastDrink ?? Date())
        // Reminders: skip the rest of today once the goal is met; otherwise the next one
        // comes one interval after this drink. Wait for it, since the process may be
        // suspended right after this returns.
        ReminderSettings.load().apply(
            to: NotificationScheduler.shared,
            goalMetToday: update.goalMet,
            lastDrinkDate: update.lastDrink,
            waitUntilDone: true
        )
        // Earlier reminders still on the Lock Screen are now out of date.
        NotificationScheduler.shared.clearDeliveredReminders()
        // Interactive widget buttons reload their own widget automatically; this refreshes
        // the rest (e.g. Lock Screen widgets), and all of them when logged from a notification.
        WidgetCenter.shared.reloadAllTimelines()
    }
}
