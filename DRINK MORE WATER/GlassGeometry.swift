import SwiftUI

// Shared by the app and the widget, so both draw the same glass.

// MARK: - Artwork geometry

/// Measurements of the glass photos, in pixels of the original 896×1200 photo.
///
/// All of the glass artwork comes from two pixel-aligned photos — the splash photo
/// (water + "DRINK MORE WATER") and the same glass empty — so every layer shares one coordinate
/// space. In the app, the photo sits unscaled in the middle of a 2400×1800 canvas whose margins
/// continue its blue background (`glass_background` and `splash_photo` are both that canvas).
/// Showing the canvas aspect-filled puts the glass in exactly the same place as on the splash
/// screen, on every device. The widget uses smaller copies cropped to `widgetCropRect`.
/// `Tools/BuildGlassAssets.swift` makes all of these images; its measurements must match these.
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

    /// The widget's crop around the glass (`widget_glass_empty` / `widget_glass_water`).
    static let widgetCropRect = CGRect(x: 160, y: 100, width: 580, height: 990)
    /// The average blue just around the glass, used behind the widget's glass so it blends in.
    static let widgetBackground = Color(red: 0, green: 104 / 255, blue: 220 / 255)

    /// Underwater tint and haze, shared so the app and widget water look the same.
    static let underwaterTint = Color(red: 0.86, green: 0.95, blue: 1.0)

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

    /// How full the glass is drawn for an intake (0 = empty, 1 = full). A met goal is always full.
    static func fillFraction(intake: Int, goal: Int, perTap: Int) -> CGFloat {
        let bounds = WaterMaskBounds.photoGlass
        if goal > 0 && intake >= goal { return bounds.fullFraction }
        return FillFractionCalculator().fraction(
            intakeOz: CGFloat(intake), goalOz: CGFloat(goal), bounds: bounds, perTapOz: CGFloat(perTap)
        )
    }
}

/// Photo pixels → screen points: where the photo's top-left corner lands, and points per pixel.
struct PhotoTransform: Equatable {
    var origin: CGPoint
    var scale: CGFloat

    func point(_ p: CGPoint) -> CGPoint {
        CGPoint(x: origin.x + p.x * scale, y: origin.y + p.y * scale)
    }

    func y(_ photoY: CGFloat) -> CGFloat { origin.y + photoY * scale }

    func rect(_ r: CGRect) -> CGRect {
        CGRect(origin: point(r.origin), size: CGSize(width: r.width * scale, height: r.height * scale))
    }

    /// Where the photographed surface artwork (`glass_surface`) goes for a level: scaled to the
    /// glass's width there, with its centre line on the level.
    func surfaceRect(atLevelY levelY: CGFloat) -> CGRect {
        let art = GlassArt.surfaceRect
        let s = GlassArt.surfaceScale(atLevelY: levelY)
        let anchor = point(CGPoint(x: GlassArt.centerX, y: levelY))
        let size = CGSize(width: art.width * s * scale, height: art.height * s * scale)
        return CGRect(x: anchor.x - (GlassArt.centerX - art.minX) * s * scale,
                      y: anchor.y - GlassArt.surfaceCenterRow * s * scale,
                      width: size.width, height: size.height)
    }

    /// The water surface at a level, on screen.
    func waterline(atLevelY levelY: CGFloat) -> Waterline {
        let surfaceScale = GlassArt.surfaceScale(atLevelY: levelY)
        return Waterline(
            levelY: y(levelY),
            centerX: point(CGPoint(x: GlassArt.centerX, y: 0)).x,
            halfWidth: GlassArt.surfaceWidth(atLevelY: levelY) / 2 * scale,
            frontDepth: GlassArt.surfaceFrontDepth * surfaceScale * scale
        )
    }
}

// MARK: - Waterline

/// Where the water surface is on screen, as an ellipse: its centre line and its front edge.
struct Waterline: Equatable {
    var levelY: CGFloat
    var centerX: CGFloat
    var halfWidth: CGFloat
    var frontDepth: CGFloat

    /// Everything counts as "above" the water: used when the glass is empty.
    static func none(below height: CGFloat) -> Waterline {
        Waterline(levelY: height + 1, centerX: 0, halfWidth: 0, frontDepth: 0)
    }

