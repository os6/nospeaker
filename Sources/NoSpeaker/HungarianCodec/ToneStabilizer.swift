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
                        if let bridged = bridgedUpperFrequency(
                            at: frameIndex, replacing: current.hz,
                            originalTones: original
                        ) {
                            // Rejoin a coherent 5 ms spectral track instead
                            // of outputting an unrelated high-pitched chime.
                            tones[toneIndex].hz = bridged
                            tones[toneIndex].amp *= 0.70
                        } else {
                            tones[toneIndex].amp *= 0.18
                        }
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

        softenSustainedFricatives(&frames, originalTones: original)
    }

    /// A narrow high note held through a noisy /sz/ or /s/ sounds like a
    /// whistle. Only reduce upper-band energy *inside* sustained unvoiced
    /// regions; protect the first/last frames of each consonant and all
    /// short stop releases.
    private static func softenSustainedFricatives(
        _ frames: inout [SpeechFrame],
        originalTones: [[(hz: Double, amp: Double)]]
    ) {
        guard frames.count >= 3 else { return }
        for index in 1..<(frames.count - 1) {
            guard !frames[index].voiced, frames[index].level > 0,
                  !frames[index - 1].voiced, frames[index - 1].level > 0,
                  !frames[index + 1].voiced, frames[index + 1].level > 0 else {
                continue
            }

            let tones = originalTones[index]
            let total = tones.reduce(0.0) { $0 + $1.amp }
            guard total > 0 else { continue }
            let highTones = tones.filter { $0.hz >= 2800 }
            guard !highTones.isEmpty else { continue }
            let highShare = highTones.reduce(0.0) { $0 + $1.amp } / total

            // Untracked upper peaks behave like narrowband whistles. A
            // continuous fricative is attenuated less than an erratic one.
            let trackedOnBothSides = highTones.allSatisfy { high in
                [index - 1, index + 1].allSatisfy { neighbour in
                    originalTones[neighbour].contains { candidate in
                        abs(candidate.hz - high.hz) <= trackingDistanceHz
                    }
                }
            }
            let upperBandGain = trackedOnBothSides ? 0.82 : 0.58
            frames[index].level *= Float(1 - highShare * (1 - upperBandGain))
        }
    }

    /// Interpolate a missing upper spectral partial only when both adjacent
    /// *voiced* frames agree on its trajectory. A true new consonant sound
    /// has no such coherent track and is not replaced.
    private static func bridgedUpperFrequency(
        at index: Int, replacing outlierHz: Double,
        originalTones: [[(hz: Double, amp: Double)]]
    ) -> Double? {
        let previous = originalTones[index - 1].filter { $0.hz >= upperToneStartHz }
        let following = originalTones[index + 1].filter { $0.hz >= upperToneStartHz }
        let possible = previous.flatMap { before in
            following.compactMap { after -> Double? in
                guard abs(before.hz - after.hz) <= 280 else { return nil }
                let middle = (before.hz + after.hz) / 2
                return abs(outlierHz - middle) > 500 ? middle : nil
            }
        }
        return possible.min { abs($0 - outlierHz) < abs($1 - outlierHz) }
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
