import SwiftUI

/// Maps photo coordinates to screen coordinates for a given screen size, the same way the
/// splash screen's aspect-filled image does.
struct GlassCanvasLayout: Equatable {
    let size: CGSize
    /// Photo pixels → screen points.
    let transform: PhotoTransform
    private let canvasOrigin: CGPoint

    init(size: CGSize) {
        self.size = size
        let fill = max(size.width / GlassArt.canvasSize.width, size.height / GlassArt.canvasSize.height)
        let scale = fill.isFinite && fill > 0 ? fill : 1
        canvasOrigin = CGPoint(
            x: (size.width - GlassArt.canvasSize.width * scale) / 2,
            y: (size.height - GlassArt.canvasSize.height * scale) / 2
        )
        transform = PhotoTransform(
            origin: CGPoint(x: canvasOrigin.x + GlassArt.photoOrigin.x * scale,
                            y: canvasOrigin.y + GlassArt.photoOrigin.y * scale),
            scale: scale
        )
    }

    /// Screen points per photo pixel.
    var scale: CGFloat { transform.scale }
    func point(_ p: CGPoint) -> CGPoint { transform.point(p) }
    func y(_ photoY: CGFloat) -> CGFloat { transform.y(photoY) }
    func rect(_ r: CGRect) -> CGRect { transform.rect(r) }

    /// The whole canvas on screen (larger than the screen; the overflow is off-screen).
    var canvasRect: CGRect {
        CGRect(origin: canvasOrigin, size: CGSize(width: GlassArt.canvasSize.width * scale,
                                                  height: GlassArt.canvasSize.height * scale))
    }

    var glassRect: CGRect { rect(GlassArt.glassRect) }
}

// MARK: - Glass view

/// The main screen's full-screen glass: the empty-glass photo as the background, with the water
/// from the splash photo revealed up to the current level, the photographed water surface moved to
/// that level, and the words drawn crisp above the water and rippling below it.
struct WaterGlassView: View {
    /// 0 = empty, 1 = full (daily goal met: water just under the rim).
    let targetFraction: CGFloat
    /// When set, the water is still (app inactive); otherwise it moves continuously.
    let frozenPhase: Double?
    /// Start time of the ring that spreads across the surface after a tap.
    let surfacePulseStart: Double?
    /// Shows "DAILY GOAL MET!" in place of "DRINK MORE WATER".
    let goalMet: Bool
    let layout: GlassCanvasLayout

    static let waveSpeed: Double = 2.3
    static let glareSpeed: Double = 0.01
    static let rippleSeed = Double.random(in: 0...(2 * .pi))

    private let pulseDuration: Double = 0.9

    /// Sideways sway of the underwater words and the distance between wave crests, in photo
    /// pixels (about 2 pt and 80 pt on an iPhone): a gentle sway, about two waves across the words.
    static let waveAmplitude: CGFloat = 4
    static let waveLength: CGFloat = 160

    @State private var animator = WaterGlassAnimator()

    var body: some View {
        // Low Power Mode halves the frame rate to save battery.
        let interval = ProcessInfo.processInfo.isLowPowerModeEnabled ? 1.0 / 15 : 1.0 / 30
        TimelineView(.animation(minimumInterval: interval, paused: frozenPhase != nil)) { context in
            let now = context.date.timeIntervalSinceReferenceDate
            let snapshot = animator.snapshot(now: now, frozenPhase: frozenPhase)
            scene(fraction: snapshot.fraction, phase: snapshot.ripplePhase, now: now)
        }
        .frame(width: layout.size.width, height: layout.size.height)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { animator.configure(initialFraction: targetFraction) }
        .onChange(of: targetFraction) { _, newValue in
            animator.updateTargetFraction(newValue, now: Date.timeIntervalSinceReferenceDate)
        }
    }

