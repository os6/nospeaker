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
}

func verify(_ value: @autoclosure () -> Bool, _ message: String) {
    guard value() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let source = (0..<6400).map { index -> Float in
    Float(0.3 * sin(2 * .pi * 200 * Double(index) / sampleRate) +
          0.2 * sin(2 * .pi * 2200 * Double(index) / sampleRate))
}
let frames = analyzeSpeechSamples(source)
verify(frames.count >= 35, "10-ms LPC analysis retains all voiced frames")
verify(frames.allSatisfy { $0.frameIntervalSeconds == 0.010 },
       "both languages share the same 10-ms speech timebase")
verify(frames.allSatisfy { $0.level >= 0 && $0.level <= 1 &&
    $0.f0 >= SpeechActuationLimits.minimumPulseRateHz &&
    $0.f0 <= SpeechActuationLimits.maximumPulseRateHz },
    "shared 70–250 Hz speech repetition limits must hold")
verify(frames.filter { $0.voiced && $0.level > 0 }.allSatisfy {
    formantTones($0).count == 2
}, "two LPC formants per voiced actuation")

let defaultVoicedTones = formantTones(frames.first(where: { $0.voiced })!)
let explicitDefault = formantTones(
    frames.first(where: { $0.voiced })!, secondFormantGain: 1.8
)
let reducedUpperTone = formantTones(
    frames.first(where: { $0.voiced })!, secondFormantGain: 1.3
)
verify(defaultVoicedTones[1].amp == explicitDefault[1].amp,
       "English default formant balance must be unchanged")
verify(reducedUpperTone[1].amp < defaultVoicedTones[1].amp,
       "Hungarian formant balance must reduce only the high tone")

// Less compression must suppress quiet frames while preserving the
// original English exponent and all measured LPC frequency information.
let varyingSource = (0..<6400).map { index -> Float in
    let amplitude = index < 3200 ? 0.08 : 0.4
    return Float(amplitude * sin(2 * .pi * 200 * Double(index) / sampleRate))
}
let defaultEnvelope = analyzeSpeechSamples(varyingSource)
let explicitEnglishEnvelope = analyzeSpeechSamples(
    varyingSource, envelopeExponent: 0.45
)
let lessCompressedHungarianEnvelope = analyzeSpeechSamples(
    varyingSource, envelopeExponent: 0.58
)
verify(defaultEnvelope.count == lessCompressedHungarianEnvelope.count,
       "less compression must not change frame count or speech timing")
verify(zip(defaultEnvelope, explicitEnglishEnvelope).allSatisfy {
    $0.level == $1.level && $0.f0 == $1.f0
}, "English must retain the exact original envelope")
verify(zip(defaultEnvelope, lessCompressedHungarianEnvelope).allSatisfy {
    $1.level <= $0.level && $1.voiced == $0.voiced &&
        $1.formants == $0.formants && $1.f0 == $0.f0
}, "Hungarian compression adjustment must only lower quiet-frame levels")
verify(zip(defaultEnvelope, lessCompressedHungarianEnvelope).contains {
    $1.level > 0 && $1.level < $0.level
}, "Hungarian quiet speech must actually be less amplified")

let silence = [Float](repeating: 0, count: 800)
let quiet = analyzeSpeechSamples(silence)
verify(quiet.allSatisfy { $0.level == 0 },
       "silence must not generate active speech")
print("PASS: one LPC model for both languages, bounded pulse rate and silence")
