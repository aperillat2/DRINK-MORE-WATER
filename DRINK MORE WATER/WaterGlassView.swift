import SwiftUI

// MARK: - Artwork geometry

/// Measurements of the glass photos, in pixels of the original 896×1200 photo.
///
/// All of the main screen's glass artwork comes from two pixel-aligned photos — the splash photo
/// (water + "DRINK MORE WATER") and the same glass empty — so every layer shares one coordinate
/// space. The photo sits unscaled in the middle of a 2400×1800 canvas whose margins continue its
/// blue background (`glass_background` and `splash_photo` are both that canvas). Showing the canvas
/// aspect-filled puts the glass in exactly the same place as on the splash screen, on every device.
enum GlassArt {
    static let canvasSize = CGSize(width: 2400, height: 1800)
    /// Where the photo's top-left corner sits in the canvas.
    static let photoOrigin = CGPoint(x: 752, y: 300)

    /// Horizontal centre of the glass.
    static let centerX: CGFloat = 448
    /// Centre line of the water surface when the daily goal is met: just under the rim lip
    /// (which starts at y ≈ 160), like a full glass.
    static let fullLevelY: CGFloat = 200
    /// Centre line of the water surface for a nearly empty glass (just above the thick base).
    static let emptyLevelY: CGFloat = 905

    /// Where the surface sits in the splash photo, and its width there (it meets the glass walls
    /// at x ≈ 195 and 700). The surface artwork is cut from this level.
    static let photoLevelY: CGFloat = 377
    static let photoSurfaceWidth: CGFloat = 505
    /// Width of the water surface at other levels, measured from the glass's outline (which
    /// flares slightly toward the rim and tapers toward the base): (level y, width).
    static let surfaceWidths: [(y: CGFloat, width: CGFloat)] = [
        (200, 517), (290, 506), (377, 505), (450, 495), (550, 472),
        (650, 456), (750, 440), (850, 427), (925, 422),
    ]
    /// Distance from the surface's centre line to its front edge (the curve nearest the viewer).
    static let surfaceFrontDepth: CGFloat = 21
    /// Bottom of the water: the top of the glass's thick base.
    static let waterBottomY: CGFloat = 930

    /// The water, with the words and the surface removed (`glass_water`).
    static let waterRect = CGRect(x: 180, y: 150, width: 537, height: 811)
    /// The water surface cut from the splash photo (`glass_surface`), and the row of its centre line.
    static let surfaceRect = CGRect(x: 183, y: 330, width: 532, height: 88)
    static let surfaceCenterRow: CGFloat = 47
    /// The words lifted from the splash photo (`glass_words`, white on transparent).
    static let wordsRect = CGRect(x: 270, y: 470, width: 360, height: 350)
    /// Centre rows of the three lines of words, and their cap height (used for "DAILY GOAL MET!").
    static let wordLineCenters: [CGFloat] = [530, 643.5, 752]
    static let wordCapHeight: CGFloat = 87
    static let wordsCenterX: CGFloat = 445

    /// The whole glass, rim to base: the area that responds to taps.
    static let glassRect = CGRect(x: 170, y: 110, width: 560, height: 960)

    /// Surface centre line for a fill level (0 = empty, 1 = full).
    static func levelY(forFraction fraction: CGFloat) -> CGFloat {
        emptyLevelY + (fullLevelY - emptyLevelY) * max(0, min(1, fraction))
    }

    /// Width of the water surface at a level, interpolated from `surfaceWidths`.
    static func surfaceWidth(atLevelY y: CGFloat) -> CGFloat {
        guard let first = surfaceWidths.first, let last = surfaceWidths.last else { return photoSurfaceWidth }
        if y <= first.y { return first.width }
        if y >= last.y { return last.width }
        for (a, b) in zip(surfaceWidths, surfaceWidths.dropFirst()) where y <= b.y {
            return a.width + (b.width - a.width) * (y - a.y) / (b.y - a.y)
        }
        return last.width
    }

    /// How much the surface artwork is scaled at a level, so its ends meet the glass walls.
    static func surfaceScale(atLevelY y: CGFloat) -> CGFloat {
        surfaceWidth(atLevelY: y) / photoSurfaceWidth
    }
}

