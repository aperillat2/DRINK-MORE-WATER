import Foundation
import UIKit

protocol Haptics {
    func impactLight()
    func success()
}

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

enum HapticsFactory {
    static func `default`() -> Haptics {
        return iOSHaptics()
    }
}
