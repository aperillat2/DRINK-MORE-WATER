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
        // Set the category before preparing the player so it never runs under the
        // default (soloAmbient) category, which pauses other apps' audio.
        configureCategory()
        preloadSplash()
    }

    /// `.ambient` mixes with other audio (Music, podcasts, audiobooks) by default.
    /// Don't pass `.mixWithOthers` here: it's only valid for playback/playAndRecord/multiRoute
    /// and makes `setCategory` throw for `.ambient`.
    private func configureCategory() {
        do {
            try session.setCategory(.ambient, mode: .default)
        } catch {
            print("Failed to set audio session category: \(error)")
        }
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
            if session.category != .ambient { configureCategory() }
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
