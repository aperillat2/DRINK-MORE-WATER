import Foundation
#if os(iOS)
import UIKit
#endif

protocol Haptics {
    func impactLight()
    func success()
}

struct NoOpHaptics: Haptics {
    func impactLight() {}
    func success() {}
}

#if os(iOS)
struct iOSHaptics: Haptics {
    func impactLight() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
    }
    func success() {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
    }
}
#endif

enum HapticsFactory {
    static func `default`() -> Haptics {
        #if os(iOS)
        return iOSHaptics()
        #else
        return NoOpHaptics()
        #endif
    }
}