    /// Screen y of the surface's front edge at `x` (the centre line beyond the glass walls).
    func frontEdgeY(atX x: CGFloat) -> CGFloat {
        guard halfWidth > 0 else { return levelY }
        let u = (x - centerX) / halfWidth
        guard abs(u) < 1 else { return levelY }
        return levelY + frontDepth * sqrt(1 - u * u)
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

/// The water inside the glass: from the surface's centre line down to the base, between the walls.
struct WaterBodyShape: Shape {
    let transform: PhotoTransform
    let levelY: CGFloat

    func path(in rect: CGRect) -> Path {
        let bottom = GlassArt.waterBottomY
        guard levelY < bottom else { return Path() }
        let steps = 24
        let rows = (0...steps).map { levelY + (bottom - levelY) * CGFloat($0) / CGFloat(steps) }
        func wall(_ y: CGFloat, side: CGFloat) -> CGPoint {
            transform.point(CGPoint(x: GlassArt.centerX + side * GlassArt.surfaceWidth(atLevelY: y) / 2, y: y))
        }
        var path = Path()
        path.move(to: wall(rows[0], side: -1))
        for y in rows.dropFirst() { path.addLine(to: wall(y, side: -1)) }
        for y in rows.reversed() { path.addLine(to: wall(y, side: 1)) }
        path.closeSubpath()
        return path
    }
}

/// A faint milky haze filling the water inside the glass, a little denser toward the bottom,
/// so the water reads as slightly cloudy and the words behind it a bit washed out.
struct WaterHaze: View {
    let transform: PhotoTransform
    let levelY: CGFloat
    let size: CGSize

    var body: some View {
        let top = transform.y(levelY), bottom = transform.y(GlassArt.waterBottomY)
        let height = max(size.height, 1)
        WaterBodyShape(transform: transform, levelY: levelY)
            .fill(LinearGradient(
                stops: [
                    .init(color: .white.opacity(0.07), location: top / height),
                    .init(color: .white.opacity(0.13), location: bottom / height),
                ],
                startPoint: .top, endPoint: .bottom
            ))
            .blur(radius: 2 * transform.scale) // soft edges against the glass walls
            .frame(width: size.width, height: size.height)
    }
}

// MARK: - Words on the glass

/// "DRINK MORE WATER" on the glass. In English this is the lettering lifted from the splash photo
/// (`photoImageName`), so the main screen matches the splash screen exactly; in other languages
/// it's drawn as translated text in the same place and style.
struct DrinkMoreWaterWords: View {
    let transform: PhotoTransform
    let size: CGSize
    /// The photo lettering for this target (`glass_words` in the app, `widget_glass_words` in the widget).
    let photoImageName: String

    /// Whether the app is running in English, where the photo lettering is used.
    static var usesPhotoLettering: Bool {
        Bundle.main.preferredLocalizations.first?.hasPrefix("en") ?? true
    }

    var body: some View {
        if Self.usesPhotoLettering {
            let rect = transform.rect(GlassArt.wordsRect)
            Image(photoImageName)
                .resizable()
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                .frame(width: size.width, height: size.height, alignment: .topLeading)
        } else {
            // Each word is one line on the glass, so translations should stay short.
            GlassWordLines(
                lines: [
                    LocalizedStringResource("DRINK", comment: "Line 1 of 3 written on the water glass (\"DRINK MORE WATER\"). The three lines are read together as one phrase; reorder words between lines as needed. Keep each line very short."),
                    LocalizedStringResource("MORE", comment: "Line 2 of 3 written on the water glass (\"DRINK MORE WATER\"). The three lines are read together as one phrase; reorder words between lines as needed. Keep each line very short."),
                    LocalizedStringResource("WATER", comment: "Line 3 of 3 written on the water glass (\"DRINK MORE WATER\"). The three lines are read together as one phrase; reorder words between lines as needed. Keep each line very short."),
                ],
                color: .white,
                transform: transform,
                size: size
            )
        }
    }
}

/// "DAILY GOAL MET!" in place of "DRINK MORE WATER", coloured green.
struct GoalMetWords: View {
    let transform: PhotoTransform
    let size: CGSize

    /// Bright green so the met goal stands out against the blue water.
    static let goalGreen = Color(red: 0.22, green: 0.88, blue: 0.42)

    var body: some View {
        // Each word is one line on the glass, so translations should stay short.
        GlassWordLines(
            lines: [
                LocalizedStringResource("DAILY", comment: "Goal met, line 1 of 3 on the glass (\"DAILY GOAL MET!\")"),
                LocalizedStringResource("GOAL", comment: "Goal met, line 2 of 3 on the glass"),
                LocalizedStringResource("MET!", comment: "Goal met, line 3 of 3 on the glass"),
            ],
            color: Self.goalGreen,
            transform: transform,
            size: size
        )
    }
}

/// Three lines of text laid out like the photo's words: same line positions and cap height,
/// in a condensed bold face close to the photo's lettering.
struct GlassWordLines: View {
    let lines: [LocalizedStringResource]
    let color: Color
    let transform: PhotoTransform
    let size: CGSize

    /// The widest a line may be (photo pixels) before it shrinks to stay inside the glass walls.
    private static let maxLineWidth: CGFloat = 420

    /// Chinese, Japanese and Korean characters fill nearly the whole em square, much taller than
    /// Latin capitals, so they're drawn smaller to keep the lines from touching.
    private static var fontScale: CGFloat {
        let language = Bundle.main.preferredLocalizations.first ?? ""
        return ["ja", "ko", "zh"].contains { language.hasPrefix($0) } ? 0.8 : 1
    }

    var body: some View {
        // SF's cap height is about 0.705 of the point size.
        let fontSize = GlassArt.wordCapHeight / 0.705 * Self.fontScale * transform.scale
        ZStack(alignment: .topLeading) {
            ForEach(lines.indices, id: \.self) { index in
                let center = transform.point(CGPoint(x: GlassArt.wordsCenterX, y: GlassArt.wordLineCenters[index]))
                Text(lines[index])
                    .font(.system(size: fontSize, weight: .bold).width(.condensed))
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .frame(width: Self.maxLineWidth * transform.scale)
                    .position(center)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .dynamicTypeSize(.large) // part of the artwork, so it doesn't follow text-size settings
    }
}
