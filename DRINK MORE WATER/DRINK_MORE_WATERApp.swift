import SwiftUI

@main
struct DRINK_MORE_WATERApp: App {
    private let uiTestsSkipFlag = "-UITestsSkipSplash"
    private var shouldSkipSplash: Bool { ProcessInfo.processInfo.arguments.contains(uiTestsSkipFlag) }

    @State private var showSplash = true

    init() {
        if ProcessInfo.processInfo.arguments.contains("-UITestsResetState") {
            let defaults = UserDefaults.standard
            defaults.removeObject(forKey: "intakeOz")
            defaults.removeObject(forKey: "lastIntakeDate")
            defaults.removeObject(forKey: "dailyGoalOz")
            defaults.synchronize()
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if showSplash {
                    SplashView()
                } else {
                    ContentView()
                }
            }
            .animation(.easeInOut(duration: 0.3), value: showSplash)
            .onAppear {
                if shouldSkipSplash { showSplash = false }
            }
            .task {
                guard showSplash && !shouldSkipSplash else { return }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                withAnimation {
                    showSplash = false
                }
            }
        }
    }
}
