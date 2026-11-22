import Foundation

// Standalone deterministic tests of the Hungarian encoder's phoneme gating,
// vowel preservation, and F2/F3 transitions. No speech engine or motor needed.
struct SpeechFrame {
    var formants = [500.0, 1500.0, 2500.0]
    var level: Float = 0
    var voiced = true
    var hungarianTones: [(hz: Double, amp: Double)] = []
}

func validate(_ result: @autoclosure () -> Bool, _ reason: String) {
    guard result() else {
        fputs("FAIL: \(reason)\n", stderr)
        exit(1)
    }
}

let stable = SpeechFrame(formants: [500, 1500, 2500], level: 1, voiced: true)
let transition = SpeechFrame(formants: [460, 1950, 2800], level: 0.35, voiced: true)
let ending = SpeechFrame(formants: [420, 2250, 3200], level: 0.4, voiced: true)

var hungarian = [stable, transition, ending]
HungarianSpeechEncoder.apply(to: &hungarian, text: "hogy")
validate(hungarian[1].hungarianTones.count == 2, "gy must preserve F2/F3 transition cues")
validate(hungarian[1].hungarianTones[0].hz == 1950, "palatal F2 frequency")
validate(hungarian[1].hungarianTones[1].hz == 2800, "palatal F3 frequency")
validate(hungarian[0].hungarianTones.isEmpty, "stable vowel retains F1/F2")

var ordinary = [stable, transition, ending]
HungarianSpeechEncoder.apply(to: &ordinary, text: "hogi")
validate(ordinary.allSatisfy { $0.hungarianTones.isEmpty },
         "g+i is not a palatal stop and must not trigger gy encoding")

var noTransition = [stable, stable, stable]
HungarianSpeechEncoder.apply(to: &noTransition, text: "gyár")
validate(noTransition.allSatisfy { $0.hungarianTones.isEmpty },
         "stable vowel must not be replaced with consonant cues")

print("PASS: Hungarian phoneme-gated F2/F3 encoding and vowel preservation")
