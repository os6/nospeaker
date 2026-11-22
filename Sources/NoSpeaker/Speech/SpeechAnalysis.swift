import Foundation
import Darwin

func linearPredictionCoefficients(_ x: [Double], order p: Int) -> ([Double], Double) {
    var r = [Double](repeating: 0, count: p + 1)
    for k in 0...p { var s = 0.0; for i in k..<x.count { s += x[i] * x[i - k] }; r[k] = s }
    var a = [Double](repeating: 0, count: p + 1); a[0] = 1
    guard r[0] > 1e-12 else { return (a, 0) }
    r[0] *= 1.0001
    var e = r[0]
    for i in 1...p {
        var acc = r[i]
        for j in 1..<i { acc += a[j] * r[i - j] }
        let k = -acc / e
        var na = a
        for j in 1..<i { na[j] = a[j] + k * a[i - j] }
        na[i] = k
        a = na
        e *= 1 - k * k
    }
    return (a, e)
}

struct ComplexNumber {
    var realPart: Double, imaginaryPart: Double
    static func + (l: ComplexNumber, r: ComplexNumber) -> ComplexNumber { ComplexNumber(realPart: l.realPart + r.realPart, imaginaryPart: l.imaginaryPart + r.imaginaryPart) }
    static func - (l: ComplexNumber, r: ComplexNumber) -> ComplexNumber { ComplexNumber(realPart: l.realPart - r.realPart, imaginaryPart: l.imaginaryPart - r.imaginaryPart) }
    static func * (l: ComplexNumber, r: ComplexNumber) -> ComplexNumber { ComplexNumber(realPart: l.realPart * r.realPart - l.imaginaryPart * r.imaginaryPart, imaginaryPart: l.realPart * r.imaginaryPart + l.imaginaryPart * r.realPart) }
    static func / (l: ComplexNumber, r: ComplexNumber) -> ComplexNumber {
        let d = r.realPart * r.realPart + r.imaginaryPart * r.imaginaryPart
        return ComplexNumber(realPart: (l.realPart * r.realPart + l.imaginaryPart * r.imaginaryPart) / d, imaginaryPart: (l.imaginaryPart * r.realPart - l.realPart * r.imaginaryPart) / d)
    }
}

func polynomialRoots(_ a: [Double]) -> [ComplexNumber] {
    let p = a.count - 1
    var z = (0..<p).map { k -> ComplexNumber in
        let ang = 2 * Double.pi * Double(k) / Double(p) + 0.4
        return ComplexNumber(realPart: 0.9 * cos(ang), imaginaryPart: 0.9 * sin(ang))
    }
    func poly(_ x: ComplexNumber) -> ComplexNumber { var s = ComplexNumber(realPart: 1, imaginaryPart: 0); for k in 1...p { s = s * x + ComplexNumber(realPart: a[k], imaginaryPart: 0) }; return s }
    for _ in 0..<300 {
        var moved = 0.0
        for i in 0..<p {
            var d = ComplexNumber(realPart: 1, imaginaryPart: 0)
            for j in 0..<p where j != i { d = d * (z[i] - z[j]) }
            if d.realPart == 0 && d.imaginaryPart == 0 { d = ComplexNumber(realPart: 1e-12, imaginaryPart: 0) }
            let step = poly(z[i]) / d
            z[i] = z[i] - step
            moved = max(moved, abs(step.realPart) + abs(step.imaginaryPart))
        }
        if moved < 1e-10 { break }
    }
    return z
}

