import Foundation

func assertConsonant(_ result: @autoclosure () -> Bool, _ reason: String) {
    guard result() else {
        fputs("FAIL: \(reason)\n", stderr)
        exit(1)
    }
}

let sampleRate = 16000.0
let samplesCount = 400
let silentFrame = [Double](repeating: 0, count: samplesCount)
assertConsonant(hungarianConsonantTones(samples: silentFrame, samplingRate: sampleRate).isEmpty,
                "silence must not generate consonant tones")

func sineFrame(at frequencyHz: Double) -> [Double] {
    (0..<samplesCount).map { sampleIndex in
        sin(2 * .pi * frequencyHz * Double(sampleIndex) / sampleRate)
    }
}

let lowFrequencyConsonant = hungarianConsonantTones(samples: sineFrame(at: 1200), samplingRate: sampleRate)
let highFrequencyConsonant = hungarianConsonantTones(samples: sineFrame(at: 3250), samplingRate: sampleRate)
assertConsonant(lowFrequencyConsonant.first?.hz == 1200, "a 1200 Hz component should remain distinguishable")
assertConsonant(highFrequencyConsonant.first?.hz == 3250, "a 3250 Hz component should remain distinguishable")
let repeatedLowFrequency = hungarianConsonantTones(samples: sineFrame(at: 1200), samplingRate: sampleRate)
assertConsonant(lowFrequencyConsonant.count == repeatedLowFrequency.count &&
                zip(lowFrequencyConsonant, repeatedLowFrequency).allSatisfy {
                    $0.0.hz == $0.1.hz && $0.0.amp == $0.1.amp
                }, "same speech frame must yield deterministic tones")
assertConsonant((lowFrequencyConsonant + highFrequencyConsonant).allSatisfy {
    (100...4000).contains($0.hz) && $0.amp > 0 && $0.amp <= 1
}, "haptic frequency and relative amplitude bounds")
print("PASS: deterministic Hungarian consonant spectral features")
