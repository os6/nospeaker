import Foundation
import Darwin

func playRhythm(bars: Int, rapBar: Int, rap: [SpeechFrame], rapText: String) {
    let bpm = 92.0
    let s16 = 15 / bpm, barLen = 16 * s16
    let kickP = Array("X.........X..x.."), snareP = Array("....X.......X..."), hatP = Array("x.x.x.x.x.x.xxx.")
    let bassHz = [110.0, 87.31, 130.81, 98.0]
    let bassRhythm = Array("x.....x...x.....")
    struct Hit { let t: Double; let kind: Int; let acc: Double }
    var hits: [Hit] = []
    for i in 0..<(bars * 16) {
        for (k, p) in [kickP, snareP, hatP].enumerated() where p[i % 16] != "." {
            hits.append(Hit(t: Double(i) * s16, kind: k, acc: p[i % 16] == "X" ? 1 : 0.65))
        }
    }
    hits.sort { $0.t < $1.t }
    updateLiveState { $0.bpm = bpm; $0.bars = bars }
    let rapStart = Double(rapBar) * barLen
    let end = Double(bars) * barLen
    var t = 0.0, next = 0, rapping = false
    var ringing: [Hit] = []
    let start = mach_absolute_time()
    while t < end && !stopRequested {
        if (skipRequested && !rapping) || jumpToCredits { break }
        while next < hits.count, hits[next].t <= t + 0.0005 {
            let h = hits[next]
            ringing.append(h)
            let when = now()
            updateLiveState { if h.kind == 0 { $0.kick = when } else if h.kind == 1 { $0.snare = when } else { $0.hat = when } }
            next += 1
        }
        ringing.removeAll { t - $0.t > 0.2 }
        let i16 = Int(t / s16)
        updateLiveState { $0.step = i16 % 16; $0.bar = i16 / 16 }
        if !rapping, t >= rapStart {
            rapping = true
            enter(.rap, 6, "RAP")
            caption(rapText, seconds: Double(rap.count) * hop)
        }
        var frame: SpeechFrame?
        if t >= rapStart { let idx = Int((t - rapStart) / hop); if idx < rap.count { frame = rap[idx] } }
        let talking = (frame?.level ?? 0) > 0
        let bass = bassHz[(i16 / 16) % bassHz.count]
        var carrier = bass
        if let f = frame, talking, f.voiced { carrier = f.f0 }
        var tones: [(hz: Double, amp: Double)] = []
        var step = 1 / carrier
        if let f = frame, talking {
            if f.voiced {
                for v in formantTones(f) { tones.append((v.hz, Double(f.level) * v.amp)) }
                updateLiveState { $0.f0 = f.f0; $0.f1 = f.formants[0]; $0.f2 = f.formants[1] }
            } else {
                step = 0.004
                for _ in 0..<2 { tones.append((Double.random(in: 2700...4300), Double(f.level) * 0.4)) }
            }
        } else {
            let pos = i16 % 16
            let lastHit = (0...pos).last { bassRhythm[$0] != "." } ?? 0
            let age = t - Double((i16 / 16) * 16 + lastHit) * s16
            let env = (age < 0.01 ? age / 0.01 : 1) * (0.25 + 0.75 * exp(-age * 7))
            for (target, w) in [(880.0, 0.6), (1320.0, 0.4)] {
                tones.append((max(1, (target / bass).rounded()) * bass, 0.45 * env * w))
            }
        }
        for h in ringing {
            let age = t - h.t
            let duck = talking ? [0.4, 0.25, 0.0][h.kind] : 1.0
            switch h.kind {
            case 0 where age < 0.14:
                tones.append((150 + 850 * exp(-age / 0.018), duck * 0.9 * h.acc * 1.3 * exp(-age / 0.05)))
            case 1 where age < 0.16:
                let e = duck * 0.9 * h.acc * exp(-age / 0.045)
                tones.append((Double.random(in: 1300...3800), e * 0.55))
                tones.append((Double.random(in: 1300...3800), e * 0.45))
            case 2 where age < 0.05 && duck > 0:
                tones.append((3951, 0.9 * h.acc * 0.55 * exp(-age / 0.012)))
            default: break
            }
        }
        if next < hits.count {
            let dt = hits[next].t - t
            if dt > 0.0035, dt < step { step = dt }
        }
        tones.sort { $0.amp > $1.amp }
        let use = Array(tones.prefix(6))
        let total = use.reduce(0) { $0 + $1.amp }
        if total > 0.01 { playHapticTones(use, ms: step * 1000, level: Float(min(1, total))) }
        t += step
        waitUntil(start + UInt64(t * ticksPerSecond))
    }
    updateLiveState { $0.step = -1; $0.f0 = 0; $0.f1 = 0; $0.f2 = 0 }
}

/// Touch to play: the trackpad as an instrument. Slide for pitch (snapped to the motor's cleanest notes, with a
/// glide), move up for more vibrato, press with more of your finger for louder.
