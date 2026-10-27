//
//  DrinkMoreWaterWidget.swift
//  DrinkMoreWaterWidget
//
//  Created by AARON PERILLAT on 10/26/26.
//

import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Timeline

struct WaterEntry: TimelineEntry {
    let date: Date
    let snapshot: WaterSnapshot
}

struct WaterProvider: TimelineProvider {
    func placeholder(in context: Context) -> WaterEntry {
        WaterEntry(date: Date(), snapshot: WaterSnapshot(intake: 40, goal: 80, perTap: 10, unit: .oz))
    }

    func getSnapshot(in context: Context, completion: @escaping (WaterEntry) -> Void) {
        // The widget gallery shows a half-full glass rather than the user's (maybe empty) one.
        if context.isPreview {
            completion(placeholder(in: context))
        } else {
            completion(WaterEntry(date: Date(), snapshot: WaterSnapshot.load()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WaterEntry>) -> Void) {
        let now = Date()
        let current = WaterSnapshot.load(at: now)
        var entries = [WaterEntry(date: now, snapshot: current)]

        // Empty the glass at midnight without needing the app to run.
        let calendar = Calendar.current
        if let midnight = calendar.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0),
                                            matchingPolicy: .nextTime) {
            entries.append(WaterEntry(date: midnight, snapshot: current.startingNewDay()))
        }
        // After the last entry (midnight), ask for a fresh timeline. Taps in the app or on the
        // widget's button also reload it immediately.
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

// MARK: - Widget

struct DrinkMoreWaterWidget: Widget {
    let kind: String = "DrinkMoreWaterWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WaterProvider()) { entry in
            WaterWidgetView(entry: entry)
        }
        .configurationDisplayName("Water Intake")
        .description("See today's progress and add water with a tap.")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryCircular, .accessoryRectangular, .accessoryInline,
        ])
    }
}

/// Picks the layout for each widget size.
struct WaterWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WaterEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            CircularAccessoryView(snapshot: entry.snapshot)
                .containerBackground(.clear, for: .widget)
        case .accessoryRectangular:
            RectangularAccessoryView(snapshot: entry.snapshot)
                .containerBackground(.clear, for: .widget)
        case .accessoryInline:
            Text("\(entry.snapshot.intake) / \(entry.snapshot.goal) \(entry.snapshot.unit.label)")
                .containerBackground(.clear, for: .widget)
        case .systemMedium:
            MediumWaterView(snapshot: entry.snapshot)
                .containerBackground(WidgetStyle.appBlue, for: .widget)
        case .systemLarge:
            LargeWaterView(snapshot: entry.snapshot)
                .containerBackground(WidgetStyle.appBlue, for: .widget)
        default:
            SmallWaterView(snapshot: entry.snapshot)
                .containerBackground(WidgetStyle.appBlue, for: .widget)
        }
    }
}

enum WidgetStyle {
    /// Same blue as the app's background (`Color(.systemBlue)` in light mode).
    static let appBlue = Color(red: 0, green: 136 / 255, blue: 1)
}

// MARK: - Home Screen sizes

private struct SmallWaterView: View {
    let snapshot: WaterSnapshot

    var body: some View {
        VStack(spacing: 6) {
            WidgetGlassView(snapshot: snapshot)
                // No amount text in this size, so the glass speaks the progress for VoiceOver.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(snapshot.intake) of \(snapshot.goal) \(snapshot.unit.spokenName)")
            AddWaterButton(snapshot: snapshot, compact: true)
        }
    }
}

private struct MediumWaterView: View {
    let snapshot: WaterSnapshot

