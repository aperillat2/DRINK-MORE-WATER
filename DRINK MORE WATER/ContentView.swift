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
    private let calibratedFullFraction: CGFloat = 1.0 - 0.198522622345337 // = 0.801477377654663
    private let calibratedEmptyFraction: CGFloat = 1.0 - 0.8799630655586334 // = 0.1200369344413666
    private let rippleSeed = Double.random(in: 0...(2 * .pi))

    private let glassSize = CGSize(width: 551, height: 722)
    private let glassVerticalNudge: CGFloat = -20
    private let textScale: CGFloat = 0.54
    private let textOffset: CGSize = CGSize(width: 0, height: 58)
    private let maskVerticalOffset: CGFloat = 5
    private let maskHorizontalOffset: CGFloat = 2
    private let uiTestButtonFlag = "-UITestsForceButton"

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
        } message: {
            Text("This will set today's filled amount back to 0 oz.")
        }
        .contentShape(Rectangle())
        .onAppear {
            viewModel.resetIfNeeded()
            // Initialize calibration lines based on prior inner adjustments
            let innerHeight = glassSize.height - 163
            let innerCenterY = glassVerticalNudge - 26
            calTopY = innerCenterY - innerHeight / 2
            calBottomY = innerCenterY + innerHeight / 2
        }
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
    var shouldUseButtonForTap: Bool {
        ProcessInfo.processInfo.arguments.contains(uiTestButtonFlag)
    }

    @ViewBuilder
    var interactiveGlass: some View {
        if shouldUseButtonForTap {
            Button(action: handleTap) {
                glassVisual
            }
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

    var glassVisual: some View {
        TimelineView(.animation) { timeline in
            let timestamp = timeline.date.timeIntervalSinceReferenceDate
            let fraction = max(0, min(fillFraction, 1))
            let ripplePhase = rippleSeed + timestamp * (1.2 + Double(fraction) * 0.8)

            // Waterline Y in ZStack coordinates (snap to pixel for crisp alignment)
            let waterTop = glassSize.height * (1 - fraction)
            let pixel = 1.0 / max(displayScale, 1)
            let waterlineY = glassVerticalNudge + ceil(waterTop / pixel) * pixel

            #if os(iOS)
            let yFrac = max(0, min(1, waterTop / glassSize.height))
            let widthFraction = GlassWidthAnalyzer.shared.widthFraction(atYFraction: yFrac) ?? 1.0
            #else
            let widthFraction: CGFloat = 1.0
            #endif

            ZStack {
                refractedGlassText(fraction: fraction, ripplePhase: ripplePhase)
                    .allowsHitTesting(false)

                WaterFillRenderer(
                    glassSize: glassSize,
                    verticalOffset: glassVerticalNudge,
                    fillFraction: fraction,
                    ripplePhase: ripplePhase,
                    baseColor: Color(.sRGB, red: 0.78, green: 0.88, blue: 0.98, opacity: 0.82),
                    highlightColor: Color.white.opacity(0.9)
                )
                .allowsHitTesting(false)
                .mask(glassMask())

                // CALIBRATION: Draggable lines to mark true top and bottom of glass
                if showCalibration {
                    Group {
                        // TOP line
                        Rectangle()
                            .fill(Color.red)
                            .frame(width: glassSize.width, height: 3)
                            .position(x: glassSize.width / 2, y: calTopY)
                            .accessibilityHidden(true)
                            .overlay(alignment: .trailing) {
                                Text("Top: y=\(Int(calTopY)) frac=\(String(format: "%.4f", yToMaskFraction(calTopY)))")
                                    .font(.caption2).bold().foregroundColor(.white)
                                    .padding(6).background(Color.red.opacity(0.7))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                    .offset(x: -8, y: -14)
                            }

                        // BOTTOM line
                        Rectangle()
                            .fill(Color.red)
                            .frame(width: glassSize.width, height: 3)
                            .position(x: glassSize.width / 2, y: calBottomY)
                            .accessibilityHidden(true)
                            .overlay(alignment: .trailing) {
                                Text("Bottom: y=\(Int(calBottomY)) frac=\(String(format: "%.4f", yToMaskFraction(calBottomY)))")
                                    .font(.caption2).bold().foregroundColor(.white)
                                    .padding(6).background(Color.red.opacity(0.7))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                    .offset(x: -8, y: -14)
                            }

                        // Small drag handles for visibility
                        Circle()
                            .fill(Color.red)
                            .frame(width: 10, height: 10)
                            .position(x: glassSize.width - 8, y: calTopY)
                            .accessibilityHidden(true)
                        Circle()
                            .fill(Color.red)
                            .frame(width: 10, height: 10)
                            .position(x: glassSize.width - 8, y: calBottomY)
                            .accessibilityHidden(true)

                        // Gesture catcher overlay to drag nearest line
                        Color.clear
                            .frame(width: glassSize.width, height: glassSize.height)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        let y = value.location.y
                                        // Move the nearest line to the drag location
                                        if abs(y - calTopY) <= abs(y - calBottomY) {
                                            calTopY = y
                                        } else {
                                            calBottomY = y
                                        }
                                    }
                            )

                        // Quick logger button
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
                    .zIndex(1000) // ensure on top of tap gestures
                }

                Image("empty_glass")
                    .resizable()
                    .scaledToFit()
                    .frame(width: glassSize.width, height: glassSize.height)
                    .offset(y: glassVerticalNudge)
                    .accessibilityHidden(true)
            }
        }
    }

    var maskBounds: MaskBounds {
        // Use calibrated fractions in MaskAnalyzer space (1 at top, 0 at bottom).
        MaskBounds(emptyFraction: calibratedEmptyFraction, fullFraction: calibratedFullFraction)
    }

    func glassMask() -> some View {
        Image("glass_mask")
            .resizable()
            .scaledToFit()
            .frame(width: glassSize.width, height: glassSize.height)
            .offset(x: maskHorizontalOffset, y: glassVerticalNudge + maskVerticalOffset)
    }

    func refractedGlassText(fraction: CGFloat, ripplePhase: Double) -> some View {
        let clampedFraction = max(0, min(fraction, 1))
        let globalWaterline = max(0, min(glassSize.height, glassSize.height * (1 - clampedFraction)))
        let localWaterline = max(0, min(glassSize.height, globalWaterline - textOffset.height))
        let amplitude = refractedAmplitude(for: clampedFraction)
        let refractionActivationFraction: CGFloat = 0.23
        let shouldRenderRefraction = clampedFraction >= refractionActivationFraction

        return ZStack {
            Image("glass_text")
                .resizable()
                .scaledToFit()
                .frame(width: glassSize.width, height: glassSize.height)
                .scaleEffect(textScale)
                .offset(y: glassVerticalNudge)
                .offset(x: textOffset.width, y: textOffset.height)
                .mask(
                    Rectangle()
                        .frame(width: glassSize.width, height: localWaterline)
                        .offset(y: glassVerticalNudge + textOffset.height - glassSize.height / 2 + localWaterline / 2)
                )
                .accessibilityHidden(true)

            if shouldRenderRefraction {
                RefractedTextView(
                    imageName: "glass_text",
                    glassSize: glassSize,
                    textScale: textScale,
                    textOffset: textOffset,
                    verticalNudge: glassVerticalNudge,
                    waterline: globalWaterline,
                    ripplePhase: ripplePhase,
                    rippleAmplitude: amplitude
                )
                .mask(glassMask())
                .accessibilityHidden(true)
            }
        }
    }

    private func refractedAmplitude(for fraction: CGFloat) -> CGFloat {
        7
    }
    
    func yToMaskFraction(_ y: CGFloat) -> CGFloat {
        // Convert a ZStack Y coordinate back into the glass image coordinate space,
        // compensating for the mask's vertical offset and the glass nudge.
        let yInGlassSpace = y - (glassVerticalNudge + maskVerticalOffset)
        let frac = yInGlassSpace / glassSize.height
        return max(0, min(1, frac))
    }
}

