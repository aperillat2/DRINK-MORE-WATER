//
//  ContentView.swift
//  DRINK MORE WATER
//
//  Created by AARON PERILLAT on 10/22/25.
//

import SwiftUI
import CoreGraphics
import UserNotifications
import WidgetKit

struct ContentView: View {
    // Walkthrough state
    // All persisted settings live in the shared App Group store so the widget can read them.
    @AppStorage("hasCompletedWalkthrough", store: SharedStore.defaults) private var hasCompletedWalkthrough: Bool = false
    @AppStorage("hasLaunchedBefore", store: SharedStore.defaults) private var hasLaunchedBefore: Bool = false
    @State private var showWalkthroughPrompt: Bool = false
    @State private var walkthroughStep: Int? = nil // nil = not showing, 1..3 = steps

    private let haptics = HapticsFactory.default()
    @State private var viewModel = WaterIntakeViewModel()

    @Environment(\.scenePhase) private var scenePhase

    @State private var showOzPerTapPicker: Bool = false

    // Notification settings (persisted)
    // Defaults must match `ReminderSettings.load(from:)`, which the widget uses.
    @AppStorage(ReminderSettings.Keys.startHour, store: SharedStore.defaults) private var notifStartHour: Int = 7    // 7 AM
    @AppStorage(ReminderSettings.Keys.endHour, store: SharedStore.defaults) private var notifEndHour: Int = 20       // 8 PM
    @AppStorage(ReminderSettings.Keys.soundFile, store: SharedStore.defaults) private var notifSoundFile: String = "drink more water"
    @AppStorage(ReminderSettings.Keys.intervalMinutes, store: SharedStore.defaults) private var notifIntervalMinutes: Int = 60
    @AppStorage(ReminderSettings.Keys.muted, store: SharedStore.defaults) private var muteNotifications: Bool = false
    @State private var showNotificationSettings: Bool = false
    @AppStorage("muteTapSound", store: SharedStore.defaults) private var muteTapSound: Bool = false
    /// True when notifications are turned off for the app in iOS Settings.
    @State private var notificationsDenied: Bool = false

    // Wave engine
    @State private var frozenPhase: Double? = nil

    // One-shot surface pulse when level moves (center -> rim)
    @State private var surfacePulseStart: Double? = nil

    private let sfx = SoundFX.shared
    @Environment(\.notificationScheduler) private var notificationScheduler

    private var goalMet: Bool {
        viewModel.dailyGoalOz > 0 && viewModel.intakeOz >= viewModel.dailyGoalOz
    }

    private var fillFraction: CGFloat {
        GlassArt.fillFraction(intake: viewModel.intakeOz, goal: viewModel.dailyGoalOz, perTap: viewModel.ozPerTap)
    }

    private var reminderSettings: ReminderSettings {
        ReminderSettings(
            startHour: notifStartHour,
            endHour: notifEndHour,
            intervalMinutes: notifIntervalMinutes,
            soundFile: notifSoundFile,
            muted: muteNotifications
        )
    }

    private func handleTap() {
        viewModel.resetIfNeeded()
        guard let step = viewModel.nextIntakeStep() else { return }
        surfacePulseStart = Date.timeIntervalSinceReferenceDate
        haptics.impactLight()
        if !muteTapSound { sfx.playSplash() }
        // Less than a full tap when the goal caps it.
        let added = step.newValue - viewModel.intakeOz
        viewModel.intakeOz = step.newValue
        viewModel.recordDrink()
        let unit = viewModel.unit
        let drankAt = viewModel.lastDrinkToday ?? Date()
        Task { await HealthSync.log(added, unit: unit, at: drankAt) }
        announceProgress(reachedGoal: step.reachedGoal)

        if step.reachedGoal {
            viewModel.markGoalMetToday()
            Task {
                try? await Task.sleep(for: .milliseconds(250))
                haptics.success()
            }
        }
        // Goal met: skips the rest of today. Otherwise: next reminder one interval from now.
        refreshNotifications()
    }

