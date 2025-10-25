import SwiftUI
import CoreGraphics
import UIKit
import Combine

enum WaterGlassMetrics {
    static let glassSize = CGSize(width: 551, height: 722)
    static let glassVerticalNudge: CGFloat = -20
    static let textScale: CGFloat = 0.54
    static let textOffset = CGSize(width: 0, height: 58)
    static let maskVerticalOffset: CGFloat = 5
    static let maskHorizontalOffset: CGFloat = 2
}

struct WaterGlassView: View {
    let targetFraction: CGFloat
    let frozenPhase: Double?
    let surfacePulseStart: Double?

    private let surfacePulseDuration: Double = 0.9
    private let surfacePulseSpeed: Double = 1.35

    @Environment(\.displayScale) private var displayScale: CGFloat

    @StateObject private var animator = WaterGlassAnimator()

    static let waveSpeed: Double = 2.3
    static let glareSpeed: Double = 0.01
    static let rippleSeed = Double.random(in: 0...(2 * .pi))

    var body: some View {
        glassVisual
            .onAppear(perform: configureOnAppear)
            .onChange(of: targetFraction) { _, newValue in
                updateAnimationState(with: newValue)
            }
    }
}

private extension WaterGlassView {
    func configureOnAppear() {
        let clamped = clamp01(targetFraction)
        animator.configure(initialFraction: clamped)

    }

    func updateAnimationState(with newValue: CGFloat) {
        animator.updateTargetFraction(clamp01(newValue), now: Date.timeIntervalSinceReferenceDate)
    }

    var glassVisual: some View {
        let fps: Double = 30.0
        return TimelineView(.periodic(from: .now, by: 1.0 / fps)) { context in
            let now = context.date.timeIntervalSinceReferenceDate
            buildGlassContent(now: now)
        }
    }

    func buildGlassContent(now: Double) -> AnyView {
        let snapshot = animator.snapshot(now: now, frozenPhase: frozenPhase)
        let fraction = snapshot.fraction
        let ripplePhase = snapshot.ripplePhase
        let glarePhase = snapshot.glarePhase

        let glassSize = WaterGlassMetrics.glassSize
        let waterTop = glassSize.height * (1 - fraction)
        let px = 1.0 / max(displayScale, 1)
        let waterTopAligned = round(waterTop / px) * px

        let yFrac = max(0, min(1, waterTopAligned / glassSize.height))
        let widthFraction = GlassWidthAnalyzer.shared.widthFraction(atYFraction: yFrac) ?? 1.0

        let fillMask = makeFillMask(
            waterTopAligned: waterTopAligned,
            widthFraction: widthFraction,
            surfaceMaskAspect: surfaceMaskAspect
        )

        return makeGlassStack(
            fraction: fraction,
            ripplePhase: ripplePhase,
            glarePhase: glarePhase,
            widthFraction: widthFraction,
            surfaceMaskAspect: surfaceMaskAspect,
            waterTopAligned: waterTopAligned,
            now: now,
            fillMask: fillMask
        )
    }

    func makeGlassStack(
        fraction: CGFloat,
        ripplePhase: Double,
        glarePhase: Double,
        widthFraction: CGFloat,
        surfaceMaskAspect: CGFloat,
        waterTopAligned: CGFloat,
        now: Double,
        fillMask: AnyView
    ) -> AnyView {
        let glassSize = WaterGlassMetrics.glassSize
        return AnyView(
            ZStack {
                refractedGlassText(
                    fraction: fraction,
                    ripplePhase: ripplePhase,
                    widthFraction: widthFraction,
                    surfaceMaskAspect: surfaceMaskAspect
                )
                .transaction { $0.animation = nil }
                .animation(nil, value: fraction)

                WaterFillRenderer(
                    glassSize: glassSize,
                    verticalOffset: WaterGlassMetrics.glassVerticalNudge,
                    waterTopY: waterTopAligned,
                    baseColor: Color(.sRGB, red: 0.78, green: 0.88, blue: 0.98, opacity: 0.42),
                    highlightColor: Color.white.opacity(0.9)
                )
                .mask(fillMask)
                .allowsHitTesting(false)

                WaterSurfaceOverlay(
                    glassSize: glassSize,
                    verticalOffset: WaterGlassMetrics.glassVerticalNudge,
                    waterY: waterTopAligned,
                    widthFraction: widthFraction,
                    surfaceMaskAspect: surfaceMaskAspect,
                    ripplePhase: ripplePhase,
                    glarePhase: glarePhase,
                    pulseStart: surfacePulseStart,
                    now: now,
                    pulseDuration: surfacePulseDuration,
                    pulseSpeed: surfacePulseSpeed
                )
                .mask(glassMaskAlignedToFill())
                .transaction { $0.animation = nil }
                .animation(nil, value: waterTopAligned)
                .allowsHitTesting(false)

                let px = 1.0 / max(displayScale, 1)
                let contentY = round(WaterGlassMetrics.glassVerticalNudge / px) * px
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
                    .offset(y: WaterGlassMetrics.glassVerticalNudge)
                    .accessibilityHidden(true)
            }
        )
    }

