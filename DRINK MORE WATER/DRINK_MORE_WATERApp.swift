//
//  DRINK_MORE_WATERApp.swift
//  DRINK MORE WATER
//
//  Created by AARON PERILLAT on 10/22/25.
//

import SwiftUI
import SwiftData

@main
struct DRINK_MORE_WATERApp: App {
    private let uiTestsSkipFlag = "-UITestsSkipSplash"
    private var shouldSkipSplash: Bool { ProcessInfo.processInfo.arguments.contains(uiTestsSkipFlag) }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    @State private var showSplash = true

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
        .modelContainer(sharedModelContainer)
    }
}
