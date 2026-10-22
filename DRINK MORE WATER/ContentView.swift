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
    // Walkthrough state
    @AppStorage("hasCompletedWalkthrough") private var hasCompletedWalkthrough: Bool = false
    @AppStorage("hasLaunchedBefore") private var hasLaunchedBefore: Bool = false
    @State private var showWalkthroughPrompt: Bool = false
    @State private var walkthroughStep: Int? = nil // nil = not showing, 1..3 = steps

    private let haptics = HapticsFactory.default()
    private let calculator = FillFractionCalculator()
    @StateObject private var viewModel = WaterIntakeViewModel()

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.displayScale) private var displayScale: CGFloat

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
        viewModel.recordDrink()

        if step.reachedGoal {
            viewModel.markGoalMetToday()
            // Stop today's notifications and schedule only tomorrow since the goal is met
            cancelTodayAndScheduleTomorrow()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { playSuccessHaptic() }
        } else {
            // Reschedule notifications to fire after the selected interval within the window
            rescheduleNotifications(lastDrinkDate: Date())
        }

        if viewModel.lastIntakeDateString.isEmpty { viewModel.lastIntakeDateString = todayString() }
    }

    var body: some View {
        ZStack {
            Color(.systemBlue).ignoresSafeArea()

            // Top-to-bottom: intake label, glass (fills the remaining space), controls.
            VStack(spacing: 0) {
                Text("\(viewModel.intakeOz) / \(viewModel.dailyGoalOz) \(viewModel.unit.label)")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .accessibilityIdentifier("intakeLabel")
                    .padding(.top, 56) // leaves room for the gear button above

                GeometryReader { proxy in
                    interactiveGlass(scale: GlassLayout.scale(toFit: proxy.size))
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }

                VStack(spacing: 25) {
                    VStack(spacing: 8) {
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
                            .accessibilityIdentifier("perTapAmountButton")
                            .overlay(alignment: .center) {
                                if walkthroughStep == 3 {
                                    handPointerOverlay(size: CGSize(width: 60, height: 60))
                                        .offset(x: -12, y: 8)
                                }
                            }
                            .popover(isPresented: $showOzPerTapPicker) {
                                VStack(spacing: 16) {
                                    Text("Water Added Per Tap")
                                        .font(.title2)
                                    Text("\(viewModel.ozPerTap) \(viewModel.unit.label)")
                                        .font(.title.weight(.bold))
                                    Slider(
                                        value: Binding(
                                            get: { Double(viewModel.ozPerTap) },
                                            set: { viewModel.ozPerTap = Int($0.rounded()) }
                                        ),
                                        in: Double(viewModel.unit.perTapRange.lowerBound)...Double(viewModel.unit.perTapRange.upperBound),
                                        step: Double(viewModel.unit.perTapStep)
                                    )
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
                        }
                        .padding(.top, 8)
                        .offset(y: 10)
                        .font(.title3)
                    }

                    HStack {
                        Text("Daily goal").font(.title3).foregroundStyle(.white)
                        Spacer()
                        Text("\(viewModel.dailyGoalOz) \(viewModel.unit.label)").font(.title3).foregroundStyle(.white.opacity(0.75))
                    }
                    Slider(
                        value: Binding(
                            get: { Double(viewModel.dailyGoalOz) },
                            set: { viewModel.dailyGoalOz = Int($0.rounded()) }
                        ),
                        in: Double(viewModel.unit.goalRange.lowerBound)...Double(viewModel.unit.goalRange.upperBound),
                        step: Double(viewModel.unit.goalStep)
                    )
                    .allowsHitTesting(walkthroughStep == nil || walkthroughStep == 2)
                    .tint(.white)
                    .overlay(alignment: .center) {
                        if walkthroughStep == 2 {
                            handPointerOverlay(size: CGSize(width: 66, height: 66))
                                .offset(x: -40, y: 6)
                        }
                    }
                }
                .frame(maxWidth: 500) // keep controls a comfortable width on iPad
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
            }
        }
        .dynamicTypeSize(.large ... .accessibility1)
        .overlay(alignment: .center) {
            walkthroughOverlay
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
            .allowsHitTesting(walkthroughStep == nil)
            .padding(.trailing, 24)
            .padding(.top, 12)
        }
        .alert("Reset today's intake?", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                viewModel.intakeOz = 0
                viewModel.lastIntakeDateString = todayString()
                viewModel.clearGoalMetFlag()
                rescheduleNotifications(lastDrinkDate: Date())
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
                onApply: {
                    // Re-schedule notifications using current or last drink time
                    let lastDrinkDate = Date() // use now as baseline when changing settings
                    rescheduleNotifications(lastDrinkDate: lastDrinkDate)
                },
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
        }
        .onAppear {
            if !hasLaunchedBefore {
                hasLaunchedBefore = true
                if !hasCompletedWalkthrough {
                    DispatchQueue.main.async {
                        showWalkthroughPrompt = true
                    }
                }
            }

            viewModel.resetIfNeeded()
            if scenePhase != .active {
                let t = Date.timeIntervalSinceReferenceDate
                frozenPhase = WaterGlassView.rippleSeed + t * WaterGlassView.waveSpeed
            }

            Task { @MainActor in
                await notificationScheduler.requestAuthorization()
                if viewModel.isGoalMetToday {
                    scheduleNotificationsForTomorrow()
                } else {
                    // Use the real time of today's last tap (not "now"), so simply opening
                    // the app doesn't push the next reminder back.
                    rescheduleNotifications(lastDrinkDate: viewModel.lastDrinkToday)
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                frozenPhase = nil
                viewModel.resetIfNeeded()
                // The user has seen the app, so the reminder badge is no longer needed.
                notificationScheduler.clearBadge()
            } else {
                let t = Date.timeIntervalSinceReferenceDate
                frozenPhase = WaterGlassView.rippleSeed + t * WaterGlassView.waveSpeed
            }
        }
        .onChange(of: notifStartHour) { _, _ in
            if viewModel.isGoalMetToday {
                scheduleNotificationsForTomorrow()
            } else {
                rescheduleNotifications(lastDrinkDate: Date())
            }
        }
        .onChange(of: notifEndHour) { _, _ in
            if viewModel.isGoalMetToday {
                scheduleNotificationsForTomorrow()
            } else {
                rescheduleNotifications(lastDrinkDate: Date())
            }
        }
        .onChange(of: notifSoundFile) { _, _ in
            if viewModel.isGoalMetToday {
                scheduleNotificationsForTomorrow()
            } else {
                rescheduleNotifications(lastDrinkDate: Date())
            }
        }
        .onChange(of: notifIntervalMinutes) { _, _ in
            if viewModel.isGoalMetToday {
                scheduleNotificationsForTomorrow()
            } else {
                rescheduleNotifications(lastDrinkDate: Date())
            }
        }
        .onChange(of: muteNotifications) { _, isMuted in
            if isMuted {
                let scheduler = notificationScheduler
                DispatchQueue.global(qos: .userInitiated).async {
                    scheduler.cancelAll()
                }
            } else if viewModel.isGoalMetToday {
                scheduleNotificationsForTomorrow()
            } else {
                rescheduleNotifications(lastDrinkDate: Date())
            }
        }
        .onChange(of: fillFraction) { _, _ in
            surfacePulseStart = Date.timeIntervalSinceReferenceDate
        }
    }
}

// MARK: - Private helpers
private extension ContentView {
    // Animated hand pointer overlay shown during the walkthrough
    @ViewBuilder
    func handPointerOverlay(size: CGSize = CGSize(width: 80, height: 80)) -> some View {
        HandPointerOverlayView(size: size)
    }

    @ViewBuilder
    var walkthroughOverlay: some View {
        if let step = walkthroughStep,
           let info = walkthroughInfo(for: step) {
            GeometryReader { proxy in
                let textWidth = walkthroughTextWidth(for: proxy.size.width)

                ZStack {
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()
                        .transition(.opacity)

                    ScrollView {
                        VStack(spacing: 16) {
                            Text(info.title)
                                .font(.title2).bold()
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .lineLimit(nil)
                                .frame(width: textWidth, alignment: .center)
                                .fixedSize(horizontal: false, vertical: true)

                            Text(info.detail)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.white.opacity(0.9))
                                .lineLimit(nil)
                                .frame(width: textWidth, alignment: .center)
                                .fixedSize(horizontal: false, vertical: true)

                            HStack(spacing: 16) {
                                Button("Skip") {
                                    walkthroughStep = nil
                                    hasCompletedWalkthrough = true
                                }
                                .buttonStyle(.bordered)
                                .tint(.white)

                                Button(info.isFinal ? "Done" : "Next") {
                                    if info.isFinal {
                                        walkthroughStep = nil
                                        hasCompletedWalkthrough = true
                                    } else {
                                        walkthroughStep = step + 1
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal)
                        .padding(.top, 170)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .accessibilityAddTraits(.isModal)
                .transition(.opacity)
            }
        }
    }

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

    /// The glass drawn at `scale`, laid out in a frame that hugs the visible glass.
    /// `WaterGlassView` always draws in its fixed 551×722 design space (mostly transparent
    /// margins), so it's scaled as a whole and allowed to overflow the frame invisibly.
    func scaledGlass(_ scale: CGFloat) -> some View {
        glassRenderer
            .scaleEffect(scale)
            .frame(
                width: GlassLayout.visibleSize.width * scale,
                height: GlassLayout.visibleSize.height * scale
            )
    }

    @ViewBuilder
    func interactiveGlass(scale: CGFloat) -> some View {
        if shouldUseButtonForTap {
            Button(action: handleTap) { scaledGlass(scale).contentShape(Rectangle()) }
                .allowsHitTesting(walkthroughStep == nil || walkthroughStep == 1)
                .overlay(alignment: .center) {
                    if walkthroughStep == 1 {
                        handPointerOverlay()
                            .offset(x: -32)
                    }
                }
                .buttonStyle(NoHighlightButtonStyle())
                .accessibilityLabel("Water glass")
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("waterGlass")
        } else {
            scaledGlass(scale)
                .contentShape(Rectangle())
                .onTapGesture(perform: handleTap)
                .allowsHitTesting(walkthroughStep == nil || walkthroughStep == 1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Water glass")
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("waterGlass")
                .overlay(alignment: .center) {
                    if walkthroughStep == 1 {
                        handPointerOverlay()
                            .offset(x: -32)
                    }
                }
        }
    }

    var maskBounds: WaterMaskBounds {
        WaterMaskBounds(emptyFraction: calibratedEmptyFraction, fullFraction: calibratedFullFraction)
    }

    func walkthroughInfo(for step: Int) -> (title: String, detail: String, isFinal: Bool)? {
        switch step {
        case 1:
            return (
                "Tap the glass to add water.",
                "When the glass is full, you've met your daily goal.",
                false
            )
        case 2:
            return (
                "Adjust your daily goal.",
                "Use the Daily goal slider to choose how much you want to drink today.",
                false
            )
        case 3:
            return (
                "Set amount per tap.",
                "Change how much water gets added each time by adjusting the \(viewModel.unit.label) value.",
                true
            )
        default:
            return nil
        }
    }

    func walkthroughTextWidth(for totalWidth: CGFloat) -> CGFloat {
        let padding: CGFloat = 48
        let minWidth: CGFloat = 220
        let maxWidth: CGFloat = 360
        let available = totalWidth - padding
        return min(max(available, minWidth), maxWidth)
    }
    func rescheduleNotifications(lastDrinkDate: Date?) {
        let scheduler = notificationScheduler
        let startHour = notifStartHour
        let endHour = notifEndHour
        if muteNotifications {
            scheduler.cancelAll()
            return
        }
        let interval = notifIntervalMinutes
        let sound = notifSoundFile
        DispatchQueue.global(qos: .userInitiated).async {
            scheduler.scheduleForTodayAndTomorrow(
                startHour: startHour,
                endHour: endHour,
                intervalMinutes: interval,
                soundFile: sound,
                lastDrinkDate: lastDrinkDate
            )
        }
    }
    func scheduleNotificationsForTomorrow() {
        let scheduler = notificationScheduler
        let startHour = notifStartHour
        let endHour = notifEndHour
        if muteNotifications {
            scheduler.cancelAll()
            return
        }
        let interval = notifIntervalMinutes
        let sound = notifSoundFile
        DispatchQueue.global(qos: .userInitiated).async {
            scheduler.scheduleForTomorrow(
                startHour: startHour,
                endHour: endHour,
                intervalMinutes: interval,
                soundFile: sound
            )
        }
    }
    func cancelTodayAndScheduleTomorrow() {
        let scheduler = notificationScheduler
        let startHour = notifStartHour
        let endHour = notifEndHour
        if muteNotifications {
            scheduler.cancelAll()
            return
        }
        let interval = notifIntervalMinutes
        let sound = notifSoundFile
        DispatchQueue.global(qos: .userInitiated).async {
            // Remove any pending notifications and schedule tomorrow only
            scheduler.scheduleForTomorrow(
                startHour: startHour,
                endHour: endHour,
                intervalMinutes: interval,
                soundFile: sound
            )
        }
    }
}

// MARK: - Glass Layout
/// Sizing for the glass on the main screen.
enum GlassLayout {
    /// Size of the visible glass inside `WaterGlassView`'s 551×722 design canvas
    /// (measured from the artwork, plus a small margin). The glass is centered in that canvas.
    static let visibleSize = CGSize(width: 300, height: 550)

    /// Upper limit so the glass doesn't get oversized (and blurry) on iPad.
    static let maxScale: CGFloat = 1.6

    /// Scale at which the visible glass fits inside `available`.
    static func scale(toFit available: CGSize) -> CGFloat {
        guard available.width > 0, available.height > 0 else { return 1 }
        let fit = min(available.width / visibleSize.width, available.height / visibleSize.height)
        return min(fit, maxScale)
    }
}

// MARK: - Walkthrough Hand Overlay
private struct HandPointerOverlayView: View {
    let size: CGSize
    private let gesturePeriod: TimeInterval = 1.2
    private let updateInterval: TimeInterval = 1.0 / 30.0

    var body: some View {
        TimelineView(.periodic(from: .now, by: updateInterval)) { context in
            let state = animationState(for: context.date)
            ZStack(alignment: .topLeading) {
                rippleView(state.ripple1)
                    .offset(x: state.tipOffset.width, y: state.tipOffset.height)
                rippleView(state.ripple2)
                    .offset(x: state.tipOffset.width, y: state.tipOffset.height)
                handImage(state.hand)
            }
        }
    }

    private func animationState(for date: Date) -> AnimationState {
        let elapsed = date.timeIntervalSinceReferenceDate
        let normalized = (elapsed.truncatingRemainder(dividingBy: gesturePeriod)) / gesturePeriod
        let secondary = (normalized + 0.5).truncatingRemainder(dividingBy: 1.0)
        let press = sin(normalized * .pi)
        let tipOffset = CGSize(width: size.width * 0.55, height: size.height * 0.18)

        let ripple1 = RippleState(
            size: 24 + 22 * normalized,
            opacity: 0.5 * (1 - normalized),
            lineWidth: 3
        )
        let ripple2 = RippleState(
            size: 18 + 28 * secondary,
            opacity: 0.35 * (1 - secondary),
            lineWidth: 2
        )
        let hand = HandState(
            scale: 2.0 - 0.07 * press,
            offset: CGSize(width: 6 * press, height: 10 * press)
        )

        return AnimationState(
            tipOffset: tipOffset,
            ripple1: ripple1,
            ripple2: ripple2,
            hand: hand
        )
    }

    private func rippleView(_ ripple: RippleState) -> some View {
        Circle()
            .stroke(Color.white.opacity(ripple.opacity), lineWidth: ripple.lineWidth)
            .frame(width: ripple.size, height: ripple.size)
    }

    private func handImage(_ hand: HandState) -> some View {
        Image("hand")
            .resizable()
            .renderingMode(.original)
            .scaledToFit()
            .frame(width: size.width, height: size.height)
            .shadow(color: Color.black.opacity(0.3), radius: 6, x: 0, y: 3)
            .scaleEffect(hand.scale, anchor: UnitPoint.topLeading)
            .offset(x: hand.offset.width, y: hand.offset.height)
            .opacity(0.75)
    }

    private struct AnimationState {
        let tipOffset: CGSize
        let ripple1: RippleState
        let ripple2: RippleState
        let hand: HandState
    }

    private struct RippleState {
        let size: CGFloat
        let opacity: Double
        let lineWidth: CGFloat
    }

    private struct HandState {
        let scale: CGFloat
        let offset: CGSize
    }
}

private struct NotificationSettingsView: View {
    @Binding var startHour: Int
    @Binding var endHour: Int
    @Binding var intervalMinutes: Int
    @Binding var selectedSound: String
    @Binding var muteTapSound: Bool
    @Binding var muteNotifications: Bool
    @Binding var volumeUnit: VolumeUnit
    var onApply: () -> Void
    var onResetToday: () -> Void
    var onShowHelp: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("General")) {
                    LabeledContent("Units") {
                        Picker("Units", selection: $volumeUnit) {
                            Text("oz").tag(VolumeUnit.oz)
                            Text("ml").tag(VolumeUnit.ml)
                        }
                        .pickerStyle(.segmented)
                        .fixedSize()
                        .accessibilityIdentifier("volumeUnitPicker")
                    }
                    Toggle("Mute Add Water Sound", isOn: $muteTapSound)
                }

                Section(
                    header: Text("Reminders"),
                    footer: Text("Reminders only occur between the start and end hours.")
                ) {
                    Toggle("Mute Notifications", isOn: $muteNotifications)
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
                    Picker("Frequency", selection: $intervalMinutes) {
                        ForEach(reminderChoices, id: \.self) { value in
                            Text(intervalLabel(value)).tag(value)
                        }
                    }
                    Picker("Sound", selection: $selectedSound) {
                        // Explicit none option (empty string means no sound)
                        Text("None").tag("")
                        ForEach(availableSoundsBaseNames(), id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                }

                Section {
                    Button(role: .destructive) {
                        onResetToday()
                    } label: {
                        Text("Reset today's intake")
                    }
                } footer: {
                    HStack {
                        Text("App Version \(versionLabel)")
                        Spacer()
                        Button {
                            dismiss()
                            DispatchQueue.main.async {
                                onShowHelp()
                            }
                        } label: {
                            Label("Help", systemImage: "questionmark.circle")
                                .labelStyle(.titleAndIcon)
                        }
                        .buttonStyle(.bordered)
                        .textCase(nil)
                    }
                    .padding(.top, 8)
                }
            }
            .listSectionSpacing(.compact)
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
        .navigationViewStyle(StackNavigationViewStyle())
        .dynamicTypeSize(.large ... .accessibility1)
    }

    private func hourLabel(_ hour24: Int) -> String {
        let h = ((hour24 + 11) % 12) + 1 // 0->12, 13->1
        let isPM = hour24 >= 12
        return "\(h) \(isPM ? "PM" : "AM")"
    }

    private let oncePerDaySentinel = 0

    private var reminderChoices: [Int] {
        var base = [oncePerDaySentinel, 15, 30, 45, 60, 90, 120]
        if !base.contains(intervalMinutes) {
            base.append(intervalMinutes)
        }
        return base.sorted()
    }

    private func intervalLabel(_ minutes: Int) -> String {
        if minutes == oncePerDaySentinel {
            return "Once a day"
        }
        if minutes < 60 {
            return "Every \(minutes) minutes"
        }
        if minutes % 60 == 0 {
            let hours = minutes / 60
            let suffix = hours == 1 ? "hour" : "hours"
            return "Every \(hours) \(suffix)"
        }
        return "Every \(minutes) minutes"
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

    private var versionLabel: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String
        let build = info?["CFBundleVersion"] as? String
        switch (short, build) {
        case let (v?, b?):
            return "\(v) (\(b))"
        case let (v?, nil):
            return v
        case let (nil, b?):
            return b
        default:
            return "Unknown"
        }
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
