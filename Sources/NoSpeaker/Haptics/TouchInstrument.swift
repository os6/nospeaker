import Foundation
import Darwin

func playTouchInstrument() {
    guard startTouch() else { updateLiveState { $0.touchMissed = true }; pause(1.5); return }
    defer { stopTouch() }
    updateLiveState { $0.touchWaitUntil = now() + 8 }
    let waitEnd = now() + 8
    while now() < waitEnd && !interrupted() && !contact.down { usleep(5000) }
    guard contact.down else { updateLiveState { $0.touchMissed = true }; pause(1.5); return }
    let endAt = now() + 12
    updateLiveState { $0.touchSeen = true; $0.touchEnds = endAt }
    let scale = ["G5", "A5", "B5", "C6", "E6", "F6", "G6", "A6", "B6", "C7"].map(frequencyForNote)
    var current = scale[4]
    var lastDown = false, downAt = 0.0
    while now() < endAt && !interrupted() {
        let c = contact
        updateLiveState { $0.touchDown = c.down; if c.down { $0.touchX = Double(c.x); $0.touchY = Double(c.y) } }
        guard c.down else { lastDown = false; usleep(3000); continue }
        if !lastDown { downAt = now() }
        lastDown = true
        let idx = min(scale.count - 1, max(0, Int((Double(c.x) * Double(scale.count)).rounded(.down))))
        let target = scale[idx]
        current *= pow(target / current, 0.3)
        let age = now() - downAt
        let depth = 0.05 + 0.45 * Double(max(0, min(1, c.y)))
        let f = current * pow(2, depth * sin(2 * .pi * 6 * age) / 12)
        let level = min(1, max(0.5, 0.3 + Double(c.size) * 0.8))
        let seg = max(1, (0.02 * f).rounded()) / f
        let t0 = mach_absolute_time()
        playHapticTones([(f, 1)], ms: seg * 1000, level: Float(level))
        updateLiveState { $0.noteName = noteName(f) }
        waitUntil(t0 + UInt64(seg * ticksPerSecond))
    }
    updateLiveState { $0.touchDown = false }
}

func noteName(_ f: Double) -> String {
    let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    let midi = Int((69 + 12 * log2(f / 440)).rounded())
    return names[(midi % 12 + 12) % 12] + String(midi / 12 - 1)
}

/// A sparkle to close: an arpeggio up, then the motor's purest note.
func playOutroNotes() {
    for n in ["A5", "C6", "E6", "A6", "C7"] where !stopRequested {
        let f = frequencyForNote(n)
        let seg = (0.07 * f).rounded() / f
        playHapticTones([(f, 1)], ms: seg * 1000, level: 0.9)
        let end = mach_absolute_time() + UInt64(seg * ticksPerSecond)
        waitUntil(end)
    }
    let start = mach_absolute_time()
    var t = 0.0
    while t < 0.6 && !stopRequested {
        let seg = (0.02 * 3951).rounded() / 3951
        playHapticTones([(3951, 1)], ms: seg * 1000, level: Float(exp(-t / 0.18)))
        t += seg
        waitUntil(start + UInt64(t * ticksPerSecond))
    }
}

/// Lines to try in Say anything, shown one at a time in the empty box. Tab types the one showing.
