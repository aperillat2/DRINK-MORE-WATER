import SwiftUI

/// The dimmed overlay with the title/detail text and Skip/Next buttons for each walkthrough step.
struct WalkthroughOverlay: View {
    /// nil = not showing; 1...3 = current step.
    @Binding var step: Int?
    let unitLabel: String
    /// Called when the user skips or finishes.
    var onFinish: () -> Void

    var body: some View {
        if let current = step, let info = info(for: current) {
            GeometryReader { proxy in
                let textWidth = textWidth(for: proxy.size.width)

                ZStack {
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()
                        .transition(.opacity)

                    ScrollView {
                        VStack(spacing: 16) {
                            Text(info.title)
                                .font(.title2).bold()
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .lineLimit(nil)
                                .frame(width: textWidth, alignment: .center)
                                .fixedSize(horizontal: false, vertical: true)

                            Text(info.detail)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.white.opacity(0.9))
                                .lineLimit(nil)
                                .frame(width: textWidth, alignment: .center)
                                .fixedSize(horizontal: false, vertical: true)

                            HStack(spacing: 16) {
                                Button("Skip") {
                                    step = nil
                                    onFinish()
                                }
                                .buttonStyle(.bordered)
                                .tint(.white)

                                Button(info.isFinal ? "Done" : "Next") {
                                    if info.isFinal {
                                        step = nil
                                        onFinish()
                                    } else {
                                        step = current + 1
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal)
                        .padding(.top, 170)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .accessibilityAddTraits(.isModal)
                .transition(.opacity)
            }
        }
    }

    private func info(for step: Int) -> (title: String, detail: String, isFinal: Bool)? {
        switch step {
        case 1:
            return (
                String(localized: "Tap the glass to add water."),
                String(localized: "When the glass is full, you've met your daily goal."),
                false
            )
        case 2:
            return (
                String(localized: "Adjust your daily goal."),
                String(localized: "Use the Daily goal slider to choose how much you want to drink today."),
                false
            )
        case 3:
            return (
                String(localized: "Set amount per tap."),
                String(localized: "Change how much water gets added each time by adjusting the \(unitLabel) value."),
                true
            )
        default:
            return nil
        }
    }

    private func textWidth(for totalWidth: CGFloat) -> CGFloat {
        let padding: CGFloat = 48
        let minWidth: CGFloat = 220
        let maxWidth: CGFloat = 360
        let available = totalWidth - padding
        return min(max(available, minWidth), maxWidth)
    }
}

/// Animated tapping hand shown on the control each walkthrough step points at.
struct HandPointerOverlayView: View {
    var size = CGSize(width: 80, height: 80)
    private let gesturePeriod: TimeInterval = 1.2
    private let updateInterval: TimeInterval = 1.0 / 30.0

    var body: some View {
        TimelineView(.periodic(from: .now, by: updateInterval)) { context in
            let state = animationState(for: context.date)
            ZStack(alignment: .topLeading) {
                rippleView(state.ripple1)
                    .offset(x: state.tipOffset.width, y: state.tipOffset.height)
                rippleView(state.ripple2)
                    .offset(x: state.tipOffset.width, y: state.tipOffset.height)
                handImage(state.hand)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func animationState(for date: Date) -> AnimationState {
        let elapsed = date.timeIntervalSinceReferenceDate
        let normalized = (elapsed.truncatingRemainder(dividingBy: gesturePeriod)) / gesturePeriod
        let secondary = (normalized + 0.5).truncatingRemainder(dividingBy: 1.0)
        let press = sin(normalized * .pi)
        let tipOffset = CGSize(width: size.width * 0.55, height: size.height * 0.18)

        let ripple1 = RippleState(
            size: 24 + 22 * normalized,
            opacity: 0.5 * (1 - normalized),
            lineWidth: 3
        )
        let ripple2 = RippleState(
            size: 18 + 28 * secondary,
            opacity: 0.35 * (1 - secondary),
            lineWidth: 2
        )
        let hand = HandState(
            scale: 2.0 - 0.07 * press,
            offset: CGSize(width: 6 * press, height: 10 * press)
        )

        return AnimationState(
            tipOffset: tipOffset,
            ripple1: ripple1,
            ripple2: ripple2,
            hand: hand
        )
    }

    private func rippleView(_ ripple: RippleState) -> some View {
        Circle()
            .stroke(Color.white.opacity(ripple.opacity), lineWidth: ripple.lineWidth)
            .frame(width: ripple.size, height: ripple.size)
    }

    private func handImage(_ hand: HandState) -> some View {
        Image("hand")
            .resizable()
            .renderingMode(.original)
            .scaledToFit()
            .frame(width: size.width, height: size.height)
            .shadow(color: Color.black.opacity(0.3), radius: 6, x: 0, y: 3)
            .scaleEffect(hand.scale, anchor: UnitPoint.topLeading)
            .offset(x: hand.offset.width, y: hand.offset.height)
            .opacity(0.75)
    }

    private struct AnimationState {
        let tipOffset: CGSize
        let ripple1: RippleState
        let ripple2: RippleState
        let hand: HandState
    }

    private struct RippleState {
        let size: CGFloat
        let opacity: Double
        let lineWidth: CGFloat
    }

    private struct HandState {
        let scale: CGFloat
        let offset: CGSize
    }
}
