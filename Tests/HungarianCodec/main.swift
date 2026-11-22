import Foundation

let sampleRate = 16000.0
let hop = 0.010

struct SpeechFrame {
    var formants = [500.0, 1500.0, 2500.0]
    var amps = [1.0, 0.5, 0.25]
    var level: Float = 0
    var voiced = false
    var f0 = 110.0
    var frameIntervalSeconds = hop
    var hungarianTones: [(hz: Double, amp: Double)] = []
}

func verify(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

func sine(_ frequency: Double, amplitude: Double = 1,
          length: Int = 320) -> [Double] {
    (0..<length).map { index in
        amplitude * sin(2 * .pi * Double(index) * frequency / sampleRate)
    }
}

let mixed = zip(sine(500), sine(2400)).map { $0 + 0.6 * $1 }
let spectralPeaks = HungarianSpectrum.peaks(in: mixed)
let selected = HungarianSpectrum.tones(from: spectralPeaks, emphasizeUpperSpectrum: false)
verify(selected.count == 2, "voiced signal must retain two spectral peaks")
verify(abs(selected[0].hz - 500) <= 100, "low formant peak must be retained")
verify(abs(selected[1].hz - 2400) <= 100, "high formant peak must be retained")
verify(selected.allSatisfy { (300...3900).contains($0.hz) &&
                             $0.amp > 0 && $0.amp <= 1 },
       "vocoder respects frequency and relative amplitude limits")

// A non-grid-aligned formant must not be rounded to 100 Hz increments.
let offGrid = HungarianSpectrum.peaks(in: sine(575))
let finePeak = HungarianSpectrum.strongest(offGrid, within: 400...800)
verify(abs((finePeak?.frequencyHz ?? 0) - 575) < 20,
       "interpolated Hungarian formants should be within 20 Hz of a test tone")


let voiced = HungarianAudioFeatures.measure(samples: sine(200))
verify(abs((voiced.fundamentalHz ?? 0) - 200) < 10,
       "vocoder identifies source pitch")
let silent = [Float](repeating: 0, count: 800)
verify(HungarianVocoder.encode(silent).isEmpty, "no tone generation for silence")

let signal = (0..<6400).map { index -> Float in
    Float(0.3 * sin(2 * .pi * 200 * Double(index) / sampleRate) +
          0.2 * sin(2 * .pi * 2200 * Double(index) / sampleRate))
}
let frames = HungarianVocoder.encode(signal)
verify(frames.count >= 75, "5 ms analysis resolution")
verify(frames.allSatisfy { $0.frameIntervalSeconds == 0.005 },
       "Hungarian frame timing stays independent from English")
verify(frames.filter { $0.level > 0 }.allSatisfy {
    !$0.hungarianTones.isEmpty &&
    $0.hungarianTones.count <= 2 &&
    $0.hungarianTones.allSatisfy { (300...3900).contains($0.hz) }
}, "speech encodes into at most two motor-bound spectral tones per frame")
verify(frames.allSatisfy { $0.level >= 0 && $0.level <= 1 },
       "motor level never exceeds original normalized bounds")
verify(frames.allSatisfy { $0.f0 >= 80 && $0.f0 <= 250 },
       "Hungarian voice must not exceed the original motor repetition ceiling")
verify(HungarianAudioFeatures.measure(samples: sine(340)).fundamentalHz != nil,
       "higher-pitched Hungarian voice is analyzed before motor ceiling")


print("PASS: independent Hungarian spectral vocoder, pitch and 5-ms timing")
