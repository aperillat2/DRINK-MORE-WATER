//
//  ContentView.swift
//  DRINK MORE WATER
//
//  Created by AARON PERILLAT on 10/22/25.
//

import SwiftUI
import CoreGraphics
import UserNotifications

struct ContentView: View {
    // Walkthrough state
    @AppStorage("hasCompletedWalkthrough") private var hasCompletedWalkthrough: Bool = false
    @AppStorage("hasLaunchedBefore") private var hasLaunchedBefore: Bool = false
    @State private var showWalkthroughPrompt: Bool = false
    @State private var walkthroughStep: Int? = nil // nil = not showing, 1..3 = steps

    private let haptics = HapticsFactory.default()
    private let calculator = FillFractionCalculator()
    @State private var viewModel = WaterIntakeViewModel()

    @Environment(\.scenePhase) private var scenePhase

    @State private var showResetConfirmation: Bool = false
    @State private var showOzPerTapPicker: Bool = false

    // Notification settings (persisted)
    @AppStorage("notifStartHour") private var notifStartHour: Int = 7    // 7 AM
    @AppStorage("notifEndHour") private var notifEndHour: Int = 20       // 8 PM
    @AppStorage("notifSoundFile") private var notifSoundFile: String = "drink more water"
    @AppStorage("notifIntervalMinutes") private var notifIntervalMinutes: Int = 60
    @AppStorage("muteNotifications") private var muteNotifications: Bool = false
    @State private var showNotificationSettings: Bool = false
    @AppStorage("muteTapSound") private var muteTapSound: Bool = false
    /// True when notifications are turned off for the app in iOS Settings.
    @State private var notificationsDenied: Bool = false

    // Mask calibration (mask space: 1 = top, 0 = bottom)
    private let calibratedFullFraction: CGFloat = 1.0 - 0.198522622345337
    private let calibratedEmptyFraction: CGFloat = 1.0 - 0.8799630655586334

    // Wave engine
    @State private var frozenPhase: Double? = nil

    // One-shot surface pulse when level moves (center -> rim)
    @State private var surfacePulseStart: Double? = nil

    private let sfx = SoundFX.shared
    @Environment(\.notificationScheduler) private var notificationScheduler

    private var fillFraction: CGFloat {
        calculator.fraction(
            intakeOz: CGFloat(viewModel.intakeOz),
            goalOz: CGFloat(viewModel.dailyGoalOz),
            bounds: maskBounds,
            perTapOz: CGFloat(viewModel.ozPerTap)
        )
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
        viewModel.intakeOz = step.newValue
        viewModel.recordDrink()

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

    var body: some View {
        ZStack {
            Color(.systemBlue).ignoresSafeArea()

            // Top-to-bottom: intake label, glass (fills the remaining space), controls.
            VStack(spacing: 0) {
                Text("\(viewModel.intakeOz) / \(viewModel.dailyGoalOz) \(viewModel.unit.label)")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .accessibilityLabel("\(viewModel.intakeOz) of \(viewModel.dailyGoalOz) \(viewModel.unit.spokenName)")
                    .accessibilityIdentifier("intakeLabel")
                    .padding(.top, 56) // leaves room for the gear button above

                GeometryReader { proxy in
                    interactiveGlass(scale: GlassLayout.scale(toFit: proxy.size))
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }

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
        .alert("Reset today's intake?", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                viewModel.resetToday()
                refreshNotifications()
            }
        } message: { Text("This will set today's filled amount back to 0 \(viewModel.unit.label).") }
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
                onResetToday: {
                    showResetConfirmation = true
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
                viewModel.resetIfNeeded()
                // The user has seen the app, so the reminder badge is no longer needed.
                notificationScheduler.clearBadge()
                // They may have changed notification permission in iOS Settings meanwhile.
                Task { await refreshNotificationsDenied() }
            } else {
                let t = Date.timeIntervalSinceReferenceDate
                frozenPhase = WaterGlassView.rippleSeed + t * WaterGlassView.waveSpeed
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

    /// The glass drawn at `scale`, laid out in a frame that hugs the visible glass.
    /// `WaterGlassView` always draws in its fixed 551×722 design space (mostly transparent
    /// margins), so it's scaled as a whole and allowed to overflow the frame invisibly.
    func interactiveGlass(scale: CGFloat) -> some View {
        WaterGlassView(
            targetFraction: fillFraction,
            frozenPhase: frozenPhase,
            surfacePulseStart: surfacePulseStart,
            hideUnderwaterText: viewModel.intakeOz >= viewModel.dailyGoalOz
        )
        .scaleEffect(scale)
        .frame(
            width: GlassLayout.visibleSize.width * scale,
            height: GlassLayout.visibleSize.height * scale
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: handleTap)
        .allowsHitTesting(walkthroughStep == nil || walkthroughStep == 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Water glass")
        .accessibilityValue("\(viewModel.intakeOz) of \(viewModel.dailyGoalOz) \(viewModel.unit.spokenName)")
        .accessibilityHint("Adds \(viewModel.ozPerTap) \(viewModel.unit.spokenName)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, handleTap)
        .accessibilityIdentifier("waterGlass")
        .overlay(alignment: .center) {
            if walkthroughStep == 1 {
                HandPointerOverlayView()
                    .offset(x: -32)
            }
        }
    }

    var maskBounds: WaterMaskBounds {
        WaterMaskBounds(emptyFraction: calibratedEmptyFraction, fullFraction: calibratedFullFraction)
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
