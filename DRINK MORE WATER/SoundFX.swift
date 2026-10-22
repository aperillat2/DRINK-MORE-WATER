import Foundation
import AVFoundation

/// Lightweight shared audio helper for the splash effect.
///
/// Activating/deactivating `AVAudioSession` can block, so all audio work runs on a private
/// serial queue instead of the main thread (where it could stall taps and animation).
/// Every mutable property below is only touched on `audioQueue`.
nonisolated final class SoundFX: NSObject, @unchecked Sendable {
    static let shared = SoundFX()

    private let audioQueue = DispatchQueue(label: "SoundFX.audio", qos: .userInitiated)
    private var splashPlayer: AVAudioPlayer?
    private let splashVolume: Float = 0.08
    private let session = AVAudioSession.sharedInstance()
    private var sessionActivated = false
    private var deactivateWorkItem: DispatchWorkItem?

    private override init() {
        super.init()
        audioQueue.async { [self] in
            // Set the category before preparing the player so it never runs under the
            // default (soloAmbient) category, which pauses other apps' audio.
            configureCategory()
            preloadSplash()
        }
    }

    /// Safe to call from the main thread; returns immediately.
    func playSplash() {
        audioQueue.async { [self] in
            if splashPlayer == nil { preloadSplash() }
            activateSessionIfNeeded()
            guard let player = splashPlayer else { return }

            player.stop()
            player.currentTime = 0
            player.volume = splashVolume
            player.play()

            scheduleSessionDeactivation()
        }
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
        audioQueue.asyncAfter(deadline: .now() + 2.0, execute: workItem)
    }
}

extension SoundFX: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        // The delegate can be called on any thread; hop back to the audio queue.
        audioQueue.async { [self] in
            scheduleSessionDeactivation()
        }
    }
}
