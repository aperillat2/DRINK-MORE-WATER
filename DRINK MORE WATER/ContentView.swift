//
//  ContentView.swift
//  DRINK MORE WATER
//
//  Created by AARON PERILLAT on 10/22/25.
//

import SwiftUI
import CoreGraphics
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif
import UserNotifications

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

    // Mask calibration (MaskAnalyzer space: 1 = top, 0 = bottom)
    private let calibratedFullFraction: CGFloat = 1.0 - 0.198522622345337
    private let calibratedEmptyFraction: CGFloat = 1.0 - 0.8799630655586334

    // Wave engine
    private static let rippleSeed = Double.random(in: 0...(2 * .pi))
    private let waveSpeed: Double = 2.3
    @State private var frozenPhase: Double? = nil

    // One-shot surface pulse when level moves (center -> rim)
    @State private var surfacePulseStart: Double? = nil
    private let surfacePulseDuration: Double = 0.9
    private let surfacePulseSpeed: Double = 1.35

    // Level animation (drives water fill + surface together)
    @State private var displayedFraction: CGFloat = 0        // what the UI shows
    @State private var levelAnimFrom: CGFloat = 0
    @State private var levelAnimTo: CGFloat = 0
    @State private var levelAnimStart: Double? = nil
    private let levelAnimDuration: Double = 1.5

    // Layout
    private let glassSize = CGSize(width: 551, height: 722)
    private let glassVerticalNudge: CGFloat = -20
    private let textScale: CGFloat = 0.54
    private let textOffset: CGSize = CGSize(width: 0, height: 58)
    private let maskVerticalOffset: CGFloat = 5
    private let maskHorizontalOffset: CGFloat = 2
    private let uiTestButtonFlag = "-UITestsForceButton"

    // Tint applied only to the underwater letters (leave water tint unchanged)
    private let underwaterTextTint: Color = Color(hue: 0.58, saturation: 0.5, brightness: 1.0)
    private let sfx = SoundFX.shared
    private let notificationScheduler = NotificationScheduler.shared

    private var fillFraction: CGFloat {
        let bounds = maskBounds
        let goal = CGFloat(viewModel.dailyGoalOz)
        let intake = CGFloat(viewModel.intakeOz)
        let perTap = CGFloat(viewModel.ozPerTap)
        let calcBounds = CalcMaskBounds(emptyFraction: bounds.emptyFraction, fullFraction: bounds.fullFraction)
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
            let innerHeight = glassSize.height - 163
            let innerCenterY = glassVerticalNudge - 26
            calTopY = innerCenterY - innerHeight / 2
            calBottomY = innerCenterY + innerHeight / 2
            if scenePhase != .active {
                let t = Date.timeIntervalSinceReferenceDate
                frozenPhase = Self.rippleSeed + t * waveSpeed
            }
            #if os(iOS)
            _ = MaskAnalyzer.shared.prepare()
            #endif

            // Initialize level animation state
            let cur = clamp01(fillFraction)
            displayedFraction = cur
            levelAnimFrom = cur
            levelAnimTo = cur
            levelAnimStart = nil
            
            // Notifications: request auth and schedule initial plan for today & tomorrow
            Task { @MainActor in
                await notificationScheduler.requestAuthorization()
                let lastDrink: Date? = {
                    // If lastIntakeDateString is today and intake > 0, treat as last drink at now for initial schedule
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
                frozenPhase = Self.rippleSeed + t * waveSpeed
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
        // Start a new 1.0 s ramp whenever the model fraction changes
        .onChange(of: fillFraction) { _, new in
            let target = clamp01(new)
            let now = Date.timeIntervalSinceReferenceDate

            // Compute the current on-screen fraction (respecting any in-flight animation)
            let current: CGFloat
            if let start = levelAnimStart {
                let raw = min(max((now - start) / levelAnimDuration, 0), 1)
                let eased = easeOutCubic(raw)
                current = levelAnimFrom + CGFloat(eased) * (levelAnimTo - levelAnimFrom)
            } else {
                current = displayedFraction
            }

            levelAnimFrom = clamp01(current)
            levelAnimTo = target
            levelAnimStart = now
            surfacePulseStart = now
        }
    }
}

// MARK: - Private helpers
private extension ContentView {
    var shouldUseButtonForTap: Bool {
        ProcessInfo.processInfo.arguments.contains(uiTestButtonFlag)
    }

    var surfaceMaskAspect: CGFloat {
        #if os(iOS)
        if let cg = UIImage(named: "glass_surface_mask")?.cgImage {
            return CGFloat(cg.height) / CGFloat(cg.width)
        }
        #endif
        return 88.0 / 480.0
    }
    
    // Clamp helper
    func clamp01(_ x: CGFloat) -> CGFloat { max(0, min(1, x)) }
    // Ease-out cubic (fast start, gentle finish)
    func easeOutCubic(_ t: Double) -> Double {
        let u = max(0.0, min(1.0, t))
        let inv = 1.0 - u
        return 1.0 - inv * inv * inv
    }
    
    private final class SoundFX {
        static let shared = SoundFX()
        private var splashPlayer: AVAudioPlayer?
        private let splashVolume: Float = 0.08

        private init() {
            #if !targetEnvironment(simulator)
            try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try? AVAudioSession.sharedInstance().setActive(true, options: [])
            #endif
            preloadPour()
        }

        private func preloadPour() {
            let bundle = Bundle.main
            // Works whether "Sounds" is a real folder (blue) or just a group (yellow)
            let url =
                bundle.url(forResource: "water pour 2", withExtension: "caf", subdirectory: "Sounds") ??
                bundle.url(forResource: "water pour 2", withExtension: "caf")
            guard let url else { return }
            splashPlayer = try? AVAudioPlayer(contentsOf: url)
            splashPlayer?.volume = splashVolume
            splashPlayer?.prepareToPlay()
        }

        func playSplash() {
            if splashPlayer == nil { preloadPour() }
            splashPlayer?.stop()
            splashPlayer?.currentTime = 0
            splashPlayer?.volume = splashVolume
            splashPlayer?.play()
        }
    }

    // Extracted to reduce type-checking load
    func makeGlassStack(
        fraction: CGFloat,
        ripplePhase: Double,
        widthFraction: CGFloat,
        surfaceMaskAspect: CGFloat,
        waterTopAligned: CGFloat,
        now: Double,
        fillMask: AnyView
    ) -> AnyView {
        AnyView(
            ZStack {
                // Text with underwater refraction
                refractedGlassText(
                    fraction: fraction,
                    ripplePhase: ripplePhase,
                    widthFraction: widthFraction,
                    surfaceMaskAspect: surfaceMaskAspect
                )
                .transaction { $0.animation = nil }
                .animation(nil, value: fraction)

                // Fill masked by (glass - surface)
                WaterFillRenderer(
                    glassSize: glassSize,
                    verticalOffset: glassVerticalNudge,
                    waterTopY: waterTopAligned,
                    baseColor: Color(.sRGB, red: 0.78, green: 0.88, blue: 0.98, opacity: 0.42),
                    highlightColor: Color.white.opacity(0.9)
                )
                .mask(fillMask)
                .allowsHitTesting(false)

                // Surface overlay (no implicit animation)
                WaterSurfaceOverlay(
                    glassSize: glassSize,
                    verticalOffset: glassVerticalNudge,
                    waterY: waterTopAligned,
                    widthFraction: widthFraction,
                    surfaceMaskAspect: surfaceMaskAspect,
                    ripplePhase: ripplePhase,
                    pulseStart: surfacePulseStart,
                    now: now,
                    pulseDuration: surfacePulseDuration,
                    pulseSpeed: surfacePulseSpeed
                )
                .mask(glassMaskAlignedToFill())
                .transaction { $0.animation = nil }
                .animation(nil, value: waterTopAligned)
                .allowsHitTesting(false)

                if showCalibration { calibrationOverlay.zIndex(1000) }

                let px = 1.0 / max(displayScale, 1)
                let contentY = round(glassVerticalNudge / px) * px

                // Raise positive bias, lower negative
                let shimmerMaskBiasY: CGFloat = 0

                GlassLightShimmer(glassSize: glassSize)
                    .offset(y: contentY)
                    .mask(glassMaskForOverlays(biasY: shimmerMaskBiasY))
                    .blendMode(.screen)
                    .allowsHitTesting(false)

                GlassInnerShadow(glassSize: glassSize)
                    .offset(y: contentY)
                    .mask(glassMaskForOverlays(biasY: shimmerMaskBiasY))
                    .blendMode(.multiply)
                    .allowsHitTesting(false)

                Image("empty_glass")
                    .resizable()
                    .scaledToFit()
                    .frame(width: glassSize.width, height: glassSize.height)
                    .offset(y: glassVerticalNudge)
                    .accessibilityHidden(true)
            }
        )
    }

    // Extracted to reduce type-checking load
    func makeFillMask(waterTopAligned: CGFloat, widthFraction: CGFloat, surfaceMaskAspect: CGFloat) -> AnyView {
        AnyView(
            ZStack {
                glassMaskAlignedToFill()
                WaterSurfaceCutout(
                    glassSize: glassSize,
                    verticalOffset: glassVerticalNudge,
                    waterY: waterTopAligned,
                    widthFraction: widthFraction,
                    surfaceMaskAspect: surfaceMaskAspect
                )
                .blendMode(.destinationOut)
                .transaction { $0.animation = nil }
                .animation(nil, value: waterTopAligned)
            }
            .compositingGroup()
            .drawingGroup()
        )
    }

    @ViewBuilder
    var interactiveGlass: some View {
        if shouldUseButtonForTap {
            Button(action: handleTap) { glassVisual }
                .buttonStyle(NoHighlightButtonStyle())
                .accessibilityLabel("Water glass")
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("waterGlass")
        } else {
            glassVisual
                .contentShape(Rectangle())
                .onTapGesture(perform: handleTap)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Water glass")
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("waterGlass")
        }
    }
    
    // Helper: mask aligned to glass + tweak
    func glassMaskForOverlays(biasY: CGFloat = 0) -> some View {
        let px = 1.0 / max(displayScale, 1)
        let y = round((glassVerticalNudge + maskVerticalOffset + biasY) / px) * px
        return Image("glass_mask")
            .resizable()
            .scaledToFit()
            .frame(width: glassSize.width, height: glassSize.height)
            .offset(x: maskHorizontalOffset, y: y)
    }

    // Further type-erasure to help the compiler in the TimelineView closure
    func buildGlassContent(now: Double) -> AnyView {
        // Drive a manual ease-out ramp independent of implicit animations without mutating @State during render.
        let fraction: CGFloat
        if let start = levelAnimStart {
            let raw = min(max((now - start) / levelAnimDuration, 0), 1)
            let eased = easeOutCubic(raw)
            fraction = clamp01(levelAnimFrom + CGFloat(eased) * (levelAnimTo - levelAnimFrom))
            if raw >= 1 {
                // Defer state updates to outside the render pass
                DispatchQueue.main.async {
                    if levelAnimStart != nil {
                        levelAnimStart = nil
                        displayedFraction = clamp01(levelAnimTo)
                    }
                }
            }
        } else {
            // When not animating, continue from the last displayed value
            fraction = clamp01(displayedFraction)
        }

        let ripplePhase = frozenPhase ?? (Self.rippleSeed + now * waveSpeed)

        // Single source of truth for water top
        let waterTop = glassSize.height * (1 - fraction)
        let px = 1.0 / max(displayScale, 1)
        let waterTopAligned = round(waterTop / px) * px

        #if os(iOS)
        let yFrac = max(0, min(1, waterTopAligned / glassSize.height))
        let widthFraction = GlassWidthAnalyzer.shared.widthFraction(atYFraction: yFrac) ?? 1.0
        #else
        let widthFraction: CGFloat = 1.0
        #endif

        let fillMask = makeFillMask(
            waterTopAligned: waterTopAligned,
            widthFraction: widthFraction,
            surfaceMaskAspect: surfaceMaskAspect
        )

        let content = makeGlassStack(
            fraction: fraction,
            ripplePhase: ripplePhase,
            widthFraction: widthFraction,
            surfaceMaskAspect: surfaceMaskAspect,
            waterTopAligned: waterTopAligned,
            now: now,
            fillMask: fillMask
        )
        return content
    }

    var glassVisual: some View {
        #if targetEnvironment(simulator)
        let fps: Double = 20.0
        #else
        let fps: Double = 30.0
        #endif
        return TimelineView(.periodic(from: .now, by: 1.0 / fps)) { _ in
            let now = Date.timeIntervalSinceReferenceDate
            buildGlassContent(now: now)
        }
    }

    var maskBounds: MaskBounds {
        MaskBounds(emptyFraction: calibratedEmptyFraction, fullFraction: calibratedFullFraction)
    }

    func glassMask() -> some View {
        Image("glass_mask")
            .resizable()
            .scaledToFit()
            .frame(width: glassSize.width, height: glassSize.height)
            .offset(x: maskHorizontalOffset, y: glassVerticalNudge + maskVerticalOffset)
    }

    func glassMaskAlignedToFill() -> some View {
        Image("glass_mask")
            .resizable()
            .scaledToFit()
            .frame(width: glassSize.width, height: glassSize.height)
            .offset(x: maskHorizontalOffset, y: glassVerticalNudge)
    }

    // Pixel-aligned relative offset to start the refraction below the surface band
    func refractionSeamOffset(waterY: CGFloat, widthFraction: CGFloat) -> CGFloat {
        let px = 1.0 / max(displayScale, 1)
        let surfaceWidth = max(1, glassSize.width * widthFraction)
        let depth = min(max(waterY / glassSize.height, 0), 1)
        let foreshortenY: CGFloat = 1.0 - 0.08 * depth
        let surfaceHeight = max(1, surfaceWidth * surfaceMaskAspect * foreshortenY)
        let rel = surfaceHeight * 0.48                // ~18% of ellipse height
        let off = max(px, min(rel, 24))               // clamp
        return round(off / px) * px                    // pixel align
    }

    func refractedGlassText(
        fraction: CGFloat,
        ripplePhase: Double,
        widthFraction: CGFloat,
        surfaceMaskAspect: CGFloat
    ) -> AnyView {
        let clamped = max(0, min(fraction, 1))
        let realWaterY = max(0, min(glassSize.height, glassSize.height * (1 - clamped)))

        // Underwater starts below the real waterline
        let seam = refractionSeamOffset(waterY: realWaterY, widthFraction: widthFraction)
        let underwaterStartY = realWaterY + seam

        // Above-water mask uses the real waterline (no offset)
        let px = 1.0 / max(displayScale, 1)
        let localAbove = max(0, min(glassSize.height, realWaterY - textOffset.height))
        let aboveAligned = round(localAbove / px) * px

        return AnyView(
            ZStack {
                // ABOVE WATER — mask height changes instantly (no implicit tween)
                Image("glass_text")
                    .resizable()
                    .scaledToFit()
                    .frame(width: glassSize.width, height: glassSize.height)
                    .scaleEffect(textScale)
                    .offset(y: glassVerticalNudge)
                    .offset(x: textOffset.width, y: textOffset.height)
                    .mask(
                        Rectangle()
                            .frame(width: glassSize.width, height: aboveAligned)
                            .offset(y: glassVerticalNudge + textOffset.height - glassSize.height/2 + aboveAligned/2)
                    )
                    .transaction { $0.animation = nil }
                    .animation(nil, value: aboveAligned)
                    .animation(nil, value: fraction)
                    .accessibilityHidden(true)

                // UNDER WATER — starts at offset seam
                RefractedTextView(
                    imageName: "glass_text",
                    glassSize: glassSize,
                    textScale: textScale,
                    textOffset: textOffset,
                    verticalNudge: glassVerticalNudge,
                    waterline: underwaterStartY,
                    ripplePhase: ripplePhase,
                    rippleAmplitude: 4
                )
                .mask(glassMask())
                .colorMultiply(underwaterTextTint)
                .transaction { $0.animation = nil }
                .animation(nil, value: fraction)
                .accessibilityHidden(true)
            }
        )
    }


    func yToMaskFraction(_ y: CGFloat) -> CGFloat {
        let yInGlassSpace = y - (glassVerticalNudge + maskVerticalOffset)
        let frac = yInGlassSpace / glassSize.height
        return max(0, min(1, frac))
    }

    @ViewBuilder
    var calibrationOverlay: some View {
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

// MARK: - Cutout to subtract surface from fill (used inside the fill mask)
private struct WaterSurfaceCutout: View {
    let glassSize: CGSize
    let verticalOffset: CGFloat
    let waterY: CGFloat
    let widthFraction: CGFloat
    let surfaceMaskAspect: CGFloat
    @Environment(\.displayScale) private var displayScale: CGFloat

    var body: some View {
        let surfaceWidth  = max(1, glassSize.width * widthFraction)
        let depth = min(max(waterY / glassSize.height, 0), 1)
        let foreshortenY: CGFloat = 1.0 - 0.08 * depth
        let baseHeight = max(1, surfaceWidth * surfaceMaskAspect * foreshortenY)

        // Overscan upward only to hide seam; keep bottom aligned
        let px = 1.0 / max(displayScale, 1)
        let overscanUp = 3 * px
        let cutoutHeight = baseHeight + overscanUp
        let cutoutCenterY = waterY - overscanUp / 2

        Rectangle()
            .fill(.white)
            .frame(width: surfaceWidth, height: cutoutHeight)
            .mask(
                Image("glass_surface_mask")
                    .resizable()
                    .frame(width: surfaceWidth, height: cutoutHeight)
            )
            .frame(width: glassSize.width, height: glassSize.height)
            .position(x: glassSize.width / 2, y: cutoutCenterY)
            .offset(y: verticalOffset)
            .allowsHitTesting(false)
    }
}

// MARK: - Visible surface overlay
private struct WaterSurfaceOverlay: View {
    let glassSize: CGSize
    let verticalOffset: CGFloat
    let waterY: CGFloat
    let widthFraction: CGFloat
    let surfaceMaskAspect: CGFloat
    let ripplePhase: Double
    let pulseStart: Double?
    let now: Double
    let pulseDuration: Double
    let pulseSpeed: Double

    var body: some View {
        let surfaceWidth = max(1, glassSize.width * widthFraction)
        let depth = min(max(waterY / glassSize.height, 0), 1)
        let foreshortenY: CGFloat = 1.0 - 0.08 * depth
        let surfaceHeight = max(1, surfaceWidth * surfaceMaskAspect * foreshortenY)

        ZStack {
            WaterSurfaceTexture(
                size: CGSize(width: surfaceWidth, height: surfaceHeight),
                phase: ripplePhase,
                pulseStart: pulseStart,
                now: now,
                pulseDuration: pulseDuration,
                pulseSpeed: pulseSpeed
            )
            .mask(
                Image("glass_surface_mask")
                    .resizable()
                    .renderingMode(.original)
                    .frame(width: surfaceWidth, height: surfaceHeight)
            )
            .position(x: glassSize.width / 2, y: waterY)
        }
        .frame(width: glassSize.width, height: glassSize.height)
        .offset(y: verticalOffset)
    }
}

private struct WaterSurfaceTexture: View {
    let size: CGSize
    let phase: Double
    let pulseStart: Double?
    let now: Double
    let pulseDuration: Double
    let pulseSpeed: Double

    var body: some View {
        Canvas { context, _ in
            let rect = CGRect(origin: .zero, size: size)

            // Base
            context.fill(Path(ellipseIn: rect), with: .color(Color.white.opacity(0.18)))

            // Gloss
            let base = Gradient(stops: [
                .init(color: Color.white.opacity(0.55), location: 0.35),
                .init(color: Color.white.opacity(0.30), location: 0.65),
                .init(color: Color.white.opacity(0.18), location: 1.00),
            ])
            context.fill(
                Path(ellipseIn: rect),
                with: .linearGradient(
                    base,
                    startPoint: CGPoint(x: rect.minX, y: rect.midY),
                    endPoint:   CGPoint(x: rect.maxX, y: rect.midY)
                )
            )

            // Specular streak drifting
            let drift = CGFloat(phase * 0.90)
            let w = rect.width
            let x0 = rect.minX + drift.truncatingRemainder(dividingBy: w)
            let streakRect = CGRect(x: x0 - w * 0.08, y: rect.minY + rect.height * 0.18,
                                    width: w * 0.16, height: rect.height * 0.64)
            let streak = Gradient(stops: [
                .init(color: Color.white.opacity(0.0),  location: 0.0),
                .init(color: Color.white.opacity(0.45), location: 0.5),
                .init(color: Color.white.opacity(0.0),  location: 1.0),
            ])
            context.fill(
                Path(streakRect),
                with: .linearGradient(
                    streak,
                    startPoint: CGPoint(x: streakRect.minX, y: streakRect.minY),
                    endPoint:   CGPoint(x: streakRect.maxX, y: streakRect.minY)
                )
            )

            // Traveling micro ripples
            let lines = 5
            let amp = max(0.6, size.height * 0.05)
            let baseY = rect.midY
            let kd = 2 * Double.pi / Double(max(10.0, size.width * 0.7))
            let omega: Double = 1.8
            let driftD = Double(drift) * omega
            for i in 0..<lines {
                var p = Path()
                let yCenter = baseY + CGFloat(i - lines/2) * size.height * 0.07
                let localAmp = amp * (1 - CGFloat(i) / CGFloat(lines)) * 0.7
                let step: CGFloat = 5
                var x = rect.minX
                var first = true
                while x <= rect.maxX {
                    let y = yCenter + CGFloat(sin(kd * (Double(x) - driftD))) * localAmp
                    if first { p.move(to: CGPoint(x: x, y: y)); first = false }
                    else { p.addLine(to: CGPoint(x: x, y: y)) }
                    x += step
                }
                context.stroke(p, with: .color(Color.white.opacity(0.22)), lineWidth: 1)
            }

            // One-shot radial pulse from center -> rim
            if let s = pulseStart {
                let age = now - s
                if age >= 0, age <= pulseDuration {
                    let progress = age / pulseDuration
                    for j in 0..<3 {
                        let pr = progress - Double(j) * 0.15
                        if pr <= 0 || pr > 1 { continue }
                        let grow = pr * pulseSpeed
                        let wR = rect.width * min(1.0, grow)
                        let hR = rect.height * min(1.0, grow)
                        let ringRect = CGRect(x: rect.midX - wR/2, y: rect.midY - hR/2, width: wR, height: hR)
                        let alpha = CGFloat((1 - pr)) * 0.35
                        let lw = max(1, rect.height * 0.06 * (1 - CGFloat(pr) * 0.7))
                        context.stroke(Path(ellipseIn: ringRect), with: .color(Color.white.opacity(alpha)), lineWidth: lw)
                    }
                }
            }

            // Meniscus shading
            let inset = max(rect.width, rect.height) * 0.015
            let ringRect = rect.insetBy(dx: inset, dy: inset)
            let ring = Path(ellipseIn: ringRect)

            context.drawLayer { layer in
                let nearHalf = Path(CGRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height/2))
                layer.clip(to: nearHalf)
                layer.stroke(ring, with: .color(Color.white.opacity(0.32)), lineWidth: max(1, rect.height * 0.08))
            }
            context.drawLayer { layer in
                let farHalf = Path(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height/2))
                layer.clip(to: farHalf)
                layer.stroke(ring, with: .color(Color.black.opacity(0.10)), lineWidth: max(1, rect.height * 0.06))
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

private struct GlassLightShimmer: View {
    let glassSize: CGSize
    var body: some View {
        Canvas { ctx, size in
            let r = CGRect(origin: .zero, size: size)

            // Broad lateral gloss
            let gloss = Gradient(stops: [
                .init(color: .white.opacity(0.35), location: 0.18),
                .init(color: .white.opacity(0.10), location: 0.58),
                .init(color: .white.opacity(0.00), location: 0.95),
            ])
            ctx.fill(Path(r), with: .linearGradient(gloss,
                startPoint: CGPoint(x: r.minX, y: r.midY),
                endPoint:   CGPoint(x: r.maxX, y: r.midY)))

            // Two vertical specular streaks
            func streak(_ xFrac: CGFloat, widthFrac: CGFloat, alpha: Double, y0: CGFloat, y1: CGFloat) {
                let w = r.width * widthFrac
                let h = r.height * (y1 - y0)
                let x = r.minX + r.width * xFrac - w/2
                let y = r.minY + r.height * y0
                let rr = CGRect(x: x, y: y, width: w, height: h)
                let g = Gradient(stops: [
                    .init(color: .white.opacity(0.00), location: 0.00),
                    .init(color: .white.opacity(alpha), location: 0.50),
                    .init(color: .white.opacity(0.00), location: 1.00),
                ])
                ctx.fill(Path(roundedRect: rr, cornerRadius: w/2),
                         with: .linearGradient(g,
                            startPoint: CGPoint(x: rr.minX, y: rr.midY),
                            endPoint:   CGPoint(x: rr.maxX, y: rr.midY)))
            }

            streak(0.30, widthFrac: 0.055, alpha: 0.38, y0: 0.16, y1: 0.76)
            streak(0.66, widthFrac: 0.040, alpha: 0.22, y0: 0.22, y1: 0.72)

            // Soft rim highlight (top ellipse stroke, near side brighter)
            let rimInsetX = r.width * 0.06
            let rimInsetY = r.height * 0.06
            let rimRect = r.insetBy(dx: rimInsetX, dy: rimInsetY)
            let ellipse = Path(ellipseIn: rimRect)

            // Near half bright
            ctx.drawLayer { layer in
                layer.clip(to: Path(CGRect(x: r.minX, y: r.midY, width: r.width, height: r.height/2)))
                layer.stroke(ellipse, with: .color(.white.opacity(0.28)),
                             lineWidth: max(1, r.height * 0.035))
            }
            // Far half subtle
            ctx.drawLayer { layer in
                layer.clip(to: Path(CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height/2)))
                layer.stroke(ellipse, with: .color(.white.opacity(0.10)),
                             lineWidth: max(1, r.height * 0.025))
            }
        }
        .frame(width: glassSize.width, height: glassSize.height)
    }
}

private struct GlassInnerShadow: View {
    let glassSize: CGSize
    var body: some View {
        Canvas { ctx, size in
            let r = CGRect(origin: .zero, size: size)

            // Side vignette to add depth
            let edgeW = max(1, r.width * 0.10)
            let leftRect  = CGRect(x: r.minX, y: r.minY, width: edgeW, height: r.height)
            let rightRect = CGRect(x: r.maxX - edgeW, y: r.minY, width: edgeW, height: r.height)

            let leftGrad = Gradient(stops: [
                .init(color: .black.opacity(0.18), location: 0.00),
                .init(color: .black.opacity(0.00), location: 1.00),
            ])
            let rightGrad = Gradient(stops: [
                .init(color: .black.opacity(0.00), location: 0.00),
                .init(color: .black.opacity(0.18), location: 1.00),
            ])

            ctx.fill(Path(leftRect),
                     with: .linearGradient(leftGrad,
                        startPoint: CGPoint(x: leftRect.minX, y: leftRect.midY),
                        endPoint:   CGPoint(x: leftRect.maxX, y: leftRect.midY)))

            ctx.fill(Path(rightRect),
                     with: .linearGradient(rightGrad,
                        startPoint: CGPoint(x: rightRect.minX, y: rightRect.midY),
                        endPoint:   CGPoint(x: rightRect.maxX, y: rightRect.midY)))

            // Bottom fade for thickness
            let bottomH = r.height * 0.10
            let bottomRect = CGRect(x: r.minX, y: r.maxY - bottomH, width: r.width, height: bottomH)
            let bottomGrad = Gradient(stops: [
                .init(color: .black.opacity(0.16), location: 0.00),
                .init(color: .black.opacity(0.00), location: 1.00),
            ])
            ctx.fill(Path(bottomRect),
                     with: .linearGradient(bottomGrad,
                        startPoint: CGPoint(x: bottomRect.midX, y: bottomRect.maxY),
                        endPoint:   CGPoint(x: bottomRect.midX, y: bottomRect.minY)))
        }
        .frame(width: glassSize.width, height: glassSize.height)
        .opacity(0.6) // reduce if too strong
    }
}


// MARK: - Water fill (driven by waterTopY)
private struct WaterFillRenderer: View {
    let glassSize: CGSize
    let verticalOffset: CGFloat
    let waterTopY: CGFloat
    let baseColor: Color
    let highlightColor: Color

    var body: some View {
        Canvas { context, size in
            let width = size.width
            let height = size.height
            let top = max(0, min(waterTopY, height))
            let waterHeight = max(0.0, height - top)
            guard waterHeight > 0.5 else { return }
            let waterRect = CGRect(x: 0, y: top, width: width, height: waterHeight)
            drawBaseGradient(context: &context, rect: waterRect, width: width)
        }
        .frame(width: glassSize.width, height: glassSize.height)
        .offset(y: verticalOffset)
    }

    private func drawBaseGradient(context: inout GraphicsContext, rect: CGRect, width: CGFloat) {
        let gradient = Gradient(stops: [
            .init(color: baseColor.mix(with: .white, fraction: 0.35).opacity(0.88), location: 0),
            .init(color: baseColor.opacity(0.82), location: 0.5),
            .init(color: baseColor.mix(with: .white, fraction: 0.55).opacity(0.76), location: 1)
        ])
        context.fill(
            Path(rect),
            with: .linearGradient(
                gradient,
                startPoint: CGPoint(x: width * 0.3, y: rect.minY),
                endPoint:   CGPoint(x: width * 0.7, y: rect.maxY)
            )
        )
    }
}

private extension Color {
    func mix(with color: Color, fraction: Double) -> Color {
        let f = min(max(fraction, 0), 1)
        #if canImport(UIKit)
        let a = UIColor(self), b = UIColor(color)
        var r1: CGFloat = 0, g1: CGFloat = 0, b1c: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2c: CGFloat = 0, a2: CGFloat = 0
        a.getRed(&r1, green: &g1, blue: &b1c, alpha: &a1)
        b.getRed(&r2, green: &g2, blue: &b2c, alpha: &a2)
        return Color(
            red: Double(r1 + (r2 - r1) * f),
            green: Double(g1 + (g2 - g1) * f),
            blue: Double(b1c + (b2c - b1c) * f),
            opacity: Double(a1 + (a2 - a1) * f)
        )
        #else
        return self
        #endif
    }
}

// MARK: - Refracted text (underwater waves confined below surface)
private struct RefractedTextView: View {
    let imageName: String
    let glassSize: CGSize
    let textScale: CGFloat
    let textOffset: CGSize
    let verticalNudge: CGFloat
    let waterline: CGFloat
    let ripplePhase: Double
    let rippleAmplitude: CGFloat

    @Environment(\.displayScale) private var displayScale: CGFloat
    #if os(iOS)
    private let baseImage: CGImage?
    #endif

    init(
        imageName: String,
        glassSize: CGSize,
        textScale: CGFloat,
        textOffset: CGSize,
        verticalNudge: CGFloat,
        waterline: CGFloat,
        ripplePhase: Double,
        rippleAmplitude: CGFloat
    ) {
        self.imageName = imageName
        self.glassSize = glassSize
        self.textScale = textScale
        self.textOffset = textOffset
        self.verticalNudge = verticalNudge
        self.waterline = waterline
        self.ripplePhase = ripplePhase
        self.rippleAmplitude = rippleAmplitude
        #if os(iOS)
        self.baseImage = UIImage(named: imageName)?.cgImage
        #endif
    }

    var body: some View {
        Canvas { context, _ in
            #if os(iOS)
            guard let baseImage else { return }

            let imgW = CGFloat(baseImage.width)
            let imgH = CGFloat(baseImage.height)

            // aspect-fit rect of the text inside glass space
            let scale = min(glassSize.width / imgW, glassSize.height / imgH)
            let targetW = imgW * scale
            let targetH = imgH * scale
            let fittedRect = CGRect(
                x: (glassSize.width - targetW) / 2,
                y: (glassSize.height - targetH) / 2,
                width: targetW,
                height: targetH
            )

            // Map real waterline into this Canvas space (inverse of outer scale+offset)
            let centerY = glassSize.height / 2
            let canvasWaterY = centerY + (waterline - textOffset.height - centerY) / max(textScale, 0.0001)
            let clamped = max(fittedRect.minY, min(canvasWaterY, fittedRect.maxY))

            // Align seam to device pixels
            let px = 1.0 / max(displayScale, 1)
            let seamY = round(clamped / px) * px

            let sliceStep: CGFloat = 3
            let sy = imgH / fittedRect.height

            context.withCGContext { cg in
                // Clip to rectangle below the seam only
                cg.saveGState()
                cg.clip(to: CGRect(
                    x: fittedRect.minX,
                    y: seamY,
                    width: fittedRect.width,
                    height: max(fittedRect.maxY - seamY, 0)
                ))

                var y = max(seamY, fittedRect.minY)
                while y < fittedRect.maxY {
                    let bandHeight = min(sliceStep, fittedRect.maxY - y)
                    let absProg = (y - fittedRect.minY) / max(fittedRect.height, 1)
                    let phase = ripplePhase + Double(absProg) * 12.0
                    let offset = CGFloat(sin(phase) * Double(rippleAmplitude))

                    // Source slice
                    let srcY = (y - fittedRect.minY) * sy
                    let srcH = bandHeight * sy
                    let src = CGRect(x: 0, y: srcY, width: imgW, height: srcH).integral
                    guard let slice = baseImage.cropping(to: src) else { y += sliceStep; continue }

                    // Destination slice with horizontal ripple offset
                    let dst = CGRect(x: fittedRect.minX + offset, y: y, width: fittedRect.width, height: bandHeight)
                    cg.draw(slice, in: dst)
                    y += sliceStep
                }

                cg.restoreGState()
            }
            #else
            let resolved = context.resolve(Image(imageName))
            context.draw(resolved, in: CGRect(origin: .zero, size: glassSize))
            #endif
        }
        .frame(width: glassSize.width, height: glassSize.height)
        .scaleEffect(textScale)
        .offset(y: verticalNudge)
        .offset(x: textOffset.width, y: textOffset.height)
        .blur(radius: 0.4)
        .opacity(0.9)
        .accessibilityHidden(true)
    }
}

private final class NotificationScheduler {
    static let shared = NotificationScheduler()

    func requestAuthorization() async {
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
    }

    /// Clears pending notifications and schedules for today and tomorrow based on settings and last drink time.
    /// - Parameters:
    ///   - startHour: first hour (0-23) to allow notifications
    ///   - endHour: last hour (0-23) to allow notifications
    ///   - soundFile: bundle sound filename (e.g., "drink more water.caf")
    ///   - lastDrinkDate: if provided, first notification is 1 hour after this time (clamped to window)
    func scheduleForTodayAndTomorrow(startHour: Int, endHour: Int, soundFile: String, lastDrinkDate: Date?) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        // Reset badge count; we will increment on each scheduled request index
        DispatchQueue.main.async { UIApplication.shared.applicationIconBadgeNumber = 0 }

        let calendar = Calendar.current
        let now = Date()

        // Helper to build hourly times within window for a given day reference
        func hourlyTimes(for day: Date, startHour: Int, endHour: Int) -> [Date] {
            guard let start = calendar.date(bySettingHour: startHour, minute: 0, second: 0, of: day),
                  let end = calendar.date(bySettingHour: endHour, minute: 0, second: 0, of: day) else { return [] }
            var times: [Date] = []
            var t = start
            while t <= end {
                times.append(t)
                t = calendar.date(byAdding: .hour, value: 1, to: t) ?? t.addingTimeInterval(3600)
            }
            return times
        }

        func nextRoundedHour(after date: Date) -> Date {
            let comps = calendar.dateComponents([.year, .month, .day, .hour], from: date)
            let base = calendar.date(from: comps) ?? date
            return calendar.date(byAdding: .hour, value: 1, to: base) ?? date.addingTimeInterval(3600)
        }

        // Determine first fire for today based on lastDrinkDate
        var todayTimes = hourlyTimes(for: now, startHour: startHour, endHour: endHour)
        var firstFromDrink: Date? = nil
        if let ld = lastDrinkDate {
            let candidate = ld.addingTimeInterval(3600)
            // Clamp to window: if before startHour, move to start; if after endHour, none today
            if let startWindow = calendar.date(bySettingHour: startHour, minute: 0, second: 0, of: now),
               let endWindow = calendar.date(bySettingHour: endHour, minute: 0, second: 0, of: now) {
                if candidate < startWindow { firstFromDrink = startWindow }
                else if candidate <= endWindow { firstFromDrink = candidate }
            }
        }

        // Filter todayTimes based on now and firstFromDrink logic
        let filteredToday: [Date] = {
            if let first = firstFromDrink {
                // Start at 1h after drink, then hourly to end
                var arr: [Date] = []
                var t = nextRoundedHour(after: first.addingTimeInterval(-1)) // align to the next whole hour after first
                if t < first { t = first }
                // Include the exact first reminder at first (even if not on whole hour)
                arr.append(first)
                while true {
                    if let endWindow = calendar.date(bySettingHour: endHour, minute: 0, second: 0, of: now), t > endWindow { break }
                    if t > first { arr.append(t) }
                    t = calendar.date(byAdding: .hour, value: 1, to: t) ?? t.addingTimeInterval(3600)
                }
                return arr.filter { $0 > now }
            } else {
                // No drink yet: hourly from the next window time after now
                return todayTimes.filter { $0 > now }
            }
        }()

        // Build tomorrow schedule: hourly within window (restart at midnight)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(86400)
        let tomorrowTimes = hourlyTimes(for: tomorrow, startHour: startHour, endHour: endHour)

        // Resolve a base name (no extension) to an actual bundle resource filename
        func resolveSoundFilename(baseName: String) -> String? {
            if baseName.isEmpty { return nil }
            let fm = FileManager.default
            let exts = ["caf", "aiff", "wav"]

            func search(in path: String) -> String? {
                guard let items = try? fm.contentsOfDirectory(atPath: path) else { return nil }
                // Prefer extensions in the given order
                for ext in exts {
                    if let match = items.first(where: { ($0 as NSString).deletingPathExtension.caseInsensitiveCompare(baseName) == .orderedSame && ($0 as NSString).pathExtension.lowercased() == ext }) {
                        return match
                    }
                }
                // Fallback: any matching base name regardless of extension
                if let any = items.first(where: { ($0 as NSString).deletingPathExtension.caseInsensitiveCompare(baseName) == .orderedSame }) {
                    return any
                }
                return nil
            }

            if let base = Bundle.main.resourcePath {
                let soundsPath = (base as NSString).appendingPathComponent("Sounds")
                if let fromSounds = search(in: soundsPath) { return fromSounds }
                if let fromRoot = search(in: base) { return fromRoot }
            }
            return nil
        }

        let resolvedName = resolveSoundFilename(baseName: soundFile)
        let sound: UNNotificationSound? = {
            if let name = resolvedName { return UNNotificationSound(named: UNNotificationSoundName(name)) }
            return .default
        }()

        // Create content factory
        func content(badge: Int) -> UNMutableNotificationContent {
            let c = UNMutableNotificationContent()
            c.title = "Drink more water"
            c.body = "Tap the glass when you've had a drink."
            c.sound = sound // normal notifications obey Silent and Focus
            c.badge = NSNumber(value: badge)
            return c
        }

        var badgeCount = 0
        func schedule(date: Date, id: String) {
            badgeCount += 1
            let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let request = UNNotificationRequest(identifier: id, content: content(badge: badgeCount), trigger: trigger)
            center.add(request)
        }

        // Schedule today's
        for (idx, t) in filteredToday.enumerated() {
            schedule(date: t, id: "today_\(idx)")
        }
        // Schedule tomorrow's
        for (idx, t) in tomorrowTimes.enumerated() {
            schedule(date: t, id: "tomorrow_\(idx)")
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

                Section(header: Text("Ntification Sound")) {
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

#if os(iOS)
private final class MaskAnalyzer {
    static let shared = MaskAnalyzer()
    private(set) var bounds: MaskBounds?

    func prepare() -> Bool {
        guard bounds == nil else { return true }
        guard let image = UIImage(named: "glass_mask") else { return false }
        guard let newBounds = MaskAnalyzer.computeBounds(from: image) else { return false }
        bounds = newBounds
        return true
    }

    private static func computeBounds(from image: UIImage) -> MaskBounds? {
        guard let cgImage = image.cgImage else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.interpolationQuality = .none
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let data = context.data else { return nil }
        let buffer = data.bindMemory(to: UInt8.self, capacity: width * height * bytesPerPixel)

        let alphaThreshold: UInt8 = 10
        var topRow: Int?
        var bottomRow: Int?

        for row in 0..<height {
            let rowStart = row * bytesPerRow
            for col in 0..<width {
                let alpha = buffer[rowStart + col * bytesPerPixel + 3]
                if alpha > alphaThreshold {
                    if topRow == nil { topRow = row }
                    bottomRow = row
                    break
                }
            }
        }

        guard let tRow = topRow, let bRow = bottomRow else { return nil }
        let denominator = max(height - 1, 1)

        let topFraction = 1 - CGFloat(tRow) / CGFloat(denominator)
        let bottomFraction = 1 - CGFloat(bRow) / CGFloat(denominator)

        return MaskBounds(emptyFraction: bottomFraction, fullFraction: topFraction)
    }
}

private final class GlassWidthAnalyzer {
    static let shared = GlassWidthAnalyzer()
    private var cgImage: CGImage?
    private let alphaThreshold: UInt8 = 10

    init() { cgImage = UIImage(named: "glass_mask")?.cgImage }

    /// Returns opaque width / total width at a given vertical fraction (0 = top, 1 = bottom).
    func widthFraction(atYFraction yFrac: CGFloat) -> CGFloat? {
        guard let cgImage else { return nil }
        let W = cgImage.width
        let H = cgImage.height
        let row = max(0, min(H - 1, Int(round(yFrac * CGFloat(H - 1)))))

        guard let rowImg = cgImage.cropping(to: CGRect(x: 0, y: row, width: W, height: 1)) else { return nil }

        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * W
        guard let ctx = CGContext(
            data: nil,
            width: W,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.draw(rowImg, in: CGRect(x: 0, y: 0, width: W, height: 1))
        guard let data = ctx.data else { return nil }
        let buf = data.bindMemory(to: UInt8.self, capacity: bytesPerRow)

        var left: Int? = nil, right: Int? = nil
        for x in 0..<W where buf[x*bytesPerPixel+3] > alphaThreshold { left = x; break }
        for x in stride(from: W-1, through: 0, by: -1) where buf[x*bytesPerPixel+3] > alphaThreshold { right = x; break }
        guard let l = left, let r = right, r >= l else { return 0 }
        return CGFloat(r - l + 1) / CGFloat(W)
    }
}
#endif

private struct MaskBounds {
    let emptyFraction: CGFloat
    let fullFraction: CGFloat
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

