//
//  ContentView.swift
//  DRINK MORE WATER
//
//  Created by AARON PERILLAT on 10/22/25.
//
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ContentView: View {
    @AppStorage("intakeOz") private var intakeOz: Int = 0
    @AppStorage("lastIntakeDate") private var lastIntakeDateString: String = ""
    @AppStorage("dailyGoalOz") private var dailyGoalOz: Int = 80
    @Environment(\.scenePhase) private var scenePhase
    @State private var showResetConfirmation: Bool = false

    private let glassSize = CGSize(width: 551, height: 722)
    private let glassVerticalNudge: CGFloat = -20
    private let textScale: CGFloat = 0.54
    private let textOffset: CGSize = CGSize(width: 0, height: 58)
    private let maskVerticalOffset: CGFloat = 5
    private let maskHorizontalOffset: CGFloat = 2

    private let ozPerTap: Int = 10

    private var fillFraction: CGFloat {
        let bounds = maskBounds
        guard dailyGoalOz > 0 else { return bounds.emptyFraction }

        let goal = CGFloat(dailyGoalOz)
        let intake = max(0, min(goal, CGFloat(intakeOz)))
        if intake <= 0 { return bounds.emptyFraction }

        let perTapValue = max(1, CGFloat(ozPerTap))
        let span = max(bounds.fullFraction - bounds.emptyFraction, 0.001)
        let totalSteps = max(1, Int(ceil(goal / perTapValue)))

        // Trim the bottom/top according to the mask so the first tap is visible
        // while keeping the final tap just below the rim.
        let bottomTrim = min(span * 0.3, span / CGFloat(totalSteps) * 2.6)
        let topTrim = min(span * 0.03, span / CGFloat(totalSteps) * 0.4)

        let minFraction = min(bounds.fullFraction - topTrim, bounds.emptyFraction + bottomTrim)
        let maxFraction = max(minFraction, bounds.fullFraction - topTrim)

        if intake <= 0 {
            return bounds.emptyFraction
        }

        if intake >= goal {
            return maxFraction
        }

        let normalized = max(0, min(1, (intake - perTapValue) / max(goal - perTapValue, 1)))
        let fraction = minFraction + normalized * (maxFraction - minFraction)

        return max(bounds.emptyFraction, min(fraction, maxFraction))
    }

    private func todayString() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale.current
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd" // day precision
        return formatter.string(from: Date())
    }

    private func resetIfNeeded() {
        let today = todayString()
        if lastIntakeDateString != today {
            intakeOz = 0
            lastIntakeDateString = today
        }
    }

    private func playHaptic(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
        #endif
    }

    private func playSuccessHaptic() {
        #if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
        #endif
    }

    private func handleTap() {
        resetIfNeeded()
        guard intakeOz < dailyGoalOz else { return }

        let newValue = min(intakeOz + ozPerTap, dailyGoalOz)

        // Light haptic on each increment
        playHaptic(style: .light)

        withAnimation(.easeInOut(duration: 0.25)) {
            intakeOz = newValue
        }
        // Success haptic when the goal is reached
        if intakeOz >= dailyGoalOz {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                playSuccessHaptic()
            }
        }

        if lastIntakeDateString.isEmpty { lastIntakeDateString = todayString() }
    }

    var body: some View {
        ZStack {
            Color(.systemBlue)
                .ignoresSafeArea()

            ZStack {
                Image("glass_text")
                    .resizable()
                    .scaledToFit()
                    .frame(width: glassSize.width, height: glassSize.height)
                    .scaleEffect(textScale)
                    .offset(y: glassVerticalNudge)
                    .offset(x: textOffset.width, y: textOffset.height)
                    .accessibilityHidden(true)

                glassMaskedWater()
                    .allowsHitTesting(false)

                Image("empty_glass")
                    .resizable()
                    .scaledToFit()
                    .frame(width: glassSize.width, height: glassSize.height)
                    .offset(y: glassVerticalNudge)
                    .accessibilityHidden(true)
            }
            .onTapGesture(perform: handleTap)

            VStack {
                Spacer()
                VStack(spacing: 20) {
                    VStack(spacing: 10) {
                        Text("\(intakeOz) / \(dailyGoalOz) oz")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                        Text("Tap the glass to add \(ozPerTap) oz")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.7))
                    }

                    VStack(spacing: 20) {
                        HStack {
                            Text("Daily goal")
                                .font(.headline)
                                .foregroundStyle(.white)
                            Spacer()
                            Text("\(dailyGoalOz) oz")
                                .font(.headline)
                                .foregroundStyle(.white.opacity(0.75))
                        }

                        Slider(
                            value: Binding(
                                get: { Double(dailyGoalOz) },
                                set: { dailyGoalOz = Int($0.rounded()) }
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
            Button {
                showResetConfirmation = true
            } label: {
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
                intakeOz = 0
                lastIntakeDateString = todayString()
            }
        } message: {
            Text("This will set today's filled amount back to 0 oz.")
        }
        .contentShape(Rectangle())
        .onAppear(perform: resetIfNeeded)
        .onAppear {
            #if os(iOS)
            _ = MaskAnalyzer.shared.prepare()
            #endif
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active { resetIfNeeded() }
        }
    }
}

// MARK: - Private helpers
private extension ContentView {
    var maskBounds: MaskBounds {
        #if os(iOS)
        if let bounds = MaskAnalyzer.shared.bounds {
            return bounds
        }
        if MaskAnalyzer.shared.prepare(), let bounds = MaskAnalyzer.shared.bounds {
            return bounds
        }
        #endif
        return MaskBounds(emptyFraction: 0.0, fullFraction: 1.0)
    }

    func glassMask() -> some View {
        Image("glass_mask")
            .resizable()
            .scaledToFit()
            .frame(width: glassSize.width, height: glassSize.height)
            .offset(x: maskHorizontalOffset, y: glassVerticalNudge + maskVerticalOffset)
    }

    func glassMaskedWater() -> some View {
        let fillHeight = max(0, glassSize.height * fillFraction)
        let surfaceWidth = glassSize.width * (0.34 + (0.64 - 0.34) * fillFraction)
        let surfaceHeight = max(12, 18 + (28 - 18) * fillFraction)
        let surfaceY = glassSize.height - fillHeight

        return ZStack {
            VStack(spacing: 0) {
                Spacer()
                LinearGradient(colors: [Color.white.opacity(0.80), Color.white.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                    .frame(width: glassSize.width, height: fillHeight)
                    .overlay(
                        LinearGradient(colors: [Color.white.opacity(0.06), .clear, Color.white.opacity(0.04)], startPoint: .leading, endPoint: .trailing)
                    )
                    .blur(radius: 0.2)
            }

            if fillHeight > 0 {
                WaterSurfaceGraphic(width: surfaceWidth, height: surfaceHeight)
                    .frame(width: surfaceWidth, height: surfaceHeight)
                    .position(x: glassSize.width / 2, y: surfaceY)
            }
        }
        .frame(width: glassSize.width, height: glassSize.height)
        .offset(y: glassVerticalNudge)
        .mask(glassMask())
    }
}

private struct WaterSurfaceGraphic: View {
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        let innerWidth = width * 0.92
        let innerHeight = height * 0.82
        let outerStrokeWidth = max(1, width * 0.003)
        let innerStrokeWidth = max(0.5, width * 0.0015)

        return ZStack {
            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.65), Color.white.opacity(0.85)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    Ellipse()
                        .stroke(Color.white.opacity(0.95), lineWidth: outerStrokeWidth)
                )
            Ellipse()
                .stroke(Color.white.opacity(0.5), lineWidth: innerStrokeWidth)
                .frame(width: innerWidth, height: innerHeight)
        }
        .blur(radius: 0.35)
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
