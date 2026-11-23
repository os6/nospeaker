import Foundation

let sampleRate = 16000.0
let hop = 0.010

struct SpeechFrame {
    var formants = [500.0, 1500.0, 2500.0]
    var amps = [1.0, 0.5, 0.25]
    var level: Float = 0.8
    var voiced = false
    var f0 = 200.0
    var frameIntervalSeconds = hop
}

func interrupted() -> Bool { false }

func verify(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

verify(SpeechLanguage.english.encodingProfile.envelopeExponent == 0.45 &&
       SpeechLanguage.english.encodingProfile.secondFormantGain == 1.8,
       "English codec must preserve all original acoustic settings")
verify(SpeechLanguage.hungarian.encodingProfile.envelopeExponent == 0.58 &&
       SpeechLanguage.hungarian.encodingProfile.secondFormantGain == 1.3,
       "Hungarian codec must use the one central acoustic profile")
var frame = SpeechFrame()
frame.voiced = true
speechLanguage = .english
let englishVowel = actuationForSpeechFrame(frame)!
let originalTones = formantTones(frame)
verify(englishVowel.tones[1].amp == originalTones[1].amp &&
       englishVowel.tones[1].hz == originalTones[1].hz,
       "English LPC formants must be unchanged")

speechLanguage = .hungarian
let hungarianVowel = actuationForSpeechFrame(frame)!
verify(hungarianVowel.tones[1].amp < englishVowel.tones[1].amp &&
       hungarianVowel.tones[0].amp > englishVowel.tones[0].amp,
       "Hungarian must favor the first formant without losing F2")
verify(hungarianVowel.tones.count == 2 &&
       hungarianVowel.durationSeconds == englishVowel.durationSeconds &&
       hungarianVowel.level == englishVowel.level,
       "Hungarian vowel motor rate and absolute level stay unchanged")

frame.f0 = 350
verify(abs(actuationForSpeechFrame(frame)!.durationSeconds - 0.004) < 1e-9,
       "speech pulse scheduler caps both languages at 250 Hz")

frame.voiced = false
frame.level = 0.75
speechLanguage = .hungarian
for _ in 0..<400 {
    let event = actuationForSpeechFrame(frame)!
    verify(event.tones.count == 3 &&
           event.tones.allSatisfy { (2700...4300).contains($0.hz) } &&
           abs(event.durationSeconds - 0.004) < 1e-9 &&
           event.level == frame.level * 0.7,
           "Hungarian fricatives retain amplitude and 4 ms pulses")
}
speechLanguage = .english
var sawOriginalUpperCarrier = false
for _ in 0..<400 {
    let event = actuationForSpeechFrame(frame)!
    verify(event.tones.count == 3 &&
           event.tones.allSatisfy { (2700...4300).contains($0.hz) } &&
           event.level == frame.level * 0.7,
           "English fricatives must retain original bounds")
    sawOriginalUpperCarrier = sawOriginalUpperCarrier ||
        event.tones.contains { $0.hz > 3900 }
}
verify(sawOriginalUpperCarrier,
       "English must keep its original 3900–4300 Hz consonant carriers")
print("PASS: shared motor safety, English parity and Hungarian tone bounds")
