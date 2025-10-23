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
    private let haptics = HapticsFactory.default()
    private let calculator = FillFractionCalculator()
    @StateObject private var viewModel = WaterIntakeViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showResetConfirmation: Bool = false

    private let glassSize = CGSize(width: 551, height: 722)
    private let glassVerticalNudge: CGFloat = -20
    private let textScale: CGFloat = 0.54
    private let textOffset: CGSize = CGSize(width: 0, height: 58)
    private let maskVerticalOffset: CGFloat = 5
    private let maskHorizontalOffset: CGFloat = 2

    private var fillFraction: CGFloat {
        let bounds = maskBounds
        let goal = CGFloat(viewModel.dailyGoalOz)
        let intake = CGFloat(viewModel.intakeOz)
        let perTap = CGFloat(viewModel.ozPerTap)
        let calcBounds = CalcMaskBounds(emptyFraction: bounds.emptyFraction, fullFraction: bounds.fullFraction)
        return calculator.fraction(intakeOz: intake, goalOz: goal, bounds: calcBounds, perTapOz: perTap)
    }

    private func todayString() -> String {
        DateUtils.todayString()
    }

    private func playSuccessHaptic() {
        haptics.success()
    }

    private func handleTap() {
        viewModel.resetIfNeeded()
        guard let step = viewModel.nextIntakeStep() else { return }

        // Light haptic on each increment
        haptics.impactLight()

        withAnimation(.easeInOut(duration: 0.25)) {
            viewModel.intakeOz = step.newValue
        }

        if step.reachedGoal {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                playSuccessHaptic()
            }
        }

        if viewModel.lastIntakeDateString.isEmpty { viewModel.lastIntakeDateString = todayString() }
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
                        Text("\(viewModel.intakeOz) / \(viewModel.dailyGoalOz) oz")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                        Text("Tap the glass to add \(viewModel.ozPerTap) oz")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.7))
                    }

                    VStack(spacing: 20) {
                        HStack {
                            Text("Daily goal")
                                .font(.headline)
                                .foregroundStyle(.white)
                            Spacer()
                            Text("\(viewModel.dailyGoalOz) oz")
                                .font(.headline)
                                .foregroundStyle(.white.opacity(0.75))
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
                viewModel.intakeOz = 0
                viewModel.lastIntakeDateString = todayString()
            }
        } message: {
            Text("This will set today's filled amount back to 0 oz.")
        }
        .contentShape(Rectangle())
        .onAppear { viewModel.resetIfNeeded() }
        .onAppear {
            #if os(iOS)
            _ = MaskAnalyzer.shared.prepare()
            #endif
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active { viewModel.resetIfNeeded() }
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