    /// Tells VoiceOver users the new total after a tap (the glass's value doesn't re-announce itself).
    private func announceProgress(reachedGoal: Bool) {
        let message = reachedGoal
            ? String(localized: "Goal met!")
            : String(localized: "\(viewModel.intakeOz) of \(viewModel.dailyGoalOz) \(viewModel.unit.spokenName)")
        AccessibilityNotification.Announcement(message).post()
    }

    var body: some View {
        ZStack {
            // The glass fills the screen exactly like the splash photo, so it sits in the same
            // place and size; the label and controls float over the blue above and below it.
            GeometryReader { proxy in
                let layout = GlassCanvasLayout(size: proxy.size)
                ZStack(alignment: .topLeading) {
                    WaterGlassView(
                        targetFraction: fillFraction,
                        frozenPhase: frozenPhase,
                        surfacePulseStart: surfacePulseStart,
                        goalMet: goalMet,
                        layout: layout
                    )
                    interactiveGlass(in: layout.glassRect)
                }
            }
            .ignoresSafeArea()

            // Top-to-bottom: intake label, (the glass shows through the gap), controls.
            VStack(spacing: 0) {
                Text("\(viewModel.intakeOz) / \(viewModel.dailyGoalOz) \(viewModel.unit.label)")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 1)
                    .accessibilityLabel("\(viewModel.intakeOz) of \(viewModel.dailyGoalOz) \(viewModel.unit.spokenName)")
                    .accessibilityIdentifier("intakeLabel")
                    .padding(.top, 56) // leaves room for the gear button above

                Spacer(minLength: 0)

                controls
                    .frame(maxWidth: 500) // keep controls a comfortable width on iPad
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
            }
        }
        .dynamicTypeSize(.large ... .accessibility1)
        .overlay(alignment: .center) {
            WalkthroughOverlay(step: $walkthroughStep, unitLabel: viewModel.unit.label) {
                hasCompletedWalkthrough = true
            }
        }
        .alert("Welcome", isPresented: $showWalkthroughPrompt) {
            Button("No, thanks", role: .cancel) {
                hasCompletedWalkthrough = true
            }
            Button("Yes, show me") {
                walkthroughStep = 1
            }
        } message: {
            Text("Would you like a quick walkthrough of the app?")
        }
        .overlay(alignment: .topTrailing) {
            Button { showNotificationSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
            }
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("settingsButton")
            .allowsHitTesting(walkthroughStep == nil)
            .padding(.trailing, 24)
            .padding(.top, 12)
        }
        .sheet(isPresented: $showNotificationSettings) {
            NotificationSettingsView(
                startHour: $notifStartHour,
                endHour: $notifEndHour,
                intervalMinutes: $notifIntervalMinutes,
                selectedSound: $notifSoundFile,
                muteTapSound: $muteTapSound,
                muteNotifications: $muteNotifications,
                volumeUnit: Binding(
                    get: { viewModel.unit },
                    set: { viewModel.setUnit($0) }
                ),
                notificationsDenied: notificationsDenied,
                onApply: refreshNotifications,
                // Settings shows its own confirmation, then calls this.
                onResetToday: {
                    viewModel.resetToday()
                    refreshNotifications()
                    Task { await HealthSync.deleteDrinks(onDayOf: Date()) }
                },
                onShowHelp: {
                    walkthroughStep = 1
                    hasCompletedWalkthrough = false
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .settingsSheetSizing()
        }
        .onAppear {
            // Older versions allowed an End hour before Start, which schedules nothing.
            if notifEndHour < notifStartHour { notifEndHour = notifStartHour }

            if !hasLaunchedBefore {
                hasLaunchedBefore = true
                if !hasCompletedWalkthrough {
                    // Present after the first frame so the alert attaches reliably.
                    Task { showWalkthroughPrompt = true }
                }
            }

            viewModel.resetIfNeeded()
            if scenePhase != .active {
                let t = Date.timeIntervalSinceReferenceDate
                frozenPhase = WaterGlassView.rippleSeed + t * WaterGlassView.waveSpeed
            }

            Task {
                await requestNotificationPermissionIfReady()
                refreshNotifications()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                frozenPhase = nil
                // Water may have been added from the widget while the app was in the background.
                viewModel.reload()
                viewModel.resetIfNeeded()
                // The user has seen the app, so the reminder badge is no longer needed.
                notificationScheduler.clearBadge()
                // They may have changed notification permission in iOS Settings meanwhile.
                Task { await refreshNotificationsDenied() }
                // Retry any drinks the widget or an earlier attempt couldn't save to Health.
                Task { await HealthSync.savePending() }
            } else {
                let t = Date.timeIntervalSinceReferenceDate
                frozenPhase = WaterGlassView.rippleSeed + t * WaterGlassView.waveSpeed
                // Leaving the app: show the latest intake/goal/units on the Home Screen widgets.
                if newPhase == .background { WidgetCenter.shared.reloadAllTimelines() }
            }
        }
        .onChange(of: hasCompletedWalkthrough) { _, completed in
            // The permission prompt waits until the walkthrough has explained the app.
            if completed {
                Task { await requestNotificationPermissionIfReady() }
            }
        }
        .onChange(of: reminderSettings) { _, _ in
            refreshNotifications()
        }
        .onChange(of: viewModel.dailyGoalOz) { _, _ in
            // Moving the goal below/above today's intake meets/un-meets it.
            if viewModel.syncGoalMetState() {
                refreshNotifications()
            }
        }
        .onChange(of: fillFraction) { _, _ in
            surfacePulseStart = Date.timeIntervalSinceReferenceDate
        }
    }
}

// MARK: - Subviews
private extension ContentView {
    var controls: some View {
        VStack(spacing: 25) {
            HStack(spacing: 10) {
                Text("Tap the glass to add")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .allowsTightening(true)
                Button {
                    showOzPerTapPicker = true
                } label: {
                    Text("\(viewModel.ozPerTap) \(viewModel.unit.label)")
                        .fontWeight(.semibold)
                        .underline()
                }
                .allowsHitTesting(walkthroughStep == nil || walkthroughStep == 3)
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .accessibilityLabel("Amount per tap")
                .accessibilityValue("\(viewModel.ozPerTap) \(viewModel.unit.spokenName)")
                .accessibilityIdentifier("perTapAmountButton")
                .overlay(alignment: .center) {
                    if walkthroughStep == 3 {
                        HandPointerOverlayView(size: CGSize(width: 60, height: 60))
                            .offset(x: -12, y: 8)
                    }
                }
                .popover(isPresented: $showOzPerTapPicker) {
                    perTapPicker
                        // Keep it a small bubble on iPhone instead of a full-screen sheet.
                        .presentationCompactAdaptation(.popover)
                }
            }
            .padding(.top, 8)
            .offset(y: 10)
            .font(.title3)

            HStack {
                Text("Daily goal").font(.title3).foregroundStyle(.white)
                Spacer()
                Text("\(viewModel.dailyGoalOz) \(viewModel.unit.label)").font(.title3).foregroundStyle(.white.opacity(0.75))
            }
            .accessibilityHidden(true) // the slider below announces the same label and value
            Slider(
                value: Binding(
                    get: { Double(viewModel.dailyGoalOz) },
                    set: { viewModel.dailyGoalOz = Int($0.rounded()) }
                ),
                in: Double(viewModel.unit.goalRange.lowerBound)...Double(viewModel.unit.goalRange.upperBound),
                step: Double(viewModel.unit.goalStep)
            )
            .accessibilityLabel("Daily goal")
            .accessibilityValue("\(viewModel.dailyGoalOz) \(viewModel.unit.spokenName)")
            .accessibilityIdentifier("dailyGoalSlider")
            .allowsHitTesting(walkthroughStep == nil || walkthroughStep == 2)
            .tint(.white)
            .overlay(alignment: .center) {
                if walkthroughStep == 2 {
                    HandPointerOverlayView(size: CGSize(width: 66, height: 66))
                        .offset(x: -40, y: 6)
                }
            }
        }
    }

