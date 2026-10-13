import AVFoundation

/// Reading the app's audio files.
enum AudioFiles {
    /// The file `name`.m4a in the app (Resources/Audio, made by art/make_audio.py), decoded whole (nil when it is missing or will not read).
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
