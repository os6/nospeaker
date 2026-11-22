import Foundation

/// Preserve high-frequency consonant information in Hungarian speech.
/// Unlike the original random-noise approximation, the selected frequencies
/// come from each unvoiced audio frame, within the trackpad's existing range.
func hungarianConsonantTones(samples: [Double], samplingRate: Double) -> [(hz: Double, amp: Double)] {
    guard samples.count >= 2, samplingRate > 0 else { return [] }

    // A small, fixed frequency bank avoids FFT dependencies and keeps the
    // analysis cost bounded for the 25 ms windows used by the speech encoder.
    let bandCentersHz: [Double] = [800, 1200, 1650, 2150, 2700, 3250, 3850]
    let powerByBand = bandCentersHz.map { centerHz -> Double in
        let coefficient = 2 * cos(2 * .pi * centerHz / samplingRate)
        var previousSample = 0.0
        var previousPreviousSample = 0.0

        for sample in samples {
            let current = sample + coefficient * previousSample - previousPreviousSample
            previousPreviousSample = previousSample
            previousSample = current
        }

        return max(0, previousSample * previousSample +
                      previousPreviousSample * previousPreviousSample -
                      coefficient * previousSample * previousPreviousSample)
    }

    let peakPower = powerByBand.max() ?? 0
    guard peakPower > 1e-10 else { return [] }

    // Choose two separated bands: nearly identical frequencies convey less
    // information about the original consonant's spectral distribution.
    let rankedIndices = powerByBand.indices.sorted { powerByBand[$0] > powerByBand[$1] }
    let strongestIndex = rankedIndices[0]
    let secondIndex = rankedIndices.dropFirst().first {
        abs(bandCentersHz[$0] - bandCentersHz[strongestIndex]) >= 600
            && powerByBand[$0] >= peakPower * 0.15
    }

    var selectedIndices = [strongestIndex]
    if let secondIndex { selectedIndices.append(secondIndex) }

    return selectedIndices.map { bandIndex in
        (hz: bandCentersHz[bandIndex], amp: sqrt(powerByBand[bandIndex] / peakPower))
    }
}
