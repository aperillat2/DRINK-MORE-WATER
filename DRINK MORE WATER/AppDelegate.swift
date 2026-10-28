import UIKit
import UserNotifications

/// Handles the reminder notification's "Log a drink" button.
///
/// When someone taps it (on the Lock Screen, in Notification Center, or on Apple Watch), iOS
/// launches the app in the background just long enough to call `didReceive`; the app's UI
/// doesn't open.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // The delegate must be set before launch finishes, or a tap that launched the app is missed.
        UNUserNotificationCenter.current().delegate = self
        ReminderNotification.registerCategory()
        return true
    }

    // Must stay on the main actor: when this returns, UIKit finishes handling the response
    // (state restoration, snapshot) and asserts it's on the main thread. Running it
    // nonisolated crashed with "Call must be made on main thread".
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == ReminderNotification.logDrinkActionID else { return }
        // Same logic as the widgets' Add button: adds water, reschedules reminders, refreshes widgets.
        // If the app is also open, it picks up the change when it next becomes active.
        await WaterLogger.logOneTap()
    }
}
