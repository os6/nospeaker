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
    let total = Double(frames.count) * hop
    caption(text, seconds: total)
    let start = mach_absolute_time()
    var t = 0.0
    while t < total && !interrupted() {
        let f = frames[min(frames.count - 1, Int(t / hop))]
        var step = 0.005
        if f.level > 0 {
            if f.voiced {
                step = 1 / f.f0
                playHapticTones(formantTones(f), ms: step * 1000, level: f.level)
                updateLiveState { $0.f0 = f.f0; $0.f1 = f.formants[0]; $0.f2 = f.formants[1] }
            } else {
                step = 0.004
                playHapticTones((0..<3).map { _ in (Double.random(in: 2700...4300), 1.0) }, ms: step * 1000, level: f.level * 0.7)
            }
        }
        t += step
        waitUntil(start + UInt64(t * ticksPerSecond))
    }
    updateLiveState { $0.f0 = 0; $0.f1 = 0; $0.f2 = 0 }
}

/// An original hook in the motor's loudest, cleanest octave, with scoops, glides and vibrato.
