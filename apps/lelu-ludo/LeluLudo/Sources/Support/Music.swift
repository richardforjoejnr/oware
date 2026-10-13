import AVFoundation

/// The music: a slow harp-lute tune on the menu, gyil over bell and drum during a game, and quiet at
/// the end of a game so the win or lose sound is heard. Files in Resources/Audio (art/make_audio.py
/// makes stand-ins; recorded music of the same name replaces them).
enum MusicTrack: String, CaseIterable, Sendable {
    case menu = "music-menu"
    case game = "music-game"

    /// What should be playing now, or nil for quiet: never with Music off or the app off the screen,
    /// not over the opening card, and not over the game-over card.
    static func wanted(musicOn: Bool, onScreen: Bool, splash: Bool, inGame: Bool, gameOver: Bool) -> MusicTrack? {
        guard musicOn, onScreen, !splash else { return nil }
        if !inGame { return .menu }
        return gameOver ? nil : .game
    }
}

/// Loops a track, decoded whole and scheduled as a looping buffer so it joins without a gap, and
/// fades between tracks. Its own audio engine, separate from the sound effects': those pause when
/// play goes quiet, the music must not. Ambient like the effects, so the Silent switch silences it,
/// and it stays out of the way of the player's own music or podcast.
@MainActor
final class MusicPlayer {
    /// Under the sound effects: background, not foreground.
    static let volume: Float = 0.35
    private static let fade: Duration = .milliseconds(700)

    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var buffers: [MusicTrack: AVAudioPCMBuffer] = [:]
    private(set) var current: MusicTrack?
    private var change: Task<Void, Never>?

    init() {
        // A call, Siri or new headphones stop the engine: pick the tune up again afterwards.
        for name in [AVAudioSession.interruptionNotification, .AVAudioEngineConfigurationChange] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let ended = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init) != .began
                MainActor.assumeIsolated { if ended { self?.restart() } }
            }
        }
    }

    /// Fades to `track` (nil: fades out and lets the audio hardware go).
    func play(_ track: MusicTrack?) {
        guard track != current else { return }
        current = track
        change?.cancel()
        change = Task { [weak self] in
            await self?.fadeOut()
            guard let self, !Task.isCancelled else { return }
            guard let track else { self.stop(); return }
            await self.start(track)
        }
    }

    private func restart() {
        guard let track = current else { return }
        current = nil
        play(track)
    }

    private func start(_ track: MusicTrack) async {
        // Someone's own audio is playing (not mixable with ours): leave them to it.
        guard !AVAudioSession.sharedInstance().secondaryAudioShouldBeSilencedHint,
              let buffer = buffer(track), let (engine, player) = started(buffer.format) else { return }
        _ = engine
        player.stop()
        player.volume = 0
        player.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
        player.play()
        await ramp(player, to: Self.volume)
    }

    private func fadeOut() async {
        guard let player, player.isPlaying else { return }
        await ramp(player, to: 0)
        player.stop()
    }

    private func ramp(_ player: AVAudioPlayerNode, to target: Float) async {
        let steps = 14
        let from = player.volume
        for i in 1...steps {
            guard !Task.isCancelled else { return }
            player.volume = from + (target - from) * Float(i) / Float(steps)
            try? await Task.sleep(for: Self.fade / steps)
        }
    }

    private func stop() {
        player?.stop()
        engine?.stop()
    }

    private func buffer(_ track: MusicTrack) -> AVAudioPCMBuffer? {
        if let cached = buffers[track] { return cached }
        let decoded = AudioFiles.decode(track.rawValue)
        buffers[track] = decoded
        return decoded
    }

    private func started(_ format: AVAudioFormat) -> (AVAudioEngine, AVAudioPlayerNode)? {
        if let engine, let player, engine.isRunning { return (engine, player) }
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
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
}

/// Reading the app's audio files.
enum AudioFiles {
    /// The file `name`.m4a in the app, decoded whole (nil when it is missing or will not read).
    static func decode(_ name: String) -> AVAudioPCMBuffer? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "m4a"),
              let file = try? AVAudioFile(forReading: url),
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buffer)) != nil
        else { return nil }
        return buffer
    }

    /// Every take of a sound effect: `sfx-<name>-1`.m4a, `-2`, … (played in turn at random so a
    /// token's steps never repeat one click).
    static func takes(_ name: String) -> [AVAudioPCMBuffer] {
        var takes: [AVAudioPCMBuffer] = []
        while let next = decode("sfx-\(name)-\(takes.count + 1)") { takes.append(next) }
        return takes
    }
}
