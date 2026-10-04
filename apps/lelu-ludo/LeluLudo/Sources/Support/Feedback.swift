import AVFoundation
import UIKit

/// What a moment of play sounds and feels like.
enum Feedback: Equatable, Sendable {
    case roll, step, kick, home, threeSixes, win
}

/// Plays feedback. The session only says *what* happened; tests record it instead of playing it.
@MainActor
protocol FeedbackPlayer: AnyObject {
    func play(_ feedback: Feedback)
}

/// For tests: remembers every feedback in order.
final class RecordingFeedback: FeedbackPlayer {
    private(set) var played: [Feedback] = []
    func play(_ feedback: Feedback) { played.append(feedback) }
}

/// The device: a wooden tap per square, a knock for a kick, a rising pair of notes home, a rattle for
/// the die, with matching haptics. Sound follows the Silent switch (ambient). The audio engine is
/// built on the first sound only, so drawing the board never waits for the audio server (the
/// lesson of Lelu Oware's launch crash).
final class DeviceFeedback: FeedbackPlayer {
    private let settings: AppSettings
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private lazy var buffers: [Feedback: AVAudioPCMBuffer] = [
        .step: tone([(700, 34)], duration: 0.12, noise: 0.5),
        .roll: tone([(900, 60), (1_300, 80)], duration: 0.18, noise: 0.9),
        .kick: tone([(180, 12), (260, 18)], duration: 0.35, noise: 0.6),
        .home: tone([(523, 5), (659, 5)], duration: 0.45, noise: 0),
        .threeSixes: tone([(220, 6)], duration: 0.4, noise: 0),
        .win: tone([(523, 4), (659, 4), (784, 4)], duration: 0.8, noise: 0),
    ]

    init(settings: AppSettings) { self.settings = settings }

    func play(_ feedback: Feedback) {
        if settings.effectiveHaptics { haptic(feedback) }
        guard settings.effectiveSound, let buffer = buffers[feedback], let (engine, player) = started() else { return }
        _ = engine
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        if !player.isPlaying { player.play() }
    }

    private func haptic(_ f: Feedback) {
        switch f {
        case .step, .roll: UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.5)
        case .kick: UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        case .home, .win: UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .threeSixes: UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
    }

    private func started() -> (AVAudioEngine, AVAudioPlayerNode)? {
        if let engine, let player, engine.isRunning { return (engine, player) }
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            let engine = self.engine ?? AVAudioEngine()
            let player = self.player ?? AVAudioPlayerNode()
            if self.engine == nil {
                engine.attach(player)
                engine.connect(player, to: engine.mainMixerNode, format: format)
            }
            try engine.start()
            self.engine = engine
            self.player = player
            return (engine, player)
        } catch {
            return nil
        }
    }

    /// A few decaying partials (frequency, decay) plus a burst of noise at the start: wood, roughly.
    private func tone(_ partials: [(Double, Double)], duration: Double, noise: Double) -> AVAudioPCMBuffer {
        let frames = AVAudioFrameCount(duration * format.sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let data = buffer.floatChannelData![0]
        var rng = SystemRandomNumberGenerator()
        for i in 0..<Int(frames) {
            let t = Double(i) / format.sampleRate
            var v = Double.random(in: -1...1, using: &rng) * exp(-t * 600) * noise
            for (k, (f, decay)) in partials.enumerated() {
                let start = Double(k) * duration / Double(max(partials.count, 1)) * (decay < 10 ? 1 : 0)
                if t >= start { v += sin(2 * .pi * f * (t - start)) * exp(-(t - start) * decay) * 0.4 }
            }
            data[i] = Float(v * 0.5)
        }
        return buffer
    }
}
