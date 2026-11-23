import Foundation

/// Shared speech-actuation safety bounds for all supported languages.
///
/// This caps the rate of speech pulses. It does NOT cap the sine-tone carrier
/// frequencies: the original English synthesis intentionally uses higher
/// spectral frequencies for formants and consonants.
enum SpeechActuationLimits {
    static let minimumPulseRateHz = 70.0
    static let maximumPulseRateHz = 250.0

    static let unvoicedPulseDurationSeconds = 1.0 / maximumPulseRateHz

    static func cappedPulseRate(_ proposedRateHz: Double) -> Double {
        min(maximumPulseRateHz, max(minimumPulseRateHz, proposedRateHz))
    }
}
