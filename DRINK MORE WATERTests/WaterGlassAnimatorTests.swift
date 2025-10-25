import Foundation
import Testing
@testable import DRINK_MORE_WATER

@Suite("WaterGlassAnimator")
struct WaterGlassAnimatorTests {
    @MainActor
    @Test("reaches target fraction after duration")
    func reachesTargetFraction() {
        let animator = WaterGlassAnimator()
        animator.configure(initialFraction: 0.2)

        var snap = animator.snapshot(now: 0, frozenPhase: nil)
        #expect(abs(snap.fraction - 0.2) < 0.0001)

        animator.updateTargetFraction(0.8, now: 0)

        snap = animator.snapshot(now: 1.5, frozenPhase: nil)
        #expect(abs(snap.fraction - 0.8) < 0.0001)

        snap = animator.snapshot(now: 2.0, frozenPhase: nil)
        #expect(abs(snap.fraction - 0.8) < 0.0001)
    }

    @MainActor
    @Test("freezes and resumes glare phase")
    func freezesAndResumesGlare() {
        let animator = WaterGlassAnimator()
        animator.configure(initialFraction: 0.4)

        let frozen = animator.snapshot(now: 0, frozenPhase: 1.0)
        #expect(frozen.ripplePhase == 1.0)

        let resumed = animator.snapshot(now: 1.0, frozenPhase: nil)
        let resumed2 = animator.snapshot(now: 2.0, frozenPhase: nil)
        #expect(resumed2.glarePhase > resumed.glarePhase)
    }
}