    var body: some View {
        HStack(spacing: 16) {
            WidgetGlassView(snapshot: snapshot)
            VStack(alignment: .leading, spacing: 10) {
                Text("Today")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
                ProgressLabel(snapshot: snapshot, font: .title2)
                AddWaterButton(snapshot: snapshot)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct LargeWaterView: View {
    let snapshot: WaterSnapshot

    var body: some View {
        VStack(spacing: 12) {
            ProgressLabel(snapshot: snapshot, font: .title.weight(.semibold))
            WidgetGlassView(snapshot: snapshot)
            AddWaterButton(snapshot: snapshot)
        }
    }
}

/// "40 / 80 oz", spoken as "40 of 80 ounces".
private struct ProgressLabel: View {
    let snapshot: WaterSnapshot
    let font: Font

    var body: some View {
        Text("\(snapshot.intake) / \(snapshot.goal) \(snapshot.unit.label)")
            .font(font.weight(.semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .accessibilityLabel("\(snapshot.intake) of \(snapshot.goal) \(snapshot.unit.spokenName)")
    }
}

/// Runs `AddWaterIntent` without opening the app. Shows a "Goal met" badge instead once full.
private struct AddWaterButton: View {
    let snapshot: WaterSnapshot
    /// Smaller, single-line version for the small widget.
    var compact = false

    var body: some View {
        if snapshot.isGoalMet {
            // The badge takes exactly the button's space (via a hidden copy of the button),
            // so the glass doesn't change size when the goal is reached.
            // Left-aligned like the rest of the medium/large text; centered in the small widget.
            ZStack(alignment: compact ? .center : .leading) {
                addButton.hidden()
                Label("Goal met!", systemImage: "checkmark.circle.fill")
                    .font(font)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        } else {
            addButton
        }
    }

    private var font: Font { compact ? .subheadline.weight(.semibold) : .headline }

    private var addButton: some View {
        Button(intent: AddWaterIntent()) {
            Label("Add \(snapshot.perTap) \(snapshot.unit.label)", systemImage: "plus")
                .font(font)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, compact ? 0 : 6)
        }
        .buttonStyle(.borderedProminent)
        .tint(.white)
        .foregroundStyle(WidgetStyle.appBlue)
        .accessibilityLabel("Add \(snapshot.perTap) \(snapshot.unit.spokenName)")
    }
}

// MARK: - Lock Screen sizes

/// Lock Screen widgets are tappable on iPhone and iPad: the whole widget adds water,
/// without unlocking (see `AddWaterIntent.authenticationPolicy`). Once the goal is met,
/// there's nothing to add, so it's plain content instead of a button.
private struct LockScreenAddButton<Content: View>: View {
    let snapshot: WaterSnapshot
    @ViewBuilder var content: () -> Content

    var body: some View {
        if snapshot.isGoalMet {
            content()
        } else {
            Button(intent: AddWaterIntent()) {
                content()
            }
            .buttonStyle(.plain)
            .accessibilityHint("Adds \(snapshot.perTap) \(snapshot.unit.spokenName)")
        }
    }
}

private struct CircularAccessoryView: View {
    let snapshot: WaterSnapshot

    var body: some View {
        LockScreenAddButton(snapshot: snapshot) {
            Gauge(value: Double(min(snapshot.intake, snapshot.goal)), in: 0...Double(max(snapshot.goal, 1))) {
                // "+" says "tap to add"; a checkmark once the goal is met.
                Image(systemName: snapshot.isGoalMet ? "checkmark" : "plus")
            } currentValueLabel: {
                Text("\(snapshot.intake)")
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .accessibilityLabel("Water")
            .accessibilityValue("\(snapshot.intake) of \(snapshot.goal) \(snapshot.unit.spokenName)")
        }
    }
}

private struct RectangularAccessoryView: View {
    let snapshot: WaterSnapshot

    var body: some View {
        LockScreenAddButton(snapshot: snapshot) {
            VStack(alignment: .leading, spacing: 2) {
                Label("Water", systemImage: "drop.fill")
                    .font(.headline)
                    .widgetAccentable()
                HStack(spacing: 4) {
                    Text("\(snapshot.intake) / \(snapshot.goal) \(snapshot.unit.label)")
                        .font(.body.weight(.semibold))
                    Spacer(minLength: 0)
                    Image(systemName: snapshot.isGoalMet ? "checkmark.circle.fill" : "plus.circle.fill")
                        .font(.title3)
                        .widgetAccentable()
                }
                ProgressView(value: Double(min(snapshot.intake, snapshot.goal)), total: Double(max(snapshot.goal, 1)))
                    .tint(.white)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Water, \(snapshot.intake) of \(snapshot.goal) \(snapshot.unit.spokenName)")
        }
    }
}

// MARK: - Glass

/// A still version of the app's glass: the same artwork, filled to today's level.
/// (Widgets are static snapshots, so there's no live water animation.)
struct WidgetGlassView: View {
    let snapshot: WaterSnapshot

    /// The artwork is a 551×722 canvas; the visible glass is roughly 300×550 in the middle.
    private let canvas = CGSize(width: 551, height: 722)
    private let visible = CGSize(width: 300, height: 550)

    private var fillFraction: CGFloat {
        FillFractionCalculator().fraction(
            intakeOz: CGFloat(snapshot.intake),
            goalOz: CGFloat(snapshot.goal),
            bounds: .glass,
            perTapOz: CGFloat(snapshot.perTap)
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.width / visible.width, proxy.size.height / visible.height)
            let size = CGSize(width: canvas.width * scale, height: canvas.height * scale)
            // Centered, like the app: the square artwork sits in the middle of the 551×722 canvas,
            // which is what the fill fraction is measured against.
            let waterY = size.height * (1 - fillFraction)
            ZStack {
                // Water body: a rectangle up to the fill level, clipped to the inside of the glass.
                // Same colors as the app's WaterFillRenderer.
                LinearGradient(
                    stops: [
                        .init(color: Color(red: 0.857, green: 0.922, blue: 0.987).opacity(0.55), location: 0),
                        .init(color: Color(red: 0.78, green: 0.88, blue: 0.98).opacity(0.34), location: 0.5),
                        .init(color: Color(red: 0.879, green: 0.946, blue: 0.991).opacity(0.56), location: 1),
                    ],
                    startPoint: UnitPoint(x: 0.3, y: 0), endPoint: UnitPoint(x: 0.7, y: 1)
                )
                .frame(height: size.height * fillFraction)
                .frame(width: size.width, height: size.height, alignment: .bottom)
                .mask(Image("glass_mask").resizable().scaledToFit())

                // Water surface, seen slightly from above (a still version of the app's surface).
                if snapshot.intake > 0 {
                    WidgetWaterSurface()
                        .frame(width: surfaceWidth(atCanvasY: waterY, canvasWidth: size.width,
                                                   canvasHeight: size.height),
                               height: surfaceHeight(atCanvasY: waterY, canvasWidth: size.width,
                                                     canvasHeight: size.height))
                        .position(x: size.width / 2, y: waterY)
                        .frame(width: size.width, height: size.height)
                        .mask(Image("glass_mask").resizable().scaledToFit())
                }

                Image("empty_glass")
                    .resizable()
                    .scaledToFit()
            }
            .frame(width: size.width, height: size.height)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .aspectRatio(visible.width / visible.height, contentMode: .fit)
        .accessibilityHidden(true)
    }

    /// Inside width of the glass at a height in the 551×722 canvas.
    /// Measured from `glass_mask`: the square artwork is centered vertically in the canvas, and its
    /// interior narrows linearly from 46.3% of the image width near the rim (y = 0.138) to
    /// 34.4% near the base (y = 0.825), in image-relative coordinates.
    private func surfaceWidth(atCanvasY y: CGFloat, canvasWidth: CGFloat, canvasHeight: CGFloat) -> CGFloat {
        let imageSide = canvasWidth                        // square image fitted to the canvas width
        let imageTop = (canvasHeight - imageSide) / 2
        let imageY = min(max((y - imageTop) / imageSide, 0.138), 0.825)
        let fraction = 0.463 - (imageY - 0.138) * (0.463 - 0.344) / (0.825 - 0.138)
        return imageSide * fraction
    }

    /// Same proportions as the app: the surface ellipse is 88:480 of its width, and slightly
    /// flatter the deeper it sits in the glass.
    private func surfaceHeight(atCanvasY y: CGFloat, canvasWidth: CGFloat, canvasHeight: CGFloat) -> CGFloat {
        let width = surfaceWidth(atCanvasY: y, canvasWidth: canvasWidth, canvasHeight: canvasHeight)
        let depth = min(max(y / canvasHeight, 0), 1)
        return width * (88.0 / 480.0) * (1.0 - 0.08 * depth)
    }
}

/// Still version of the app's `WaterSurfaceTexture`: a soft light ellipse with a highlight,
/// a bright front rim, a faint shaded back rim, and faint concentric ripple rings.
private struct WidgetWaterSurface: View {
    var body: some View {
        GeometryReader { proxy in
            let h = proxy.size.height
            ZStack {
                Ellipse().fill(Color.white.opacity(0.18))
                Ellipse().fill(
                    LinearGradient(stops: [
                        .init(color: .white.opacity(0.55), location: 0.35),
                        .init(color: .white.opacity(0.30), location: 0.65),
                        .init(color: .white.opacity(0.18), location: 1.0),
                    ], startPoint: .leading, endPoint: .trailing)
                )
                // Ripple rings
                ForEach([0.72, 0.48], id: \.self) { inset in
                    Ellipse()
                        .stroke(Color.white.opacity(0.22), lineWidth: 1)
                        .scaleEffect(inset)
                }
                // Front (near) rim catches the light; back (far) rim is slightly shaded.
                Ellipse()
                    .stroke(Color.white.opacity(0.32), lineWidth: max(1, h * 0.08))
                    .mask(VStack(spacing: 0) { Color.clear; Color.black })
                Ellipse()
                    .stroke(Color.black.opacity(0.10), lineWidth: max(1, h * 0.06))
                    .mask(VStack(spacing: 0) { Color.black; Color.clear })
            }
        }
    }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    DrinkMoreWaterWidget()
} timeline: {
    WaterEntry(date: .now, snapshot: WaterSnapshot(intake: 0, goal: 80, perTap: 10, unit: .oz))
    WaterEntry(date: .now, snapshot: WaterSnapshot(intake: 40, goal: 80, perTap: 10, unit: .oz))
    WaterEntry(date: .now, snapshot: WaterSnapshot(intake: 80, goal: 80, perTap: 10, unit: .oz))
}

#Preview("Medium", as: .systemMedium) {
    DrinkMoreWaterWidget()
} timeline: {
    WaterEntry(date: .now, snapshot: WaterSnapshot(intake: 40, goal: 80, perTap: 10, unit: .oz))
    WaterEntry(date: .now, snapshot: WaterSnapshot(intake: 2400, goal: 2400, perTap: 300, unit: .ml))
}

#Preview("Large", as: .systemLarge) {
    DrinkMoreWaterWidget()
} timeline: {
    WaterEntry(date: .now, snapshot: WaterSnapshot(intake: 50, goal: 80, perTap: 10, unit: .oz))
}

#Preview("Lock Screen", as: .accessoryRectangular) {
    DrinkMoreWaterWidget()
} timeline: {
    WaterEntry(date: .now, snapshot: WaterSnapshot(intake: 40, goal: 80, perTap: 10, unit: .oz))
}

#Preview("Lock Screen Circle", as: .accessoryCircular) {
    DrinkMoreWaterWidget()
} timeline: {
    WaterEntry(date: .now, snapshot: WaterSnapshot(intake: 40, goal: 80, perTap: 10, unit: .oz))
}
