//
//  ContentView.swift
//  DRINK MORE WATER
//
//  Created by AARON PERILLAT on 10/22/25.
//

import SwiftUI
import CoreGraphics

private struct NotificationSchedulerKey: EnvironmentKey {
    static let defaultValue: NotificationScheduling = NotificationScheduler.shared
}

extension EnvironmentValues {
    var notificationScheduler: NotificationScheduling {
        get { self[NotificationSchedulerKey.self] }
        set { self[NotificationSchedulerKey.self] = newValue }
    }
}

struct ContentView: View {
    private let haptics = HapticsFactory.default()
    private let calculator = FillFractionCalculator()
    @StateObject private var viewModel = WaterIntakeViewModel()

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.displayScale) private var displayScale: CGFloat

    @State private var showResetConfirmation: Bool = false

    // Notification settings (persisted)
    @AppStorage("notifStartHour") private var notifStartHour: Int = 7    // 7 AM
    @AppStorage("notifEndHour") private var notifEndHour: Int = 22       // 10 PM
    @AppStorage("notifSoundFile") private var notifSoundFile: String = "drink more water"
    @State private var showNotificationSettings: Bool = false
    @AppStorage("muteTapSound") private var muteTapSound: Bool = false

    // Mask calibration (mask space: 1 = top, 0 = bottom)
    private let calibratedFullFraction: CGFloat = 1.0 - 0.198522622345337
    private let calibratedEmptyFraction: CGFloat = 1.0 - 0.8799630655586334

    // Wave engine
    @State private var frozenPhase: Double? = nil

    // One-shot surface pulse when level moves (center -> rim)
    @State private var surfacePulseStart: Double? = nil

    private let uiTestButtonFlag = "-UITestsForceButton"
    private let sfx = SoundFX.shared
    @Environment(\.notificationScheduler) private var notificationScheduler

    private var fillFraction: CGFloat {
        let bounds = maskBounds
        let goal = CGFloat(viewModel.dailyGoalOz)
        let intake = CGFloat(viewModel.intakeOz)
        let perTap = CGFloat(viewModel.ozPerTap)
        let calcBounds = WaterMaskBounds(emptyFraction: bounds.emptyFraction, fullFraction: bounds.fullFraction)
        return calculator.fraction(intakeOz: intake, goalOz: goal, bounds: calcBounds, perTapOz: perTap)
    }

    private func todayString() -> String { DateUtils.todayString() }
    private func playSuccessHaptic() { haptics.success() }

    private func handleTap() {
        viewModel.resetIfNeeded()
        guard let step = viewModel.nextIntakeStep() else { return }
        surfacePulseStart = Date.timeIntervalSinceReferenceDate
        haptics.impactLight()
        if !muteTapSound { sfx.playSplash() }
        viewModel.intakeOz = step.newValue

        if step.reachedGoal {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { playSuccessHaptic() }
            // Stop today's notifications and schedule only tomorrow since the goal is met
            scheduleNotificationsForTomorrow()
        } else {
            // Reschedule notifications to be 1 hour from now and then hourly within the window
            rescheduleNotifications(lastDrinkDate: Date())
        }

        if viewModel.lastIntakeDateString.isEmpty { viewModel.lastIntakeDateString = todayString() }
    }

    var body: some View {
        ZStack {
            Color(.systemBlue).ignoresSafeArea()
            interactiveGlass
            VStack {
                Spacer()
                VStack(spacing: 20) {
                    VStack(spacing: 10) {
                        Text("\(viewModel.intakeOz) / \(viewModel.dailyGoalOz) oz")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                            .accessibilityIdentifier("intakeLabel")
                        Text("Tap the glass to add \(viewModel.ozPerTap) oz")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    VStack(spacing: 20) {
                        HStack {
                            Text("Daily goal").font(.headline).foregroundStyle(.white)
                            Spacer()
                            Text("\(viewModel.dailyGoalOz) oz").font(.headline).foregroundStyle(.white.opacity(0.75))
                        }
                        Slider(
                            value: Binding(
                                get: { Double(viewModel.dailyGoalOz) },
                                set: { viewModel.dailyGoalOz = Int($0.rounded()) }
                            ),
                            in: 40...200,
                            step: 10
                        )
                        .tint(.white)
                    }
                }
                .padding(.horizontal, 92)
                .padding(.bottom, 0)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button { showNotificationSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
            }
            .padding(.trailing, 100)
            .padding(.top, 20)
        }
        .alert("Reset today's intake?", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                viewModel.intakeOz = 0
                viewModel.lastIntakeDateString = todayString()
                rescheduleNotifications(lastDrinkDate: Date())
            }
        } message: { Text("This will set today's filled amount back to 0 oz.") }
        .sheet(isPresented: $showNotificationSettings) {
            NotificationSettingsView(
                startHour: $notifStartHour,
                endHour: $notifEndHour,
                selectedSound: $notifSoundFile,
                muteTapSound: $muteTapSound,
                onApply: {
                    // Re-schedule notifications using current or last drink time
                    let lastDrinkDate = Date() // use now as baseline when changing settings
                    rescheduleNotifications(lastDrinkDate: lastDrinkDate)
                },
        onResetToday: {
            showResetConfirmation = true
        }
    )
        }
        .onAppear {
            viewModel.resetIfNeeded()
            if scenePhase != .active {
                let t = Date.timeIntervalSinceReferenceDate
                frozenPhase = WaterGlassView.rippleSeed + t * WaterGlassView.waveSpeed
            }

            Task { @MainActor in
                await notificationScheduler.requestAuthorization()
                let lastDrink: Date? = {
                    if !viewModel.lastIntakeDateString.isEmpty {
                        return Date()
                    }
                    return nil
                }()
                rescheduleNotifications(lastDrinkDate: lastDrink)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                frozenPhase = nil
                viewModel.resetIfNeeded()
            } else {
                let t = Date.timeIntervalSinceReferenceDate
                frozenPhase = WaterGlassView.rippleSeed + t * WaterGlassView.waveSpeed
            }
        }
        .onChange(of: notifStartHour) { _, _ in
            rescheduleNotifications(lastDrinkDate: Date())
        }
        .onChange(of: notifEndHour) { _, _ in
            rescheduleNotifications(lastDrinkDate: Date())
        }
        .onChange(of: notifSoundFile) { _, _ in
            rescheduleNotifications(lastDrinkDate: Date())
        }
        .onChange(of: fillFraction) { _, _ in
            surfacePulseStart = Date.timeIntervalSinceReferenceDate
        }
    }
}

