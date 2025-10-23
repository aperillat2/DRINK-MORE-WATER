//
//  ContentView.swift
//  DRINK MORE WATER
//
//  Created by AARON PERILLAT on 10/22/25.
//
import SwiftUI

struct ContentView: View {
    @AppStorage("intakeOz") private var intakeOz: Int = 0
    @AppStorage("lastIntakeDate") private var lastIntakeDateString: String = ""
    @AppStorage("dailyGoalOz") private var dailyGoalOz: Int = 80
    @Environment(\.scenePhase) private var scenePhase
    @State private var showResetConfirmation: Bool = false

    private let glassVerticalNudge: CGFloat = -6
    private let textScale: CGFloat = 0.54
    private let textOffset: CGSize = CGSize(width: 0, height: 58)
    private let maskVerticalOffset: CGFloat = 6

    private let ozPerTap: Int = 10

    private var fillFraction: CGFloat {
        let baselineVisualOz: CGFloat = 20 // visual height for first tap
        let goal = CGFloat(dailyGoalOz)
        let intake = CGFloat(intakeOz)
        let perTap = CGFloat(ozPerTap)

        if intake <= 0 { return 0 }
        if intake >= goal { return 1 }

        let baselineFraction = baselineVisualOz / goal
        // Normalize intake from [perTap, goal] -> [0, 1]
        let t = max(0, min(1, (intake - perTap) / max(1, (goal - perTap))))
        let fraction = baselineFraction + t * (1 - baselineFraction)
        return max(0, min(1, fraction))
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
                    .frame(width: 551, height: 722)
                    .scaleEffect(textScale)
                    .offset(y: glassVerticalNudge)
                    .offset(x: textOffset.width, y: textOffset.height)
                    .accessibilityHidden(true)

                // Water fill layer (masked to the interior of the glass)
                ZStack(alignment: .bottom) {
                    LinearGradient(colors: [Color.white, Color.white], startPoint: .top, endPoint: .bottom)
                        .frame(width: 551, height: 722 * fillFraction)
                        .clipped()
                }
                .frame(width: 551, height: 722, alignment: .bottom)
                .mask(
                    Image("glass_mask")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 551, height: 722)
                        .offset(y: glassVerticalNudge + maskVerticalOffset)
                )
                .allowsHitTesting(false)

                Image("empty_glass")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 551, height: 722)
                    .offset(y: glassVerticalNudge)
                    .accessibilityHidden(true)
            }
            .onTapGesture(perform: handleTap)

            VStack {
                Spacer()
                VStack(spacing: 8) {
                    Text("Daily Goal: \(dailyGoalOz) oz")
                        .font(.headline)
                        .foregroundStyle(.white)
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
                .padding(16)
                .background(Color.black.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
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
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active { resetIfNeeded() }
        }
    }
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
