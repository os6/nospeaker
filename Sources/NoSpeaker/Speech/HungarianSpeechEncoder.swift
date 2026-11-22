import Foundation

/// A Hungarian-specific two-tone encoder, separate from the original English
/// F1/F2 path. Phonemes select which acoustic cues matter; the audio frames
/// still supply the actual frequencies and timing.
enum HungarianSpeechEncoder {
    static func apply(to frames: inout [SpeechFrame], text: String) {
        let phonemes = HungarianPhonology.transcribe(text)
        let hasPalatalStop = phonemes.contains { $0.isPalatalStop }
        guard hasPalatalStop, frames.count >= 3 else { return }

        let original = frames
        for index in 1..<(original.count - 1) {
            let frame = original[index]
            guard frame.voiced, frame.level > 0 else { continue }

            let previous = original[index - 1]
            let following = original[index + 1]

            // The original coder discards F3 entirely. Hungarian palatal
            // stops are distinguished partly by fast F2/F3 transitions.
            // Do not switch the stable vowel nuclei to F2/F3.
            let formantMotion =
                abs(following.formants[1] - previous.formants[1]) +
                0.6 * abs(following.formants[2] - previous.formants[2])
            let localMaximum = max(previous.level, following.level, frame.level)
            let lowEnergyTransition = Double(frame.level) <
                max(0.55, Double(localMaximum) * 0.85)

            guard lowEnergyTransition, formantMotion > 160 else { continue }

            let secondFormant = frame.formants[1]
            let thirdFormant = frame.formants[2]
            guard (650...2700).contains(secondFormant),
                  (1700...3900).contains(thirdFormant),
                  thirdFormant - secondFormant >= 180 else { continue }

            // Keep two tones: the motor loses intensity when many compete.
            // F2/F3 carry palatal place cues; the original F1/F2 pair
            // remains for sustained vowels and for all English output.
            frames[index].hungarianTones = [
                (hz: secondFormant, amp: 0.65),
                (hz: thirdFormant, amp: 0.35)
            ]
        }
    }
}
