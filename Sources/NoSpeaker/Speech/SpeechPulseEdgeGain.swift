import Foundation

/// Limit isolated modeled pulse-edge clicks without changing the motor
/// frequency, pitch trajectory, formant weighting or pulse timing.
/// No effect on English or unvoiced consonants (handled by the caller).
enum SpeechPulseEdgeGain {
    static func adjusted(
        level: Float, tones: [(hz: Double, amp: Double)],
        duration: Double, maximumReduction: Double
    ) -> Float {
        guard maximumReduction > 0, duration > 0, !tones.isEmpty else {
            return level
        }
        let total = max(tones.reduce(0.0) { $0 + $1.amp }, 1e-9)
        let edge = tones.reduce(0.0) { sum, tone in
            sum + tone.amp / total *
                  sin(2 * .pi * tone.hz * duration)
        }
        let risk = max(0, min(1, (abs(edge) - 0.30) / 0.70))
        return level * Float(1 - maximumReduction * risk)
    }
}
