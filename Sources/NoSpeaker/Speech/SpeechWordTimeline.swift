import AVFoundation
import Foundation

struct TimedSpeechWord {
    let seconds: Double
    let range: NSRange
}

/// Apple's speech synthesizer supplies actual word boundaries and PCM
/// positions. Map its total PCM length to the existing say/LPC playback
/// duration; never alter the haptic speech synthesis itself.
final class SpeechWordTimeline: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    private let synth = AVSpeechSynthesizer()
    private let lock = NSLock()
    private var sampleCount = 0
    private var sampleRate = 0.0
    private var events: [TimedSpeechWord] = []
    private var finished = false

    override init() {
        super.init()
        synth.delegate = self
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        willSpeakRangeOfSpeechString range: NSRange,
        utterance: AVSpeechUtterance
    ) {
        lock.lock()
        let seconds = sampleRate > 0 ? Double(sampleCount) / sampleRate : 0
        events.append(TimedSpeechWord(seconds: seconds, range: range))
        lock.unlock()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didFinish utterance: AVSpeechUtterance) {
        finished = true
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didCancel utterance: AVSpeechUtterance) {
        finished = true
    }

    func build(text: String, voiceName: String?,
               playbackDuration: Double) -> [TimedSpeechWord] {
        guard !text.isEmpty, playbackDuration > 0 else { return [] }
        let utterance = AVSpeechUtterance(string: text)
        if let argument = sayVoiceArgument(for: voiceName),
           let voice = AVSpeechSynthesisVoice(identifier: argument) {
            utterance.voice = voice
        }
        synth.write(utterance) { [weak self] buffer in
            guard let self, let pcm = buffer as? AVAudioPCMBuffer else { return }
            self.lock.lock()
            self.sampleCount += Int(pcm.frameLength)
            self.sampleRate = pcm.format.sampleRate
            self.lock.unlock()
        }

        let deadline = Date().addingTimeInterval(12)
        while !finished && !interrupted() && Date() < deadline {
            _ = RunLoop.current.run(mode: .default,
                                    before: Date().addingTimeInterval(0.03))
        }
        if !finished { synth.stopSpeaking(at: .immediate) }
        lock.lock()
        let duration = sampleRate > 0 ?
            Double(sampleCount) / sampleRate : 0
        let captured = events
        lock.unlock()
        guard finished, duration > 0 else { return [] }
        let scale = playbackDuration / duration
        let textLength = (text as NSString).length
        return captured.filter {
            $0.range.location >= 0 && NSMaxRange($0.range) <= textLength
        }.map {
            TimedSpeechWord(seconds: min(playbackDuration, $0.seconds * scale),
                            range: $0.range)
        }
    }
}
