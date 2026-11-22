import Foundation

/// Independent Hungarian audio-to-haptic codec. Retains rapid consonant
/// transients instead of reducing every voiced frame to fixed F1/F2 tones.
enum HungarianVocoder {
    static let analysisHopSize = 80 // 5 ms at 16 kHz

    static func encode(_ input: [Float]) -> [SpeechFrame] {
        guard input.count >= HungarianSpectrum.analysisWindowSize else { return [] }
        var frames: [SpeechFrame] = []
        var frameRMS: [Double] = []
        var previousRMS = 0.0

        for offset in stride(from: 0,
                             through: input.count - HungarianSpectrum.analysisWindowSize,
                             by: analysisHopSize) {
            let samples = (0..<HungarianSpectrum.analysisWindowSize).map {
                Double(input[offset + $0])
            }
            let features = HungarianAudioFeatures.measure(samples: samples)
            let peaks = HungarianSpectrum.peaks(in: samples)
            let onsetRatio = features.rms / max(previousRMS, 0.005)
            let isVoiced = features.fundamentalHz != nil

            // Fast releases and noisy consonants need their upper-spectrum
            // peaks. Stable voiced vowels retain the low + high spectral pair.
            let isConsonantTransient = !isVoiced || onsetRatio > 1.65
            let tones = HungarianSpectrum.tones(from: peaks,
                                                emphasizeUpperSpectrum: isConsonantTransient)
            var frame = SpeechFrame()
            frame.frameIntervalSeconds = Double(analysisHopSize) / sampleRate
            frame.voiced = isVoiced
            // Stay within the original English motor scheduling ceiling.
            frame.f0 = SpeechActuationLimits.cappedPulseRate(features.fundamentalHz ?? 180)
            frame.hungarianTones = tones

            if let lowTone = tones.first {
                frame.formants[0] = lowTone.hz
            }
            if tones.count > 1 {
                frame.formants[1] = tones[1].hz
            }
            frames.append(frame)
            frameRMS.append(features.rms)
            previousRMS = features.rms
        }

        let highestRMS = frameRMS.max() ?? 0
        guard highestRMS > 1e-8 else { return [] }
        for index in frames.indices {
            let relativeLevel = frameRMS[index] / highestRMS
            frames[index].level = relativeLevel < 0.018 ? 0 :
                Float(min(1, pow(relativeLevel, 1.08)))
            if frames[index].level == 0 {
                frames[index].voiced = false
                frames[index].hungarianTones = []
            }
        }
        HungarianToneStabilizer.stabilize(&frames)
        return frames
    }
}