    private func scene(fraction: CGFloat, phase: Double, now: Double) -> some View {
        let hasWater = fraction > 0.001
        let levelY = GlassArt.levelY(forFraction: fraction)
        // With no water, everything counts as "above" it.
        let waterline = hasWater
            ? layout.transform.waterline(atLevelY: levelY)
            : .none(below: layout.size.height)

        return ZStack(alignment: .topLeading) {
            placed("glass_background", in: layout.canvasRect)

            if hasWater {
                placed("glass_water", in: layout.rect(GlassArt.waterRect))
                    .mask(WaterlineShape(waterline: waterline, region: .belowCentreLine))
            }

            // Words seen through air: crisp, exactly as on the splash screen.
            words
                .mask(WaterlineShape(waterline: waterline, region: .aboveFrontEdge))

            // Words seen through water: swaying, slightly softened and tinted.
            if hasWater {
                // The phase grows without bound (seconds since 2001), which a shader's 32-bit
                // float can't represent finely, so it's wrapped to one wave cycle first.
                let wrappedPhase = phase.truncatingRemainder(dividingBy: 2 * .pi)
                let amplitude = Self.waveAmplitude * layout.scale
                words
                    .distortionEffect(
                        ShaderLibrary.underwaterWave(
                            .float(Float(wrappedPhase)),
                            .float(Float(amplitude)),
                            .float(Float(Self.waveLength * layout.scale)),
                            .float(Float(waterline.levelY + waterline.frontDepth))
                        ),
                        maxSampleOffset: CGSize(width: amplitude * 1.4, height: 0)
                    )
                    .colorMultiply(GlassArt.underwaterTint)
                    .blur(radius: 0.6 * layout.scale)
                    .opacity(0.94)
                    .mask(WaterlineShape(waterline: waterline, region: .belowFrontEdge))
            }

            if hasWater {
                WaterHaze(transform: layout.transform, levelY: levelY, size: layout.size)
                placed("glass_surface", in: layout.transform.surfaceRect(atLevelY: levelY))
                pulseRings(waterline: waterline, now: now)
            }
        }
        .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
    }

    /// An image stretched to fill `rect` (screen coordinates) inside a full-size layer.
    private func placed(_ name: String, in rect: CGRect) -> some View {
        Image(name)
            .resizable()
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
    }

    /// "DRINK MORE WATER", or "DAILY GOAL MET!" in the same style.
    private var words: some View {
        ZStack {
            DrinkMoreWaterWords(transform: layout.transform, size: layout.size, photoImageName: "glass_words")
                .opacity(goalMet ? 0 : 1)
            GoalMetWords(transform: layout.transform, size: layout.size)
                .opacity(goalMet ? 1 : 0)
        }
        .animation(.easeInOut(duration: 0.35), value: goalMet)
    }

    /// Rings that spread across the surface after a tap.
    private func pulseRings(waterline: Waterline, now: Double) -> some View {
        Canvas { context, _ in
            guard let start = surfacePulseStart else { return }
            let age = now - start
            guard age >= 0, age <= pulseDuration else { return }
            let progress = age / pulseDuration
            for ring in 0..<3 {
                let p = progress - Double(ring) * 0.15
                guard p > 0, p <= 1 else { continue }
                let grow = CGFloat(min(1, p * 1.35))
                let rect = CGRect(
                    x: waterline.centerX - waterline.halfWidth * grow,
                    y: waterline.levelY - waterline.frontDepth * grow,
                    width: waterline.halfWidth * 2 * grow,
                    height: waterline.frontDepth * 2 * grow
                )
                context.stroke(
                    Path(ellipseIn: rect),
                    with: .color(.white.opacity(0.30 * (1 - p))),
                    lineWidth: max(1, 2.5 * layout.scale * (1 - CGFloat(p) * 0.6))
                )
            }
        }
        .frame(width: layout.size.width, height: layout.size.height)
    }
}

// MARK: - Level animation

/// Eases the displayed water level toward its target and keeps the ripple phases moving.
@MainActor
final class WaterGlassAnimator {
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
