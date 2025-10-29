import Foundation
import AVFoundation

/// Lightweight shared audio helper for the splash effect.
final class SoundFX: NSObject {
    static let shared = SoundFX()

    private var splashPlayer: AVAudioPlayer?
    private let splashVolume: Float = 0.08
    private let session = AVAudioSession.sharedInstance()
    private var sessionActivated = false
    private var deactivateWorkItem: DispatchWorkItem?

    private override init() {
        super.init()
        preloadSplash()
    }

    func playSplash() {
        if splashPlayer == nil { preloadSplash() }
        activateSessionIfNeeded()
        guard let player = splashPlayer else { return }

        player.stop()
        player.currentTime = 0
        player.volume = splashVolume
        player.play()

        scheduleSessionDeactivation()
    }

    private func preloadSplash() {
        let bundle = Bundle.main
        let url =
            bundle.url(forResource: "water pour 2", withExtension: "caf", subdirectory: "Sounds") ??
            bundle.url(forResource: "water pour 2", withExtension: "caf")
        guard let url else { return }
        splashPlayer = try? AVAudioPlayer(contentsOf: url)
        splashPlayer?.delegate = self
        splashPlayer?.volume = splashVolume
        splashPlayer?.prepareToPlay()
    }

    private func activateSessionIfNeeded() {
        deactivateWorkItem?.cancel()
        guard !sessionActivated else { return }
        do {
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setActive(true, options: [])
            sessionActivated = true
        } catch {
            print("Failed to activate audio session: \(error)")
        }
    }

    private func scheduleSessionDeactivation() {
        deactivateWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.sessionActivated else { return }
            do {
                try self.session.setActive(false, options: [.notifyOthersOnDeactivation])
            } catch {
                print("Failed to deactivate audio session: \(error)")
            }
            self.sessionActivated = false
        }
        deactivateWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: workItem)
    }
}

extension SoundFX: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        scheduleSessionDeactivation()
    }
}