// MARK: - Private helpers
private extension ContentView {
    var shouldUseButtonForTap: Bool {
        ProcessInfo.processInfo.arguments.contains(uiTestButtonFlag)
    }

    var glassRenderer: some View {
        WaterGlassView(
            targetFraction: fillFraction,
            frozenPhase: frozenPhase,
            surfacePulseStart: surfacePulseStart,
            hideUnderwaterText: viewModel.intakeOz >= viewModel.dailyGoalOz
        )
    }

    @ViewBuilder
    var interactiveGlass: some View {
        if shouldUseButtonForTap {
            Button(action: handleTap) { glassRenderer }
                .buttonStyle(NoHighlightButtonStyle())
                .accessibilityLabel("Water glass")
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("waterGlass")
        } else {
            glassRenderer
                .contentShape(Rectangle())
                .onTapGesture(perform: handleTap)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Water glass")
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("waterGlass")
        }
    }

    var maskBounds: WaterMaskBounds {
        WaterMaskBounds(emptyFraction: calibratedEmptyFraction, fullFraction: calibratedFullFraction)
    }
    func rescheduleNotifications(lastDrinkDate: Date?) {
        let scheduler = notificationScheduler
        let startHour = notifStartHour
        let endHour = notifEndHour
        let sound = notifSoundFile
        DispatchQueue.global(qos: .userInitiated).async {
            scheduler.scheduleForTodayAndTomorrow(
                startHour: startHour,
                endHour: endHour,
                soundFile: sound,
                lastDrinkDate: lastDrinkDate
            )
        }
    }
    func scheduleNotificationsForTomorrow() {
        let scheduler = notificationScheduler
        let startHour = notifStartHour
        let endHour = notifEndHour
        let sound = notifSoundFile
        DispatchQueue.global(qos: .userInitiated).async {
            scheduler.scheduleForTomorrow(
                startHour: startHour,
                endHour: endHour,
                soundFile: sound
            )
        }
    }
}

private struct NotificationSettingsView: View {
    @Binding var startHour: Int
    @Binding var endHour: Int
    @Binding var selectedSound: String
    @Binding var muteTapSound: Bool
    var onApply: () -> Void
    var onResetToday: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Notification Window")) {
                    Picker("Start", selection: $startHour) {
                        ForEach(0..<24, id: \.self) { h in
                            Text(hourLabel(h)).tag(h)
                        }
                    }
                    Picker("End", selection: $endHour) {
                        ForEach(0..<24, id: \.self) { h in
                            Text(hourLabel(h)).tag(h)
                        }
                    }
                    Text("Notifications will occur only between the start and end hours.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section(header: Text("Notification Sound")) {
                    Picker("", selection: $selectedSound) {
                        ForEach(availableSoundsBaseNames(), id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    Toggle("Mute Add Water Sound", isOn: $muteTapSound)
                }

                Section {
                    Button(role: .destructive) {
                        onResetToday()
                    } label: {
                        Text("Reset today's intake")
                    }
                }
            }
            .navigationTitle("Notifications")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        onApply()
                        dismiss()
                    }
                }
            }
        }
    }

    private func hourLabel(_ hour24: Int) -> String {
        let h = ((hour24 + 11) % 12) + 1 // 0->12, 13->1
        let isPM = hour24 >= 12
        return "\(h) \(isPM ? "PM" : "AM")"
    }

    private func availableSoundsBaseNames() -> [String] {
        var set = Set<String>()
        let fm = FileManager.default
        func add(from path: String) {
            if let items = try? fm.contentsOfDirectory(atPath: path) {
                for item in items where item.lowercased().hasSuffix(".caf") || item.lowercased().hasSuffix(".aiff") || item.lowercased().hasSuffix(".wav") {
                    let base = (item as NSString).deletingPathExtension
                    set.insert(base)
                }
            }
        }
        if let base = Bundle.main.resourcePath {
            add(from: base)
            let soundsPath = (base as NSString).appendingPathComponent("Sounds")
            add(from: soundsPath)
        }
        if set.isEmpty { set.insert("drink more water") }
        return Array(set).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}



struct SplashView: View {
    var body: some View {
        ZStack {
            Color(.systemBlue)
            Image("drink_more_water")
                .resizable()
                .scaledToFit()
                .frame(width: 551, height: 722)
                .accessibilityHidden(true)
        }
        .ignoresSafeArea()
    }
}

#Preview {
    ContentView()
}

private struct NoHighlightButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label }
}
