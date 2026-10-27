import SwiftUI

@main
struct DRINK_MORE_WATERApp: App {
    /// Handles the "Log a drink" button on reminder notifications.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // UI-test launch flags only exist in Debug builds, so they can never affect the App Store build.
    private var shouldSkipSplash: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-UITestsSkipSplash")
        #else
        false
        #endif
    }

    @State private var showSplash = true

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-UITestsResetState") {
            // Wipe every saved value (intake, goal, per-tap, unit, settings...) so UI tests
            // always start from factory defaults, whatever was changed in the simulator.
            if let bundleID = Bundle.main.bundleIdentifier {
                UserDefaults.standard.removePersistentDomain(forName: bundleID)
            }
            SharedStore.defaults.removePersistentDomain(forName: SharedStore.appGroupID)
            // Skip the first-launch "Welcome" walkthrough prompt, which would block taps.
            SharedStore.defaults.set(true, forKey: "hasLaunchedBefore")
            SharedStore.defaults.set(true, forKey: "hasCompletedWalkthrough")
        }
        #endif
        // Data moved to the shared App Group store (for the widget) in 1.6; bring 1.5 data along.
        SharedStore.migrateFromStandardDefaultsIfNeeded()
    }

    /// Cross-fade from the splash photo to the main screen.
    private static let splashFade = Animation.easeInOut(duration: 0.6)

    var body: some Scene {
        WindowGroup {
            ZStack {
                if showSplash {
                    // Kept on top so the light photo fades out over the blue main screen.
                    SplashView()
                        .zIndex(1)
                } else {
                    ContentView()
                }
            }
            .animation(Self.splashFade, value: showSplash)
            .onAppear {
                if shouldSkipSplash { showSplash = false }
            }
            .task {
                guard showSplash && !shouldSkipSplash else { return }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                withAnimation(Self.splashFade) {
                    showSplash = false
                }
            }
        }
    }
}
