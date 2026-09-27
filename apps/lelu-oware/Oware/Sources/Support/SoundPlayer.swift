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
    private var buffers: [Sound: [AVAudioPCMBuffer]] = [:]
    private var started = false
    /// Stops the engine a few seconds after the last sound; a running engine keeps the audio
    /// hardware awake even when silent.
    private var idleTask: Task<Void, Never>?

    /// `tick`: a seed landing on bare wood. `clack`: a seed landing on other seeds. `pickUp`: a
    /// handful scooped out. `capture`: seeds tipped into the trough. `win` / `lose`: two notes.
    enum Sound: CaseIterable { case tick, clack, pickUp, capture, win, lose }

    private init() {
        players = (0..<6).map { _ in AVAudioPlayerNode() }
        // A phone call, Siri, or a route change (headphones) stops the engine; start it again on the
        // next sound rather than staying silent for the rest of the session.
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.started = false }
        }
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.started = false }
        }
        for p in players {
            engine.attach(p)
            engine.connect(p, to: engine.mainMixerNode, format: format)
        }
        // Four detuned takes of each sound so a sowing never repeats the exact same click.
        let detunes: [Double] = [0.94, 0.98, 1.03, 1.08]
        buffers[.tick] = detunes.map { d in
            synth(duration: 0.22) { t, r in
                // Impact: a 3 ms burst of noise, then the hollow ringing: a few wood modes decaying
                // at different rates, plus a fast, quiet high tap.
                let impact = Double.random(in: -1...1, using: &r) * exp(-t * 700) * 0.9
                let body = Self.mode(520 * d, t, decay: 34) * 0.55
                         + Self.mode(790 * d, t, decay: 46) * 0.32
                         + Self.mode(1_240 * d, t, decay: 70) * 0.22
                         + Self.mode(2_650 * d, t, decay: 150) * 0.16
                return Float((impact + body) * 0.6)   // peaks just under full scale
            }
        }
        buffers[.clack] = detunes.map { d in
            synth(duration: 0.14) { t, r in
                // Stone on stone: brighter and shorter, with a touch of the wood underneath.
                let impact = Double.random(in: -1...1, using: &r) * exp(-t * 1_100) * 0.8
                let stone = Self.mode(3_100 * d, t, decay: 120) * 0.35
                          + Self.mode(4_700 * d, t, decay: 170) * 0.22
                          + Self.mode(6_300 * d, t, decay: 240) * 0.12
                let wood = Self.mode(560 * d, t, decay: 40) * 0.25
                return Float((impact + stone + wood) * 0.65)
            }
        }
        buffers[.pickUp] = detunes.map { d in
            synth(duration: 0.26) { t, r in
                // A handful gathered: three quick soft stone clicks over a low wooden rub.
                var v = 0.0
                for (k, at) in [0.0, 0.05, 0.11].enumerated() where t >= at {
                    let u = t - at
                    let f = (2_400 + 500 * Double(k)) * d
                    v += (Double.random(in: -1...1, using: &r) * exp(-u * 900) * 0.35 + Self.mode(f, u, decay: 130) * 0.18) * (1 - 0.2 * Double(k))
                }
                let rub = Double.random(in: -1...1, using: &r) * exp(-t * 12) * 0.06
                return Float((v + rub + Self.mode(300 * d, t, decay: 30) * 0.12) * 0.7)
            }
        }
        buffers[.capture] = detunes.map { d in
            synth(duration: 0.5) { t, r in
                // Seeds tipped into the trough: a deeper hollow thud and a scatter of clacks.
                let thud = Self.mode(210 * d, t, decay: 14) * 0.55 + Self.mode(340 * d, t, decay: 20) * 0.3
                var scatter = 0.0
                for (k, at) in [0.02, 0.07, 0.11, 0.16, 0.22].enumerated() where t >= at {
                    let u = t - at
                    scatter += (Double.random(in: -1...1, using: &r) * exp(-u * 900) * 0.3 + Self.mode((2_900 + 300 * Double(k)) * d, u, decay: 140) * 0.14) * (1 - 0.12 * Double(k))
                }
                let impact = Double.random(in: -1...1, using: &r) * exp(-t * 500) * 0.6
                return Float((thud + scatter + impact) * 0.7)
            }
        }
        buffers[.win] = [synth(duration: 0.9) { t, _ in
            let env = exp(-t * 3)
            let f = t < 0.3 ? 220.0 : (t < 0.6 ? 277.0 : 330.0)
            return Float(Self.mode(f, t, decay: 0) * env * 0.35)
        }]
        buffers[.lose] = [synth(duration: 0.9) { t, _ in
            let env = exp(-t * 3)
            let f = t < 0.45 ? 196.0 : 147.0
            return Float(Self.mode(f, t, decay: 0) * env * 0.35)
        }]
    }

    /// One decaying resonance.
    private static func mode(_ frequency: Double, _ t: Double, decay: Double) -> Double {
        sin(2 * .pi * frequency * t) * exp(-t * decay)
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

    /// `.ambient` follows the phone's Silent switch and mixes with the player's own music — right
    /// for a board game whose sounds are texture, not information.
    private func startIfNeeded() {
        guard !started || !engine.isRunning else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            try engine.start()
            started = true
        } catch {
            // Try again on the next sound instead of switching audio off for good.
            started = false
        }
    }

    func play(_ sound: Sound, volume: Float = 1) {
        guard enabled, let takes = buffers[sound], let buffer = takes.randomElement() else { return }
        startIfNeeded()
        guard started, engine.isRunning else { return }
        let player = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        player.volume = volume
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        if !player.isPlaying { player.play() }
        idleTask?.cancel()
        idleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard let self, !Task.isCancelled else { return }
            self.engine.pause()
            self.started = false
        }
    }
}
