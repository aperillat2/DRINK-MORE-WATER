import Foundation
import CoreGraphics

public struct FillFractionCalculator {
    public init() {}

    // Mirrors the refined algorithm from ContentView: trims bottom/top, ensures first step is visible, last is below rim.
    public func fraction(intakeOz: CGFloat, goalOz: CGFloat, bounds: WaterMaskBounds, perTapOz: CGFloat) -> CGFloat {
        let goal = max(goalOz, 0)
        let intake = max(0, min(goal, intakeOz))
        let perTap = max(1, perTapOz)
        let span = max(bounds.fullFraction - bounds.emptyFraction, 0.001)
        let totalSteps = max(1, Int(ceil(goal / perTap)))

        // Trim the bottom/top according to the mask so the first tap is visible
        // while keeping the final tap just below the rim.
        let bottomTrim = min(span * 0.3, span / CGFloat(totalSteps) * 2.6)
        let topTrim = min(span * 0.03, span / CGFloat(totalSteps) * 0.4)

        let minFraction = min(bounds.fullFraction - topTrim, bounds.emptyFraction + bottomTrim)
        let maxFraction = max(minFraction, bounds.fullFraction - topTrim)

        if goal <= 0 || intake <= 0 {
            return bounds.emptyFraction
        }
        if intake >= goal {
            return maxFraction
        }

        let normalized = max(0, min(1, (intake - perTap) / max(goal - perTap, 1)))
        let fraction = minFraction + normalized * (maxFraction - minFraction)
        return max(bounds.emptyFraction, min(fraction, maxFraction))
    }
}
