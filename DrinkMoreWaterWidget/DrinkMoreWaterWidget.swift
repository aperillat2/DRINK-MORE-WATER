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
    /// The blue around the glass in the app's photo, so the glass blends into the widget.
    static let appBlue = GlassArt.widgetBackground
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

/// A still version of the app's glass: the same photos, water surface and words, filled to
/// today's level. (Widgets are static snapshots, so the water doesn't move.)
struct WidgetGlassView: View {
    let snapshot: WaterSnapshot

    private let crop = GlassArt.widgetCropRect

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let scale = min(size.width / crop.width, size.height / crop.height)
            // The crop fitted and centred in the available space.
            let transform = PhotoTransform(
                origin: CGPoint(x: size.width / 2 - crop.midX * scale, y: size.height / 2 - crop.midY * scale),
                scale: scale
            )
            let fraction = GlassArt.fillFraction(intake: snapshot.intake, goal: snapshot.goal, perTap: snapshot.perTap)
            let hasWater = snapshot.intake > 0 && fraction > 0.001
            let levelY = GlassArt.levelY(forFraction: fraction)
            let waterline = hasWater ? transform.waterline(atLevelY: levelY) : .none(below: size.height)
            let cropRect = transform.rect(crop)

            ZStack(alignment: .topLeading) {
                placed("widget_glass_empty", in: cropRect, size: size)
                if hasWater {
                    placed("widget_glass_water", in: cropRect, size: size)
                        .mask(WaterlineShape(waterline: waterline, region: .belowCentreLine))
                }
                words(transform: transform, size: size)
                    .mask(WaterlineShape(waterline: waterline, region: .aboveFrontEdge))
                if hasWater {
                    words(transform: transform, size: size)
                        .colorMultiply(GlassArt.underwaterTint)
                        .blur(radius: 0.6 * scale)
                        .opacity(0.94)
                        .mask(WaterlineShape(waterline: waterline, region: .belowFrontEdge))
                    WaterHaze(transform: transform, levelY: levelY, size: size)
                    placed("widget_glass_surface", in: transform.surfaceRect(atLevelY: levelY), size: size)
                }
            }
            .frame(width: size.width, height: size.height)
            // Fade the photo's edges into the widget's background (the same blue).
            .mask(
                Rectangle()
                    .frame(width: cropRect.width - 48 * scale, height: cropRect.height - 48 * scale)
                    .position(x: cropRect.midX, y: cropRect.midY)
                    .blur(radius: 12 * scale)
            )
        }
        .aspectRatio(crop.width / crop.height, contentMode: .fit)
        .accessibilityHidden(true)
    }

    /// An image stretched to fill `rect` inside a full-size layer.
    private func placed(_ name: String, in rect: CGRect, size: CGSize) -> some View {
        Image(name)
            .resizable()
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    /// "DRINK MORE WATER" from the photo, or the green "DAILY GOAL MET!" once the goal is met.
    @ViewBuilder
    private func words(transform: PhotoTransform, size: CGSize) -> some View {
        if snapshot.isGoalMet {
            GoalMetWords(transform: transform, size: size)
        } else {
            placed("widget_glass_words", in: transform.rect(GlassArt.wordsRect), size: size)
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
