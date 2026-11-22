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
            let originalTotal = tones.reduce(0.0) { $0 + $1.amp }
            let voicedNeighbours = frameIndex > 0 &&
                frameIndex + 1 < frames.count &&
                frames[frameIndex - 1].voiced && frames[frameIndex + 1].voiced

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

                // A high tone that jumps between unrelated spectral peaks
                // can whistle like a bell. Apply a short coherence weight
                // only INSIDE voiced sections, never over consonant releases.
                if voicedNeighbours {
                    switch (previousFrequency != nil, nextFrequency != nil) {
                    case (false, false):
                        tones[toneIndex].amp *= 0.18
                    case (false, true), (true, false):
                        tones[toneIndex].amp *= 0.50
                    case (true, true):
                        break
                    }
                }

                if let previousFrequency, let nextFrequency {
                    tones[toneIndex].hz =
                        0.25 * previousFrequency + 0.5 * current.hz +
                        0.25 * nextFrequency
                }

                // Preserve lower vowel energy instead of letting the
                // upper partial dominate the normalized haptic tone mix.
                if let lowTone = tones.first, lowTone.hz < 1300,
                   toneIndex > 0 {
                    tones[toneIndex].amp = min(tones[toneIndex].amp,
                                               lowTone.amp * 0.50)
                }
            }

            // The motor renormalizes all tone amplitudes. If every tone is
            // high (or there is only one), reducing weights alone has no
            // audible effect. Preserve the absolute reduction in frame level.
            let adjustedTotal = tones.reduce(0.0) { $0 + $1.amp }
            if originalTotal > 0 {
                frames[frameIndex].level *=
                    Float(min(1, adjustedTotal / originalTotal))
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
