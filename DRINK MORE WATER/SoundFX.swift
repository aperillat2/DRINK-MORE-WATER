import Foundation
import AVFoundation

/// Lightweight shared audio helper for the splash effect.
final class SoundFX {
    static let shared = SoundFX()

    private var splashPlayer: AVAudioPlayer?
    private let splashVolume: Float = 0.08

    private init() {
        #if !targetEnvironment(simulator)
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true, options: [])
        #endif
        preloadSplash()
    }

    func playSplash() {
        if splashPlayer == nil { preloadSplash() }
        splashPlayer?.stop()
        splashPlayer?.currentTime = 0
        splashPlayer?.volume = splashVolume
        splashPlayer?.play()
    }

    private func preloadSplash() {
        let bundle = Bundle.main
        let url =
            bundle.url(forResource: "water pour 2", withExtension: "caf", subdirectory: "Sounds") ??
            bundle.url(forResource: "water pour 2", withExtension: "caf")
        guard let url else { return }
        splashPlayer = try? AVAudioPlayer(contentsOf: url)
        splashPlayer?.volume = splashVolume
        splashPlayer?.prepareToPlay()
    }
}
