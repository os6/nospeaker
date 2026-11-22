import Foundation
import Darwin

let rollNotes = ["C7", "A6", "G6", "E6", "C6", "A5"]
func playMelody() {
    let beat = 60.0 / 112
    let melody: [(String, Double)] = [("E6", 0.5), ("G6", 0.5), ("A6", 1), ("G6", 0.5), ("E6", 0.5), ("C6", 1),
                                      ("E6", 0.5), ("G6", 0.5), ("A6", 0.5), ("C7", 0.5), ("A6", 1), ("G6", 1),
                                      ("E6", 0.5), ("C6", 0.5), ("A5", 1), ("C6", 0.5), ("E6", 0.5), ("A6", 2.5)]
    let phraseEnds: Set<Int> = [5, 11, 17]
    var previous: Double?
    let start = mach_absolute_time()
    var t = 0.0, at = 0.0
    for (i, (name, beats)) in melody.enumerated() {
        if interrupted() { break }
        let target = frequencyForNote(name), length = beats * beat
        let sounding = phraseEnds.contains(i) ? length * 0.86 : length
        updateLiveState { $0.noteRow = rollNotes.firstIndex(of: name) ?? -1; $0.noteName = name }
        let from = previous
        while t < at + sounding && !interrupted() {
            let age = t - at
            var f = target
            if let from, age < 0.045 { f = from * pow(target / from, age / 0.045) }
            else if from == nil, age < 0.04 { f = target * pow(2, -0.6 * (1 - age / 0.04) / 12) }
            if age > 0.2 { f *= pow(2, min(1, (age - 0.2) / 0.25) * 0.22 * sin(2 * .pi * 5.8 * age) / 12) }
            var level = age < 0.015 ? 0.6 + 0.4 * age / 0.015 : 1.0
            if i == melody.count - 1 { level *= max(0, 1 - age / length) }
            let seg = max(1, ((age < 0.06 ? 0.02 : 0.045) * f).rounded()) / f
            playHapticTones([(f, 1)], ms: min(seg, at + sounding - t + 0.004) * 1000, level: Float(level))
            t += seg
            waitUntil(start + UInt64(t * ticksPerSecond))
        }
        previous = phraseEnds.contains(i) ? nil : target
        updateLiveState { $0.noteRow = -1 }
        at += length
        if t < at { t = at; waitUntil(start + UInt64(t * ticksPerSecond)) }
    }
}

/// Drums, bass and (from `rapBar`) a rapped line, mixed into each actuation. Everything restarts on one
/// carrier period: the bass note, or the voice's own pitch while it raps, so the ear hears that as the low
/// note. While the voice talks, the bass drops out and the drums duck.
