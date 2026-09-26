import AVFoundation

/// Synthesised placeholder sounds (no asset files yet): a wooden tick per seed, a soft thump
/// for pick-up, a low drum for captures and a two-note figure for game over. Real recorded
/// atumpan/fontomfrom samples replace these buffers in Milestone 5 without changing callers.
@MainActor
final class SoundPlayer {
    static let shared = SoundPlayer()

    var enabled = true

    private let engine = AVAudioEngine()
    private let players: [AVAudioPlayerNode]
    private var nextPlayer = 0
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var buffers: [Sound: AVAudioPCMBuffer] = [:]
    private var started = false

    enum Sound: CaseIterable { case tick, pickUp, capture, win, lose }

    private init() {
        players = (0..<6).map { _ in AVAudioPlayerNode() }
        for p in players {
            engine.attach(p)
            engine.connect(p, to: engine.mainMixerNode, format: format)
        }
        buffers[.tick] = synth(duration: 0.045) { t, r in
            let env = exp(-t * 90)
            let noise = Double.random(in: -1...1, using: &r) * 0.5
            let tone = sin(2 * .pi * 1_900 * t) * 0.5
            return Float((noise + tone) * env * 0.55)
        }
        buffers[.pickUp] = synth(duration: 0.12) { t, _ in
            let env = exp(-t * 28)
            return Float(sin(2 * .pi * (140 - 60 * t) * t) * env * 0.35)
        }
        buffers[.capture] = synth(duration: 0.35) { t, _ in
            let env = exp(-t * 9)
            let f = 150 - 70 * min(t * 4, 1)
            return Float((sin(2 * .pi * f * t) + 0.3 * sin(2 * .pi * f * 2.01 * t)) * env * 0.6)
        }
        buffers[.win] = synth(duration: 0.9) { t, _ in
            let env = exp(-t * 3)
            let f = t < 0.3 ? 220.0 : (t < 0.6 ? 277.0 : 330.0)
            return Float(sin(2 * .pi * f * t) * env * 0.35)
        }
        buffers[.lose] = synth(duration: 0.9) { t, _ in
            let env = exp(-t * 3)
            let f = t < 0.45 ? 196.0 : 147.0
            return Float(sin(2 * .pi * f * t) * env * 0.35)
        }
    }

    private func synth(duration: Double, _ sample: (Double, inout SystemRandomNumberGenerator) -> Float) -> AVAudioPCMBuffer {
        let frames = AVAudioFrameCount(duration * format.sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        var rng = SystemRandomNumberGenerator()
        let data = buffer.floatChannelData![0]
        for i in 0..<Int(frames) {
            data[i] = sample(Double(i) / format.sampleRate, &rng)
        }
        return buffer
    }

    private func startIfNeeded() {
        guard !started else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            try engine.start()
            started = true
        } catch {
            enabled = false
        }
    }

    func play(_ sound: Sound, volume: Float = 1) {
        guard enabled, let buffer = buffers[sound] else { return }
        startIfNeeded()
        guard started else { return }
        let player = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        player.volume = volume
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        if !player.isPlaying { player.play() }
    }
}
