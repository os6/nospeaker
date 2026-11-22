import Foundation

struct HungarianSpectralPeak {
    let frequencyHz: Double
    let energy: Double
}

/// Measure real audio energy at regularly spaced frequencies. No synthetic
/// consonant notes are inserted: peaks come from Tünde's rendered waveform.
enum HungarianSpectrum {
    static let analysisWindowSize = 320
    static let frequencyStepHz = 100.0
    static let analysisFrequencies = stride(from: 300.0, through: 3900.0,
                                            by: frequencyStepHz).map { $0 }

    static func peaks(in samples: [Double]) -> [HungarianSpectralPeak] {
        guard samples.count >= analysisWindowSize else { return [] }
        var previousInput = 0.0
        let windowed = samples.prefix(analysisWindowSize).enumerated().map { index, value in
            let emphasized = value - 0.90 * previousInput
            previousInput = value
            let window = 0.5 - 0.5 * cos(2 * .pi * Double(index) /
                                          Double(analysisWindowSize - 1))
            return emphasized * window
        }

        let spectrum = analysisFrequencies.map { frequency -> HungarianSpectralPeak in
            let coefficient = 2 * cos(2 * .pi * frequency / sampleRate)
            var previous = 0.0
            var previousPrevious = 0.0
            for sample in windowed {
                let current = sample + coefficient * previous - previousPrevious
                previousPrevious = previous
                previous = current
            }
            let power = max(0, previous * previous +
                               previousPrevious * previousPrevious -
                               coefficient * previous * previousPrevious)
            return HungarianSpectralPeak(frequencyHz: frequency,
                                         energy: power)
        }

        return spectrum.indices.compactMap { index in
            let current = spectrum[index]
            let leftEnergy = index > 0 ? spectrum[index - 1].energy : 0
            let rightEnergy = index + 1 < spectrum.count ? spectrum[index + 1].energy : 0
            return current.energy >= leftEnergy && current.energy > rightEnergy ?
                current : nil
        }
    }

    static func strongest(_ peaks: [HungarianSpectralPeak],
                          within frequencyRange: ClosedRange<Double>,
                          excluding frequency: Double? = nil) -> HungarianSpectralPeak? {
        peaks.filter { candidate in
            guard frequencyRange.contains(candidate.frequencyHz) else { return false }
            guard let frequency else { return true }
            return abs(candidate.frequencyHz - frequency) >= 450
        }.max { $0.energy < $1.energy }
    }

    static func tones(from peaks: [HungarianSpectralPeak],
                      emphasizeUpperSpectrum: Bool) -> [(hz: Double, amp: Double)] {
        guard !peaks.isEmpty else { return [] }

        let first = emphasizeUpperSpectrum ?
            strongest(peaks, within: 1200...3900) :
            strongest(peaks, within: 300...1300)
        guard let first else { return [] }

        let second = strongest(peaks, within: 1200...3900,
                               excluding: first.frequencyHz)

        let maximumEnergy = max(first.energy, second?.energy ?? 0)
        guard maximumEnergy > 1e-8 else { return [] }
        let meaningfulSecond = second.flatMap { candidate in
            candidate.energy >= maximumEnergy * 0.025 ? candidate : nil
        }
        let chosenPeaks = [first] + (meaningfulSecond.map { [$0] } ?? [])

        return chosenPeaks.map { peak in
            (hz: peak.frequencyHz,
             amp: pow(max(0.0001, peak.energy / maximumEnergy), 0.40))
        }
    }
}
