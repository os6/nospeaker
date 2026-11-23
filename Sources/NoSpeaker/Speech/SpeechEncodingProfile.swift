import Foundation

/// Acoustic settings for the shared LPC speech codec. Hardware pulse-rate
/// limits are independent and live in SpeechActuationLimits.
struct SpeechEncodingProfile {
    let envelopeExponent: Double
    let secondFormantGain: Double
}

extension SpeechLanguage {
    var encodingProfile: SpeechEncodingProfile {
        switch self {
        case .english:
            // Keep the original English audio-to-haptic behavior.
            SpeechEncodingProfile(
                envelopeExponent: 0.45,
                secondFormantGain: 1.8
            )
        case .hungarian:
            // Preserve Tünde's LPC cues while reducing exaggerated
            // low-level pulses while preserving consonant information.
            SpeechEncodingProfile(
                envelopeExponent: 0.58,
                secondFormantGain: 1.3
            )
        }
    }
}