private struct WaterFillRenderer: View {
    let glassSize: CGSize
    let verticalOffset: CGFloat
    let fillFraction: CGFloat
    let ripplePhase: Double
    let baseColor: Color
    let highlightColor: Color

    var body: some View {
        Canvas { context, size in
            let fraction = max(0, min(fillFraction, 1))
            let width = size.width
            let height = size.height
            let waterHeight = height * fraction
            guard waterHeight > 1 else { return }

            let waterRect = CGRect(
                x: 0,
                y: height - waterHeight,
                width: width,
                height: waterHeight
            )

            drawBaseGradient(context: &context, rect: waterRect, width: width)
        }
        .frame(width: glassSize.width, height: glassSize.height)
        .offset(y: verticalOffset)
    }

    private func drawBaseGradient(context: inout GraphicsContext, rect: CGRect, width: CGFloat) {
        let gradient = Gradient(stops: [
            .init(color: baseColorMix(lighten: 0.35).opacity(0.88), location: 0),
            .init(color: baseColor.opacity(0.82), location: 0.5),
            .init(color: baseColorMix(lighten: 0.55).opacity(0.76), location: 1)
        ])

        context.fill(
            Path(rect),
            with: .linearGradient(
                gradient,
                startPoint: CGPoint(x: width * 0.3, y: rect.minY),
                endPoint: CGPoint(x: width * 0.7, y: rect.maxY)
            )
        )
    }

    private func baseColorMix(lighten amount: Double) -> Color {
        let clamped = min(max(amount, -1), 1)
        if clamped == 0 { return baseColor }
        let target: Color = clamped > 0 ? .white : .black
        return baseColor.mix(with: target, fraction: abs(clamped))
    }
}