/// Maps photo coordinates to screen coordinates for a given screen size, the same way the
/// splash screen's aspect-filled image does.
struct GlassCanvasLayout: Equatable {
    let size: CGSize
    /// Screen points per photo pixel.
    let scale: CGFloat
    private let canvasOrigin: CGPoint

    init(size: CGSize) {
        self.size = size
        let s = max(size.width / GlassArt.canvasSize.width, size.height / GlassArt.canvasSize.height)
        scale = s.isFinite && s > 0 ? s : 1
        canvasOrigin = CGPoint(
            x: (size.width - GlassArt.canvasSize.width * scale) / 2,
            y: (size.height - GlassArt.canvasSize.height * scale) / 2
        )
    }

    func point(_ p: CGPoint) -> CGPoint {
        CGPoint(x: canvasOrigin.x + (GlassArt.photoOrigin.x + p.x) * scale,
                y: canvasOrigin.y + (GlassArt.photoOrigin.y + p.y) * scale)
    }

    func y(_ photoY: CGFloat) -> CGFloat { point(CGPoint(x: 0, y: photoY)).y }

    func rect(_ r: CGRect) -> CGRect {
        let o = point(r.origin)
        return CGRect(x: o.x, y: o.y, width: r.width * scale, height: r.height * scale)
    }

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
        let surfaceScale = GlassArt.surfaceScale(atLevelY: levelY)
        // Screen y of the surface centre line; with no water everything counts as "above".
        let screenLevel = hasWater ? layout.y(levelY) : layout.size.height + 1
        let waterline = Waterline(
            levelY: screenLevel,
            centerX: layout.point(CGPoint(x: GlassArt.centerX, y: 0)).x,
            halfWidth: GlassArt.surfaceWidth(atLevelY: levelY) / 2 * layout.scale,
            frontDepth: GlassArt.surfaceFrontDepth * surfaceScale * layout.scale
        )

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
                    .colorMultiply(Color(red: 0.86, green: 0.95, blue: 1.0))
                    .blur(radius: 0.6 * layout.scale)
                    .opacity(0.94)
                    .mask(WaterlineShape(waterline: waterline, region: .belowFrontEdge))
            }

            if hasWater {
                haze(levelY: levelY)
                surface(levelY: levelY, scale: surfaceScale)
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

    /// "DRINK MORE WATER" from the splash photo, or "DAILY GOAL MET!" in the same style.
    private var words: some View {
        ZStack {
            placed("glass_words", in: layout.rect(GlassArt.wordsRect))
                .opacity(goalMet ? 0 : 1)
            GoalMetWords(layout: layout)
                .opacity(goalMet ? 1 : 0)
        }
        .animation(.easeInOut(duration: 0.35), value: goalMet)
    }

    /// The photographed water surface, scaled to the glass's width at `levelY` and centred on it.
    private func surface(levelY: CGFloat, scale: CGFloat) -> some View {
        let art = GlassArt.surfaceRect
        let width = art.width * scale * layout.scale
        let height = art.height * scale * layout.scale
        let anchor = layout.point(CGPoint(x: GlassArt.centerX, y: levelY))
        // Offsets of the artwork's centre from the point that lands on the centre line.
        let dx = (art.width / 2 - (GlassArt.centerX - art.minX)) * scale * layout.scale
        let dy = (art.height / 2 - GlassArt.surfaceCenterRow) * scale * layout.scale
        return Image("glass_surface")
            .resizable()
            .frame(width: width, height: height)
            .position(x: anchor.x + dx, y: anchor.y + dy)
            .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
    }

    /// A faint milky haze filling the water inside the glass, a little denser toward the bottom,
    /// so the water reads as slightly cloudy and the words behind it a bit washed out.
    private func haze(levelY: CGFloat) -> some View {
        let top = layout.y(levelY), bottom = layout.y(GlassArt.waterBottomY)
        let height = max(layout.size.height, 1)
        return WaterBodyShape(layout: layout, levelY: levelY)
            .fill(LinearGradient(
                stops: [
                    .init(color: .white.opacity(0.07), location: top / height),
                    .init(color: .white.opacity(0.13), location: bottom / height),
                ],
                startPoint: .top, endPoint: .bottom
            ))
            .blur(radius: 2 * layout.scale) // soft edges against the glass walls
            .frame(width: layout.size.width, height: layout.size.height)
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

/// "DAILY GOAL MET!" laid out like the photo's words: same line positions and cap height,
/// in a condensed bold face close to the photo's lettering, coloured green.
private struct GoalMetWords: View {
    let layout: GlassCanvasLayout

    /// Bright green so the met goal stands out against the blue water.
    static let goalGreen = Color(red: 0.22, green: 0.88, blue: 0.42)

    var body: some View {
        let lines = ["DAILY", "GOAL", "MET!"]
        // SF's cap height is about 0.705 of the point size.
        let fontSize = GlassArt.wordCapHeight / 0.705 * layout.scale
        ZStack(alignment: .topLeading) {
            ForEach(Array(zip(lines.indices, lines)), id: \.0) { index, line in
                let center = layout.point(CGPoint(x: GlassArt.wordsCenterX, y: GlassArt.wordLineCenters[index]))
                Text(line)
                    .font(.system(size: fontSize, weight: .bold).width(.condensed))
                    .foregroundStyle(Self.goalGreen)
                    .fixedSize()
                    .position(center)
            }
        }
        .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
        .dynamicTypeSize(.large) // part of the artwork, so it doesn't follow text-size settings
    }
}

// MARK: - Waterline

/// Where the water surface is on screen, as an ellipse: its centre line and its front edge.
struct Waterline: Equatable {
    var levelY: CGFloat
    var centerX: CGFloat
    var halfWidth: CGFloat
    var frontDepth: CGFloat

    /// Screen y of the surface's front edge at `x` (the centre line beyond the glass walls).
    func frontEdgeY(atX x: CGFloat) -> CGFloat {
        guard halfWidth > 0 else { return levelY }
        let u = (x - centerX) / halfWidth
        guard abs(u) < 1 else { return levelY }
        return levelY + frontDepth * sqrt(1 - u * u)
    }
}

/// The water inside the glass: from the surface's centre line down to the base, between the walls.
struct WaterBodyShape: Shape {
    let layout: GlassCanvasLayout
    let levelY: CGFloat

    func path(in rect: CGRect) -> Path {
        let bottom = GlassArt.waterBottomY
        guard levelY < bottom else { return Path() }
        let steps = 24
        let rows = (0...steps).map { levelY + (bottom - levelY) * CGFloat($0) / CGFloat(steps) }
        func wall(_ y: CGFloat, side: CGFloat) -> CGPoint {
            layout.point(CGPoint(x: GlassArt.centerX + side * GlassArt.surfaceWidth(atLevelY: y) / 2, y: y))
        }
        var path = Path()
        path.move(to: wall(rows[0], side: -1))
        for y in rows.dropFirst() { path.addLine(to: wall(y, side: -1)) }
        for y in rows.reversed() { path.addLine(to: wall(y, side: 1)) }
        path.closeSubpath()
        return path
    }
}

/// The part of the screen above or below the waterline.
struct WaterlineShape: Shape {
    enum Region { case belowCentreLine, aboveFrontEdge, belowFrontEdge }

    let waterline: Waterline
    let region: Region

    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch region {
        case .belowCentreLine:
            let top = max(rect.minY, min(waterline.levelY, rect.maxY))
            path.addRect(CGRect(x: rect.minX, y: top, width: rect.width, height: rect.maxY - top))
        case .aboveFrontEdge:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: waterline.levelY))
            for point in frontEdge(in: rect).reversed() { path.addLine(to: point) }
            path.closeSubpath()
        case .belowFrontEdge:
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            for point in frontEdge(in: rect) { path.addLine(to: point) }
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.closeSubpath()
        }
        return path
    }

    /// The front edge sampled left to right across the screen.
    private func frontEdge(in rect: CGRect) -> [CGPoint] {
        let steps = 48
        let left = waterline.centerX - waterline.halfWidth, right = waterline.centerX + waterline.halfWidth
        var points = [CGPoint(x: rect.minX, y: waterline.levelY), CGPoint(x: left, y: waterline.levelY)]
        for i in 0...steps {
            let x = left + (right - left) * CGFloat(i) / CGFloat(steps)
            points.append(CGPoint(x: x, y: waterline.frontEdgeY(atX: x)))
        }
        points.append(CGPoint(x: right, y: waterline.levelY))
        points.append(CGPoint(x: rect.maxX, y: waterline.levelY))
        return points
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
