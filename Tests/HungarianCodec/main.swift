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



// Detect a spurious high frequency that occurs for one 5 ms frame.
func vowelFrame(_ upperHz: Double) -> SpeechFrame {
    var frame = SpeechFrame()
    frame.voiced = true
    frame.level = 0.6
    frame.hungarianTones = [(hz: 650, amp: 1), (hz: upperHz, amp: 0.8)]
    return frame
}

var ringingFrames = [vowelFrame(2200), vowelFrame(2270),
                     vowelFrame(3800), vowelFrame(2210), vowelFrame(2200)]
HungarianToneStabilizer.stabilize(&ringingFrames)
verify(abs(ringingFrames[2].hungarianTones[1].hz - 2240) < 90,
       "isolated upper spectral jumps must reconnect to their voiced neighbours")
verify(ringingFrames[2].hungarianTones[1].amp <= 0.56,
       "reconnected upper partial must retain conservative relative energy")
var coherentFrames = [vowelFrame(2200), vowelFrame(2270), vowelFrame(2210)]
HungarianToneStabilizer.stabilize(&coherentFrames)
verify(coherentFrames[1].hungarianTones[1].hz < 2270,
       "coherent upper spectral peaks should be temporally smoothed")

var genuineOnset = [vowelFrame(2200), vowelFrame(3650), vowelFrame(3000)]
HungarianToneStabilizer.stabilize(&genuineOnset)
verify(genuineOnset[1].hungarianTones[1].hz == 3650,
       "do not invent a missing partial when neighbouring upper tones disagree")

var halfTrackedFrames = [vowelFrame(2200), vowelFrame(2270), vowelFrame(3500)]
let unfilteredHalfTrackedLevel = halfTrackedFrames[1].level
HungarianToneStabilizer.stabilize(&halfTrackedFrames)
verify(halfTrackedFrames[1].level < unfilteredHalfTrackedLevel,
       "one-sided high-frequency jumps must lower absolute output level")
verify(halfTrackedFrames[1].hungarianTones[0].hz == 650,
       "low-frequency vowel component must retain its original frequency")

verify(ringingFrames.allSatisfy { $0.hungarianTones.allSatisfy {
    $0.amp <= 1 && (300...3900).contains($0.hz)
}}, "ringing suppression must not raise motor amplitude or frequencies")

var singleToneFrames = [vowelFrame(2200), vowelFrame(2300), vowelFrame(2200)]
singleToneFrames[1].hungarianTones = [(hz: 3800, amp: 1)]
HungarianToneStabilizer.stabilize(&singleToneFrames)
verify(singleToneFrames[1].level < 0.6,
       "single high-frequency whistles must reduce level, not only normalized weight")


var releaseFrames = [vowelFrame(2200), SpeechFrame(), vowelFrame(3700)]
releaseFrames[1].level = 0.4
releaseFrames[1].voiced = false
releaseFrames[1].hungarianTones = [(hz: 3700, amp: 1)]
HungarianToneStabilizer.stabilize(&releaseFrames)
verify(releaseFrames[1].hungarianTones[0].amp == 1,
       "unvoiced consonant release must be preserved")

func fricativeFrame(_ hz: Double) -> SpeechFrame {
    var frame = SpeechFrame()
    frame.voiced = false
    frame.level = 0.6
    frame.hungarianTones = [(hz: 1800, amp: 0.5), (hz: hz, amp: 1.0)]
    return frame
}
var sustainedFricative = [fricativeFrame(3000), fricativeFrame(3750),
                          fricativeFrame(3100)]
HungarianToneStabilizer.stabilize(&sustainedFricative)
verify(sustainedFricative[1].level < 0.45,
       "erratic high-frequency fricative peaks must be attenuated")
verify(sustainedFricative[0].level == 0.6 &&
       sustainedFricative[2].level == 0.6,
       "protect fricative attack and release boundaries")
verify(sustainedFricative[1].hungarianTones[1].hz == 3750,
       "do not blur consonant peak frequency with vowel tracking")

var stableFricative = [fricativeFrame(3100), fricativeFrame(3150),
                       fricativeFrame(3200)]
HungarianToneStabilizer.stabilize(&stableFricative)
verify(stableFricative[1].level > sustainedFricative[1].level,
       "stable fricative must retain more energy than erratic high-frequency peak")


print("PASS: independent Hungarian spectral vocoder, pitch and 5-ms timing")