private extension Color {
    func mix(with color: Color, fraction: Double) -> Color {
        let fraction = min(max(fraction, 0), 1)
        #if canImport(UIKit)
        let primary = UIColor(self)
        let secondary = UIColor(color)

        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        primary.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        secondary.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)

        let r = r1 + (r2 - r1) * fraction
        let g = g1 + (g2 - g1) * fraction
        let b = b1 + (b2 - b1) * fraction
        let a = a1 + (a2 - a1) * fraction
        return Color(red: Double(r), green: Double(g), blue: Double(b), opacity: Double(a))
        #else
        return self
        #endif
    }
}

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

            // Compute aspect-fit rect of the image inside glassSize
            let scale = min(glassSize.width / imgW, glassSize.height / imgH)

            let targetW = imgW * scale
            let targetH = imgH * scale
            let fittedRect = CGRect(
                x: (glassSize.width - targetW) / 2,
                y: (glassSize.height - targetH) / 2,
                width: targetW,
                height: targetH
            )

            let sliceStep: CGFloat = 3
            // Invert the outer transforms (scale around center + vertical/text offsets)
            let centerY = glassSize.height / 2
            let canvasWaterline = centerY + (waterline - textOffset.height - centerY) / max(textScale, 0.0001)
            let clampedWaterline = max(fittedRect.minY, min(canvasWaterline, fittedRect.maxY))

            guard clampedWaterline <= fittedRect.maxY else { return }

            // Align the seam to device pixels and bias slightly below the waterline to prevent above-seam bleed
            let pixel = 1.0 / max(displayScale, 1)
            let seamY = ceil(clampedWaterline / pixel) * pixel // align to pixel without bias

            context.withCGContext { cgContext in

                let startY = seamY
                let totalDepth = max(fittedRect.maxY - startY, 1)

                // Map from fittedRect space to source image space
                let sy = imgH / fittedRect.height

                var y = max(startY, seamY)
                while y < fittedRect.maxY {
                    let bandHeight = min(sliceStep, fittedRect.maxY - y)
                    let depthProgress = (y - startY) / totalDepth
                    let phase = ripplePhase + Double(depthProgress) * 12.0
                    let amplitude = rippleAmplitude
                    let offset = CGFloat(sin(phase) * Double(amplitude))

                    // Ensure the underwater text never fully disappears at the seam
                    let minAlpha: CGFloat = 0.5
                    let appliedAlpha = minAlpha + (1 - minAlpha)

                    // Source slice in image coordinates
                    let srcY = (y - fittedRect.minY) * sy
                    let srcH = bandHeight * sy
                    let sourceRect = CGRect(x: 0, y: srcY, width: imgW, height: srcH).integral
                    guard let slice = baseImage.cropping(to: sourceRect) else {
                        y += sliceStep
                        continue
                    }

                    // Destination slice in fittedRect coordinates with horizontal ripple offset
                    let destRect = CGRect(x: fittedRect.minX + offset, y: y, width: fittedRect.width, height: bandHeight)

                    cgContext.saveGState()
                    cgContext.clip(to: CGRect(
                        x: fittedRect.minX,
                        y: seamY,
                        width: fittedRect.width,
                        height: max(fittedRect.maxY - seamY, 0)
                    ))
                    // Apply soft fade for the top band
                    cgContext.setAlpha(appliedAlpha)
                    cgContext.draw(slice, in: destRect)
                    cgContext.restoreGState()

                    y += sliceStep
                }
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

    init() {
        if let ui = UIImage(named: "glass_mask")?.cgImage {
            self.cgImage = ui
        }
    }

    /// Returns the fraction (0..1) of the mask's opaque width at a given vertical fraction (0 is top, 1 is bottom).
    func widthFraction(atYFraction yFrac: CGFloat) -> CGFloat? {
        guard let cgImage else { return nil }
        let width = cgImage.width
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width

        guard let context = CGContext(
            data: nil,
            width: width,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Draw just the single row into the 1px-high context
        context.interpolationQuality = .none
        context.translateBy(x: 0, y: 1)
        context.scaleBy(x: 1, y: -1)
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: 1), byTiling: false)

        guard let data = context.data else { return nil }
        let buffer = data.bindMemory(to: UInt8.self, capacity: width * bytesPerPixel)

        var left: Int? = nil
        var right: Int? = nil
        for col in 0..<width {
            let alpha = buffer[col * bytesPerPixel + 3]
            if alpha > alphaThreshold {
                left = col
                break
            }
        }
        for col in stride(from: width - 1, through: 0, by: -1) {
            let alpha = buffer[col * bytesPerPixel + 3]
            if alpha > alphaThreshold {
                right = col
                break
            }
        }
        guard let l = left, let r = right, r >= l else { return 0 }
        let opaqueWidth = r - l + 1
        return CGFloat(opaqueWidth) / CGFloat(width)
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
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

