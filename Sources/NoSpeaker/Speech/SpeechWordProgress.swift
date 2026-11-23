import Foundation

/// Machine-readable, newline-delimited protocol for the native Mac GUI.
/// Emitted at the *actual motor schedule*, not from a UI clock guess.
final class SpeechWordProgress {
    private let words: [TimedSpeechWord]
    private let duration: Double
    private var wordIndex = 0
    private var lastTick = -1

    init(words: [TimedSpeechWord], duration: Double) {
        self.words = words
        self.duration = duration
    }

    private func write(_ record: String) {
        FileHandle.standardOutput.write(Data(("NSP\t" + record + "\n").utf8))
    }

    func start() {
        write("START\t\(duration)")
        advance(to: 0)
    }

    func advance(to seconds: Double) {
        while wordIndex < words.count && words[wordIndex].seconds <= seconds {
            let word = words[wordIndex]
            write("WORD\t\(word.range.location)\t\(word.range.length)")
            wordIndex += 1
        }
        let tick = Int(seconds * 10)
        if tick != lastTick {
            lastTick = tick
            write("TIME\t\(min(seconds, duration))")
        }
    }

    func finish(stopped: Bool) {
        if !stopped { advance(to: duration) }
        write(stopped ? "STOPPED" : "END")
    }
}
