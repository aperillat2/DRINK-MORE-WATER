//
//  ContentView.swift
//  DRINK MORE WATER
//
//  Created by AARON PERILLAT on 10/22/25.
//

import SwiftUI
import CoreGraphics
#if canImport(UIKit)
import UIKit
#endif
struct ContentView: View {
    private let haptics = HapticsFactory.default()
    private let calculator = FillFractionCalculator()
    @StateObject private var viewModel = WaterIntakeViewModel()

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.displayScale) private var displayScale: CGFloat

    @State private var showResetConfirmation: Bool = false
    @State private var showCalibration: Bool = false
    @State private var calTopY: CGFloat = 0
    @State private var calBottomY: CGFloat = 0

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
    private let notificationScheduler = NotificationScheduler.shared

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

        // Reschedule notifications to be 1 hour from now and then hourly within the window
        notificationScheduler.scheduleForTodayAndTomorrow(
            startHour: notifStartHour,
            endHour: notifEndHour,
            soundFile: notifSoundFile,
            lastDrinkDate: Date()
        )

        if step.reachedGoal { DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { playSuccessHaptic() } }
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
        .overlay(alignment: .topLeading) {
            if showCalibration {
                Button("Log Fractions") {
                    let topF = yToMaskFraction(calTopY)
                    let bottomF = yToMaskFraction(calBottomY)
                    print("Calibration fractions: fullFraction(top)=\(topF), emptyFraction(bottom)=\(bottomF)")
                }
                .font(.caption).bold()
                .padding(8)
                .background(Color.red.opacity(0.9))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.leading, 16)
                .padding(.top, 16)
            }
        }
        .alert("Reset today's intake?", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                viewModel.intakeOz = 0
                viewModel.lastIntakeDateString = todayString()
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
                    notificationScheduler.scheduleForTodayAndTomorrow(
                        startHour: notifStartHour,
                        endHour: notifEndHour,
                        soundFile: notifSoundFile,
                        lastDrinkDate: lastDrinkDate
                    )
                },
                onResetToday: {
                    showResetConfirmation = true
                }
            )
        }
        .onAppear {
            viewModel.resetIfNeeded()
            let metrics = WaterGlassMetrics.self
            let innerHeight = metrics.glassSize.height - 163
            let innerCenterY = metrics.glassVerticalNudge - 26
            calTopY = innerCenterY - innerHeight / 2
            calBottomY = innerCenterY + innerHeight / 2
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
                notificationScheduler.scheduleForTodayAndTomorrow(
                    startHour: notifStartHour,
                    endHour: notifEndHour,
                    soundFile: notifSoundFile,
                    lastDrinkDate: lastDrink
                )
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
            notificationScheduler.scheduleForTodayAndTomorrow(
                startHour: notifStartHour,
                endHour: notifEndHour,
                soundFile: notifSoundFile,
                lastDrinkDate: Date()
            )
        }
        .onChange(of: notifEndHour) { _, _ in
            notificationScheduler.scheduleForTodayAndTomorrow(
                startHour: notifStartHour,
                endHour: notifEndHour,
                soundFile: notifSoundFile,
                lastDrinkDate: Date()
            )
        }
        .onChange(of: notifSoundFile) { _, _ in
            notificationScheduler.scheduleForTodayAndTomorrow(
                startHour: notifStartHour,
                endHour: notifEndHour,
                soundFile: notifSoundFile,
                lastDrinkDate: Date()
            )
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
            surfacePulseStart: surfacePulseStart
        )
        .overlay(alignment: .center) {
            if showCalibration {
                calibrationOverlay
            }
        }
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
    func yToMaskFraction(_ y: CGFloat) -> CGFloat {
        let yInGlassSpace = y - (WaterGlassMetrics.glassVerticalNudge + WaterGlassMetrics.maskVerticalOffset)
        let frac = yInGlassSpace / WaterGlassMetrics.glassSize.height
        return max(0, min(1, frac))
    }

    @ViewBuilder
    var calibrationOverlay: some View {
        let glassSize = WaterGlassMetrics.glassSize
        Group {
            Rectangle()
                .fill(Color.red)
                .frame(width: glassSize.width, height: 3)
                .position(x: glassSize.width / 2, y: calTopY)
                .overlay(alignment: .trailing) {
                    Text("Top: y=\(Int(calTopY)) frac=\(String(format: "%.4f", yToMaskFraction(calTopY)))")
                        .font(.caption2).bold().foregroundColor(.white)
                        .padding(6).background(Color.red.opacity(0.7))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .offset(x: -8, y: -14)
                }

            Rectangle()
                .fill(Color.red)
                .frame(width: glassSize.width, height: 3)
                .position(x: glassSize.width / 2, y: calBottomY)
                .overlay(alignment: .trailing) {
                    Text("Bottom: y=\(Int(calBottomY)) frac=\(String(format: "%.4f", yToMaskFraction(calBottomY)))")
                        .font(.caption2).bold().foregroundColor(.white)
                        .padding(6).background(Color.red.opacity(0.7))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .offset(x: -8, y: -14)
                }

            Circle().fill(Color.red).frame(width: 10, height: 10).position(x: glassSize.width - 8, y: calTopY)
            Circle().fill(Color.red).frame(width: 10, height: 10).position(x: glassSize.width - 8, y: calBottomY)

            Color.clear
                .frame(width: glassSize.width, height: glassSize.height)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let y = value.location.y
                            if abs(y - calTopY) <= abs(y - calBottomY) { calTopY = y } else { calBottomY = y }
                        }
                )

            Button("Log Fractions") {
                let topF = yToMaskFraction(calTopY)
                let bottomF = yToMaskFraction(calBottomY)
                print("Calibration fractions: fullFraction(top)=\(topF), emptyFraction(bottom)=\(bottomF)")
            }
            .font(.caption).bold()
            .padding(6)
            .background(Color.red.opacity(0.8))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .position(x: 100, y: 24)
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
