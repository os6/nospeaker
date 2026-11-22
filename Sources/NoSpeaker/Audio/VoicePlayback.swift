import Foundation
import Darwin

// MARK: - The show's parts (sound)

/// A felt-and-heard thump: a fast pitch dive.
func playThump(_ amp: Double) {
    let start = mach_absolute_time()
    var t = 0.0
    while t < 0.11 && !stopRequested {
        let f = 120 + 780 * exp(-t / 0.02)
        let seg = 1 / f
        playHapticTones([(f, 1)], ms: seg * 1000, level: Float(amp * exp(-t / 0.05)))
        t += seg
        waitUntil(start + UInt64(t * ticksPerSecond))
    }
}

func playHeartbeat() {
    for _ in 0..<2 where !interrupted() {
        playThump(1); pause(0.17); playThump(0.7); pause(0.75)
    }
}

func playFrequencySweep(seconds: Double = 6) {
    let start = mach_absolute_time()
    var t = 0.0
    while t < seconds && !interrupted() {
        let f = 100 * pow(40, t / seconds)
        let seg = max(1, (0.02 * f).rounded()) / f
        playHapticTones([(f, 1)], ms: seg * 1000, level: 1)
        t += seg
        waitUntil(start + UInt64(t * ticksPerSecond))
    }
}

func playSpeech(_ frames: [SpeechFrame], text: String) {
    guard !frames.isEmpty else { return }
    caption(text, seconds: Double(frames.count) * hop)
    let playbackStart = mach_absolute_time()
    enumerateSpeechActuations(frames, realtime: true) { startSeconds, actuation in
        playHapticTones(actuation.tones, ms: actuation.durationSeconds * 1000,
                        level: actuation.level)
        if actuation.isVoiced {
            updateLiveState {
                $0.f0 = actuation.pitchHz
                $0.f1 = actuation.firstFormantHz
                $0.f2 = actuation.secondFormantHz
            }
        }
    } waitForTime: { elapsedSeconds in
        waitUntil(playbackStart + UInt64(elapsedSeconds * ticksPerSecond))
    }
    updateLiveState { $0.f0 = 0; $0.f1 = 0; $0.f2 = 0 }
}

/// An original hook in the motor's loudest, cleanest octave, with scoops, glides and vibrato.
