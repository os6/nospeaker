import Foundation

struct HungarianAudioFeatures {
    let rms: Double
    let fundamentalHz: Double?
    let zeroCrossingRate: Double

    static func measure(samples: [Double]) -> HungarianAudioFeatures {
        guard !samples.isEmpty else {
            return HungarianAudioFeatures(rms: 0, fundamentalHz: nil,
                                          zeroCrossingRate: 0)
        }
        let frameEnergy = samples.reduce(0.0) { $0 + $1 * $1 }
        let rms = sqrt(frameEnergy / Double(samples.count))
        let crossings = zip(samples, samples.dropFirst()).reduce(0) { count, pair in
            count + ((pair.0 >= 0) != (pair.1 >= 0) ? 1 : 0)
        }
        let crossingRate = Double(crossings) / Double(samples.count)

        var maximumCorrelation = 0.0
        var strongestLag = 0
        let minimumLag = Int(sampleRate / 440)
        let maximumLag = min(samples.count / 2, Int(sampleRate / 80))

        if frameEnergy > 1e-8, maximumLag > minimumLag {
            for lag in minimumLag...maximumLag {
                var crossCorrelation = 0.0
                var firstEnergy = 0.0
                var secondEnergy = 0.0
                for index in 0..<(samples.count - lag) {
                    let current = samples[index]
                    let shifted = samples[index + lag]
                    crossCorrelation += current * shifted
                    firstEnergy += current * current
                    secondEnergy += shifted * shifted
                }
                let normalized = crossCorrelation /
                    max(sqrt(firstEnergy * secondEnergy), 1e-12)
                if normalized > maximumCorrelation {
                    maximumCorrelation = normalized
                    strongestLag = lag
                }
            }
        }

        let fundamental = maximumCorrelation > 0.42 && crossingRate < 0.26 &&
            strongestLag > 0 ? sampleRate / Double(strongestLag) : nil
        return HungarianAudioFeatures(rms: rms, fundamentalHz: fundamental,
                                      zeroCrossingRate: crossingRate)
    }
}