func analyzeSpeechSamples(_ x: [Float]) -> [SpeechFrame] {
    let win = Int(0.025 * sampleRate), hopN = Int(hop * sampleRate), order = 18
    // Preserve the original English pitch range; the Hungarian voice can be higher.
    let maximumPitchSearchHz = speechLanguage == .hungarian ? 450.0 : 300.0
    let maximumOutputPitchHz = speechLanguage == .hungarian ? 400.0 : 250.0
    let hamming = (0..<win).map { 0.54 - 0.46 * cos(2 * .pi * Double($0) / Double(win - 1)) }
    var frames: [SpeechFrame] = [], rmsList: [Double] = []
    var prev = SpeechFrame()
    var i = 0
    while i + win <= x.count {
        let seg = (0..<win).map { Double(x[i + $0]) }
        rmsList.append(sqrt(seg.reduce(0) { $0 + $1 * $1 } / Double(win)))
        var f = prev
        var zc = 0
        for k in 1..<win where (seg[k] >= 0) != (seg[k - 1] >= 0) { zc += 1 }
        var bestLag = 0, bestR = 0.0
        for lag in Int(sampleRate / maximumPitchSearchHz)...Int(sampleRate / 70) where lag < win - 40 {
            var s = 0.0, ea = 0.0, eb = 0.0
            for k in 0..<(win - lag) { s += seg[k] * seg[k + lag]; ea += seg[k] * seg[k]; eb += seg[k + lag] * seg[k + lag] }
            let r = s / max(sqrt(ea * eb), 1e-12)
            if r > bestR { bestR = r; bestLag = lag }
        }
        f.voiced = bestR > 0.35 && Double(zc) / Double(win) < 0.22
        if f.voiced, bestLag > 0 { f.f0 = sampleRate / Double(bestLag) }
        var pe = [Double](repeating: 0, count: win)
        for k in 0..<win { pe[k] = (seg[k] - 0.97 * (k > 0 ? seg[k - 1] : 0)) * hamming[k] }
        let (a, err) = linearPredictionCoefficients(pe, order: order)
        var cands: [Double] = []
        if err > 0 {
            for z in polynomialRoots(a) where z.imaginaryPart > 0 {
                let hz = atan2(z.imaginaryPart, z.realPart) * sampleRate / (2 * .pi)
                let bw = -log(max(1e-9, sqrt(z.realPart * z.realPart + z.imaginaryPart * z.imaginaryPart))) * sampleRate / .pi
                if hz > 150, hz < 4200, bw < 500 { cands.append(hz) }
            }
        }
        func pick(_ lo: Double, _ hi: Double, near: Double) -> Double? {
            cands.filter { $0 >= lo && $0 <= hi }.min { abs($0 - near) < abs($1 - near) }
        }
        if let f1 = pick(200, 1000, near: prev.formants[0]) { f.formants[0] = f1 }
        if let f2 = pick(max(f.formants[0] + 200, 650), 2700, near: prev.formants[1]) { f.formants[1] = f2 }
        if let f3 = pick(max(f.formants[1] + 300, 1700), 3900, near: prev.formants[2]) { f.formants[2] = f3 }
        if err > 0 {
            f.amps = f.formants.map { hz in
                let w = 2 * Double.pi * hz / sampleRate
                var re = 0.0, im = 0.0
                for k in 0...order { re += a[k] * cos(w * Double(k)); im -= a[k] * sin(w * Double(k)) }
                return 1 / max(sqrt(re * re + im * im), 1e-6)
            }
        }
        frames.append(f)
        prev = f
        i += hopN
    }
    let peak = rmsList.max() ?? 1
    for k in frames.indices {
        let rel = rmsList[k] / max(peak, 1e-9)
        frames[k].level = rel < 0.02 ? 0 : Float(min(1, pow(rel, 0.45)))
        if frames[k].level == 0 { frames[k].voiced = false }
    }
    func median(_ v: [Double]) -> Double { v.sorted()[v.count / 2] }
    let raw = frames
    for k in frames.indices {
        let lo = max(0, k - 2), hi = min(frames.count - 1, k + 2)
        for j in 0..<3 { frames[k].formants[j] = median((lo...hi).map { raw[$0].formants[j] }) }
        frames[k].f0 = min(maximumOutputPitchHz, max(70, median((lo...hi).map { raw[$0].f0 })))
    }
    return frames
}

/// A voiced frame as two tones, F1 and F2. Two rather than three: in a blind test two were clearer, and louder,
/// because the motor's strength is split fewer ways.
func formantTones(_ f: SpeechFrame) -> [(hz: Double, amp: Double)] {
    let w = [f.amps[0], f.amps[1] * 1.8]
    let sum = max(w[0] + w[1], 1e-9)
    return [(f.formants[0], w[0] / sum), (f.formants[1], w[1] / sum)]
}