    func makeFillMask(
        waterTopAligned: CGFloat,
        widthFraction: CGFloat,
        surfaceMaskAspect: CGFloat
    ) -> AnyView {
        AnyView(
            ZStack {
                glassMaskAlignedToFill()
                WaterSurfaceCutout(
                    glassSize: WaterGlassMetrics.glassSize,
                    verticalOffset: WaterGlassMetrics.glassVerticalNudge,
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

    var surfaceMaskAspect: CGFloat {
        if let cg = UIImage(named: "glass_surface_mask")?.cgImage {
            return CGFloat(cg.height) / CGFloat(cg.width)
        }
        return 88.0 / 480.0
    }

    func glassMaskForOverlays(biasY: CGFloat = 0) -> some View {
        let px = 1.0 / max(displayScale, 1)
        let y = round((WaterGlassMetrics.glassVerticalNudge + WaterGlassMetrics.maskVerticalOffset + biasY) / px) * px
        return Image("glass_mask")
            .resizable()
            .scaledToFit()
            .frame(width: WaterGlassMetrics.glassSize.width, height: WaterGlassMetrics.glassSize.height)
            .offset(x: WaterGlassMetrics.maskHorizontalOffset, y: y)
    }

    func glassMaskAlignedToFill() -> some View {
        Image("glass_mask")
            .resizable()
            .scaledToFit()
            .frame(width: WaterGlassMetrics.glassSize.width, height: WaterGlassMetrics.glassSize.height)
            .offset(x: WaterGlassMetrics.maskHorizontalOffset, y: WaterGlassMetrics.glassVerticalNudge)
    }

    func refractionSeamOffset(waterY: CGFloat, widthFraction: CGFloat) -> CGFloat {
        let px = 1.0 / max(displayScale, 1)
        let surfaceWidth = max(1, WaterGlassMetrics.glassSize.width * widthFraction)
        let depth = min(max(waterY / WaterGlassMetrics.glassSize.height, 0), 1)
        let foreshortenY: CGFloat = 1.0 - 0.08 * depth
        let surfaceHeight = max(1, surfaceWidth * surfaceMaskAspect * foreshortenY)
        let rel = surfaceHeight * 0.48
        let off = max(px, min(rel, 24))
        return round(off / px) * px
    }

    func refractedGlassText(
        fraction: CGFloat,
        ripplePhase: Double,
        widthFraction: CGFloat,
        surfaceMaskAspect: CGFloat
    ) -> AnyView {
        let glassSize = WaterGlassMetrics.glassSize
        let clamped = max(0, min(fraction, 1))
        let realWaterY = max(0, min(glassSize.height, glassSize.height * (1 - clamped)))

        let seam = refractionSeamOffset(waterY: realWaterY, widthFraction: widthFraction)
        let underwaterStartY = realWaterY + seam

        let px = 1.0 / max(displayScale, 1)
        let localAbove = max(0, min(glassSize.height, realWaterY - WaterGlassMetrics.textOffset.height))
        let aboveAligned = round(localAbove / px) * px

        let underwaterTextTint: Color = Color(hue: 0.58, saturation: 0.5, brightness: 1.0)

        return AnyView(
            ZStack {
                Image("glass_text")
                    .resizable()
                    .scaledToFit()
                    .frame(width: glassSize.width, height: glassSize.height)
                    .scaleEffect(WaterGlassMetrics.textScale)
                    .offset(y: WaterGlassMetrics.glassVerticalNudge)
                    .offset(x: WaterGlassMetrics.textOffset.width, y: WaterGlassMetrics.textOffset.height)
                    .mask(
                        Rectangle()
                            .frame(width: glassSize.width, height: aboveAligned)
                            .offset(y: WaterGlassMetrics.glassVerticalNudge + WaterGlassMetrics.textOffset.height - glassSize.height/2 + aboveAligned/2)
                    )
                    .transaction { $0.animation = nil }
                    .animation(nil, value: aboveAligned)
                    .animation(nil, value: fraction)
                    .accessibilityHidden(true)

                RefractedTextView(
                    imageName: "glass_text",
                    glassSize: glassSize,
                    textScale: WaterGlassMetrics.textScale,
                    textOffset: WaterGlassMetrics.textOffset,
                    verticalNudge: WaterGlassMetrics.glassVerticalNudge,
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

    func glassMask() -> some View {
        Image("glass_mask")
            .resizable()
            .scaledToFit()
            .frame(width: WaterGlassMetrics.glassSize.width, height: WaterGlassMetrics.glassSize.height)
            .offset(x: WaterGlassMetrics.maskHorizontalOffset, y: WaterGlassMetrics.glassVerticalNudge + WaterGlassMetrics.maskVerticalOffset)
    }

    func clamp01(_ x: CGFloat) -> CGFloat { max(0, min(1, x)) }
}

@MainActor
final class WaterGlassAnimator: ObservableObject {
    private let levelAnimDuration: Double = 1.5

    private var displayedFraction: CGFloat = 0
    private var levelAnimFrom: CGFloat = 0
    private var levelAnimTo: CGFloat = 0
    private var levelAnimStart: Double? = nil
    private var glarePhaseAccumulator: Double = 0
    private var lastTimelineTime: Double? = nil

    func configure(initialFraction: CGFloat) {
        let clamped = clamp(initialFraction)
        displayedFraction = clamped
        levelAnimFrom = clamped
        levelAnimTo = clamped
        levelAnimStart = nil
        glarePhaseAccumulator = 0
        lastTimelineTime = nil
    }

    func updateTargetFraction(_ target: CGFloat, now: Double) {
        let clampedTarget = clamp(target)
        let current: CGFloat
        if let start = levelAnimStart {
            let raw = max(0, min(1, (now - start) / levelAnimDuration))
            let eased = easeOutCubic(raw)
            current = clamp(levelAnimFrom + CGFloat(eased) * (levelAnimTo - levelAnimFrom))
        } else {
            current = displayedFraction
        }
        levelAnimFrom = current
        levelAnimTo = clampedTarget
        levelAnimStart = now
    }

    func snapshot(now: Double, frozenPhase: Double?) -> Snapshot {
        let fraction: CGFloat
        if let start = levelAnimStart {
            let raw = max(0, min(1, (now - start) / levelAnimDuration))
            let eased = easeOutCubic(raw)
            fraction = clamp(levelAnimFrom + CGFloat(eased) * (levelAnimTo - levelAnimFrom))
            if raw >= 1 {
                levelAnimStart = nil
                displayedFraction = clamp(levelAnimTo)
            }
        } else {
            fraction = clamp(displayedFraction)
        }

        let ripplePhase = frozenPhase ?? (WaterGlassView.rippleSeed + now * WaterGlassView.waveSpeed)
        let glarePhase: Double = {
            if frozenPhase != nil {
                lastTimelineTime = nil
                return glarePhaseAccumulator
            } else {
                let last = lastTimelineTime ?? now
                let delta = max(0, now - last)
                let updated = glarePhaseAccumulator + delta * WaterGlassView.glareSpeed
                glarePhaseAccumulator = updated
                lastTimelineTime = now
                return updated
            }
        }()

        return Snapshot(fraction: fraction, ripplePhase: ripplePhase, glarePhase: glarePhase)
    }

    private func clamp(_ value: CGFloat) -> CGFloat { max(0, min(1, value)) }

    private func easeOutCubic(_ t: Double) -> Double {
        let u = max(0.0, min(1.0, t))
        let inv = 1.0 - u
        return 1.0 - inv * inv * inv
    }

    struct Snapshot {
        let fraction: CGFloat
        let ripplePhase: Double
        let glarePhase: Double
    }
}

// MARK: - Helper Views / Components

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

private struct WaterSurfaceOverlay: View {
    let glassSize: CGSize
    let verticalOffset: CGFloat
    let waterY: CGFloat
    let widthFraction: CGFloat
    let surfaceMaskAspect: CGFloat
    let ripplePhase: Double
    let glarePhase: Double
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
                glarePhase: glarePhase,
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
        .allowsHitTesting(false)
    }
}

private struct WaterSurfaceTexture: View {
    let size: CGSize
    let phase: Double
    let glarePhase: Double
    let pulseStart: Double?
    let now: Double
    let pulseDuration: Double
    let pulseSpeed: Double

    var body: some View {
        Canvas { context, _ in
            let rect = CGRect(origin: .zero, size: size)

            context.fill(Path(ellipseIn: rect), with: .color(Color.white.opacity(0.18)))

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

            let rippleDrift = CGFloat(phase * 0.90)
            let oscillation = (sin(glarePhase) * 0.5 + 0.5)
            let w = rect.width
            let x0 = rect.minX + oscillation * w
            let streakRect = CGRect(
                x: x0 - w * 0.08,
                y: rect.minY + rect.height * 0.18,
                width: w * 0.16,
                height: rect.height * 0.64
            )
            let streak = Gradient(stops: [
                .init(color: Color.white.opacity(0.0),  location: 0.0),
                .init(color: Color.white.opacity(0.25), location: 0.5),
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

            let lines = 5
            let amp = max(0.6, size.height * 0.05)
            let baseY = rect.midY
            let kd = 2 * Double.pi / Double(max(10.0, size.width * 0.7))
            let omega: Double = 1.8
            let driftD = Double(rippleDrift) * omega
            for i in 0..<lines {
                var p = Path()
                let yCenter = baseY + CGFloat(i - lines/2) * size.height * 0.07
                let localAmp = amp * (1 - CGFloat(i) / CGFloat(lines)) * 0.7
                let step: CGFloat = 5
                var x = rect.minX
                var first = true
                while x <= rect.maxX {
                    let y = yCenter + CGFloat(sin(kd * (Double(x) - driftD))) * localAmp
                    if first {
                        p.move(to: CGPoint(x: x, y: y))
                        first = false
                    } else {
                        p.addLine(to: CGPoint(x: x, y: y))
                    }
                    x += step
                }
                context.stroke(p, with: .color(Color.white.opacity(0.22)), lineWidth: 1)
            }

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

            let gloss = Gradient(stops: [
                .init(color: .white.opacity(0.35), location: 0.18),
                .init(color: .white.opacity(0.10), location: 0.58),
                .init(color: .white.opacity(0.00), location: 0.95),
            ])
            ctx.fill(Path(r), with: .linearGradient(gloss,
                startPoint: CGPoint(x: r.minX, y: r.midY),
                endPoint:   CGPoint(x: r.maxX, y: r.midY)))

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

            let rimInsetX = r.width * 0.06
            let rimInsetY = r.height * 0.06
            let rimRect = r.insetBy(dx: rimInsetX, dy: rimInsetY)
            let ellipse = Path(ellipseIn: rimRect)

            ctx.drawLayer { layer in
                layer.clip(to: Path(CGRect(x: r.minX, y: r.midY, width: r.width, height: r.height/2)))
                layer.stroke(ellipse, with: .color(.white.opacity(0.28)),
                             lineWidth: max(1, r.height * 0.035))
            }
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
        .opacity(0.6)
    }
}

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
    private let baseImage: CGImage?

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
        self.baseImage = UIImage(named: imageName)?.cgImage
    }

    var body: some View {
        Canvas { context, _ in
            guard let baseImage else { return }

            let imgW = CGFloat(baseImage.width)
            let imgH = CGFloat(baseImage.height)

            let scale = min(glassSize.width / imgW, glassSize.height / imgH)
            let targetW = imgW * scale
            let targetH = imgH * scale
            let fittedRect = CGRect(
                x: (glassSize.width - targetW) / 2,
                y: (glassSize.height - targetH) / 2,
                width: targetW,
                height: targetH
            )

            let centerY = glassSize.height / 2
            let canvasWaterY = centerY + (waterline - textOffset.height - centerY) / max(textScale, 0.0001)
            let clamped = max(fittedRect.minY, min(canvasWaterY, fittedRect.maxY))

            let px = 1.0 / max(displayScale, 1)
            let seamYRaw = clamped
            let seamY = round(seamYRaw / px) * px

            let sliceStep: CGFloat = 1
            let sy = imgH / fittedRect.height

            context.withCGContext { cg in
                cg.saveGState()
                cg.clip(to: CGRect(
                    x: fittedRect.minX,
                    y: seamY,
                    width: fittedRect.width,
                    height: max(fittedRect.maxY - seamY, 0)
                ))

                let seamRel = max(0, min(1, (seamYRaw - fittedRect.minY) / max(fittedRect.height, 1)))
                let seamPhase = ripplePhase + Double(seamRel) * 12.0
                let seamBaseline = CGFloat(sin(seamPhase) * Double(rippleAmplitude))

                var y = max(seamY, fittedRect.minY)
                while y < fittedRect.maxY {
                    let bandHeight = min(sliceStep, fittedRect.maxY - y)
                    let absProg = max(0, min(1, (y - fittedRect.minY) / max(fittedRect.height, 1)))
                    let phase = ripplePhase + Double(absProg) * 12.0
                    let offset = CGFloat(sin(phase) * Double(rippleAmplitude)) - seamBaseline
                    let srcY = (y - fittedRect.minY) * sy
                    let srcH = bandHeight * sy
                    let src = CGRect(x: 0, y: srcY, width: imgW, height: srcH).integral
                    guard let slice = baseImage.cropping(to: src) else { y += sliceStep; continue }

                    let dst = CGRect(x: fittedRect.minX + offset, y: y, width: fittedRect.width, height: bandHeight)
                    cg.draw(slice, in: dst)
                    y += sliceStep
                }

                cg.restoreGState()
            }
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

private final class GlassWidthAnalyzer {
    static let shared = GlassWidthAnalyzer()
    private var cgImage: CGImage?
    private let alphaThreshold: UInt8 = 10

    init() { cgImage = UIImage(named: "glass_mask")?.cgImage }

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