    var perTapPicker: some View {
        VStack(spacing: 16) {
            Text("Water Added Per Tap")
                .font(.title2)
                .accessibilityAddTraits(.isHeader)
            Text("\(viewModel.ozPerTap) \(viewModel.unit.label)")
                .font(.title.weight(.bold))
                .accessibilityHidden(true) // announced by the slider
            Slider(
                value: Binding(
                    get: { Double(viewModel.ozPerTap) },
                    set: { viewModel.ozPerTap = Int($0.rounded()) }
                ),
                in: Double(viewModel.unit.perTapRange.lowerBound)...Double(viewModel.unit.perTapRange.upperBound),
                step: Double(viewModel.unit.perTapStep)
            )
            .accessibilityLabel("Water added per tap")
            .accessibilityValue("\(viewModel.ozPerTap) \(viewModel.unit.spokenName)")
            .tint(.blue)
            Text("Choose between \(viewModel.unit.perTapRange.lowerBound) and \(viewModel.unit.perTapRange.upperBound) \(viewModel.unit.label).")
                .font(.title3)
                .foregroundStyle(.secondary)
            Button("Done") { showOzPerTapPicker = false }
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .dynamicTypeSize(.large ... .accessibility1)
    }

    /// The tappable area over the glass (`rect` is the glass on screen; the glass itself is
    /// drawn by `WaterGlassView` as part of the full-screen background).
    func interactiveGlass(in rect: CGRect) -> some View {
        Color.clear
            .frame(width: rect.width, height: rect.height)
            .contentShape(Rectangle())
            .onTapGesture(perform: handleTap)
            .allowsHitTesting(walkthroughStep == nil || walkthroughStep == 1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Water glass")
            .accessibilityValue("\(viewModel.intakeOz) of \(viewModel.dailyGoalOz) \(viewModel.unit.spokenName)")
            // Once full, tapping adds nothing, so say so instead of "Adds …".
            .accessibilityHint(goalMet ? Text("Goal met!") : Text("Adds \(viewModel.ozPerTap) \(viewModel.unit.spokenName)"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default, handleTap)
            .accessibilityIdentifier("waterGlass")
            .overlay(alignment: .center) {
                if walkthroughStep == 1 {
                    HandPointerOverlayView()
                        .offset(x: -32)
                }
            }
            .position(x: rect.midX, y: rect.midY)
    }

}

// MARK: - Notifications
private extension ContentView {
    /// Reschedules all reminders for the current settings and today's progress.
    /// Timed from today's real last drink, so opening the app or changing a
    /// setting doesn't push the next reminder back.
    func refreshNotifications() {
        reminderSettings.apply(
            to: notificationScheduler,
            goalMetToday: viewModel.isGoalMetToday,
            lastDrinkDate: viewModel.lastDrinkToday
        )
    }

    /// Asks for notification permission, but only once the walkthrough is done or declined,
    /// so the system prompt doesn't appear before the user knows what the app does.
    func requestNotificationPermissionIfReady() async {
        guard hasCompletedWalkthrough else { return }
        await notificationScheduler.requestAuthorization()
        await refreshNotificationsDenied()
    }

    func refreshNotificationsDenied() async {
        notificationsDenied = await notificationScheduler.authorizationStatus() == .denied
    }
}

private extension View {
    /// On iPad the Settings sheet is a centered window whose default height is too short for
    /// the whole list (the App Version / Help row gets cut off). This keeps the standard form
    /// width but sizes the height to fit the list. No effect on iPhone, where sheets fill the screen.
    @ViewBuilder
    func settingsSheetSizing() -> some View {
        if #available(iOS 18.0, *) {
            frame(idealHeight: 720)
                .presentationSizing(.form.fitted(horizontal: false, vertical: true))
        } else {
            self
        }
    }
}

#Preview {
    ContentView()
}
