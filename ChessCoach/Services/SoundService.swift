import AVFoundation
import UIKit

/// Manages sound effects and haptic feedback for the app.
@MainActor
final class SoundService {
    static let shared = SoundService()

    enum Sound: String {
        case move = "move"
        case capture = "capture"
        case check = "check"
        case correct = "correct"
        case wrong = "wrong"
        case phaseUp = "phase_up"
    }

    private var players: [Sound: AVAudioPlayer] = [:]

    private var soundEnabled: Bool {
        UserDefaults.standard.object(forKey: "sound_enabled") as? Bool ?? true
    }

    private var hapticsEnabled: Bool {
        UserDefaults.standard.object(forKey: "haptics_enabled") as? Bool ?? true
    }

    private init() {
        prepareAudio()
    }

    private func prepareAudio() {
        // Configure audio session for mixing with other audio
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: .mixWithOthers)
        try? AVAudioSession.sharedInstance().setActive(true)

        // Pre-load sound files (if they exist in bundle)
        for sound in [Sound.move, .capture, .check, .correct, .wrong, .phaseUp] {
            if let url = Bundle.main.url(forResource: sound.rawValue, withExtension: "mp3") ??
               Bundle.main.url(forResource: sound.rawValue, withExtension: "wav") ??
               Bundle.main.url(forResource: sound.rawValue, withExtension: "caf") {
                if let player = try? AVAudioPlayer(contentsOf: url) {
                    player.prepareToPlay()
                    player.volume = 0.5
                    players[sound] = player
                }
            }
        }
    }

    // MARK: - Sound Effects (Improvement 10)

    func play(_ sound: Sound) {
        guard soundEnabled else { return }
        if let player = players[sound] {
            player.currentTime = 0
            player.play()
        } else {
            // Fallback: use system sound for basic feedback
            switch sound {
            case .move: AudioServicesPlaySystemSound(1104)      // Tock
            case .capture: AudioServicesPlaySystemSound(1105)    // Tink
            case .check: AudioServicesPlaySystemSound(1057)      // Alert
            case .correct: AudioServicesPlaySystemSound(1025)    // Positive
            case .wrong: AudioServicesPlaySystemSound(1073)      // Negative
            case .phaseUp: AudioServicesPlaySystemSound(1335)    // Fanfare
            }
        }
    }

    // MARK: - Haptic Feedback (Improvement 11)

    func hapticPiecePlaced() {
        guard hapticsEnabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func hapticCorrectMove() {
        guard hapticsEnabled else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    func hapticDeviation() {
        guard hapticsEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    func hapticLineComplete() {
        guard hapticsEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    func hapticPhaseUp() {
        guard hapticsEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
