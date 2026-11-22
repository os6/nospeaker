import Foundation

/// Reduce isolated high-frequency whistles without deleting the consonant
/// transients or raising the motor's actuation rate or normalized level.
enum HungarianToneStabilizer {
    private static let trackingDistanceHz = 320.0
    private static let upperToneStartHz = 1500.0

    static func stabilize(_ frames: inout [SpeechFrame]) {
        let original = frames.map(\.hungarianTones)

        for frameIndex in frames.indices where frames[frameIndex].voiced {
            guard frames[frameIndex].level > 0 else { continue }
            var tones = original[frameIndex]

            for toneIndex in tones.indices where tones[toneIndex].hz >= upperToneStartHz {
                let current = tones[toneIndex]
                let previousFrequency = neighbourFrequency(
                    at: frameIndex - 1, matching: current.hz,
                    frames: frames, originalTones: original
                )
                let nextFrequency = neighbourFrequency(
                    at: frameIndex + 1, matching: current.hz,
                    frames: frames, originalTones: original
                )

                // A high note occurring in one voiced frame surrounded by
                // voiced frames is spectral hopping, not a sustained formant.
                let isolated = previousFrequency == nil && nextFrequency == nil &&
                    frameIndex > 0 && frameIndex + 1 < frames.count &&
                    frames[frameIndex - 1].voiced && frames[frameIndex + 1].voiced
                if isolated {
                    tones[toneIndex].amp *= 0.25
                    if tones.count == 1 {
                        // The motor normalizes tone amplitudes: with a single
                        // tone, reducing its relative weight has no effect.
                        frames[frameIndex].level *= 0.25
                    }
                }

                // Smooth a tracked spectral component over 15 ms at most.
                // Stop-release boundaries are left alone when neighbours
                // are unvoiced or no coherent frequency match exists.
                if let previousFrequency, let nextFrequency {
                    tones[toneIndex].hz =
                        0.25 * previousFrequency + 0.5 * current.hz +
                        0.25 * nextFrequency
                }

                // During stable vowels the low spectral peak should dominate.
                // This avoids the high component sounding like a bell.
                if let lowTone = tones.first, lowTone.hz < 1300,
                   toneIndex > 0 {
                    tones[toneIndex].amp = min(tones[toneIndex].amp,
                                                lowTone.amp * 0.55)
                }
            }
            frames[frameIndex].hungarianTones = tones
        }
    }

    private static func neighbourFrequency(
        at index: Int, matching targetHz: Double,
        frames: [SpeechFrame],
        originalTones: [[(hz: Double, amp: Double)]]
    ) -> Double? {
        guard frames.indices.contains(index), frames[index].voiced,
              frames[index].level > 0 else { return nil }
        let closest = originalTones[index].min {
            abs($0.hz - targetHz) < abs($1.hz - targetHz)
        }
        guard let closest,
              abs(closest.hz - targetHz) <= trackingDistanceHz else { return nil }
        return closest.hz
    }
}
