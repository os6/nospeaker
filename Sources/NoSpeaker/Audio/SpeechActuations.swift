import Foundation

/// One command given to the motor. The speaker preview renders the same
/// frequency, duration, and relative amplitude parameters in software.
struct SpeechActuation {
    let tones: [(hz: Double, amp: Double)]
    let durationSeconds: Double
    let level: Float
    let isVoiced: Bool
    let pitchHz: Double
    let firstFormantHz: Double
    let secondFormantHz: Double
}

/// Both languages use the same LPC speech model; the correctly selected
/// macOS voice is responsible for their different phonology.
func actuationForSpeechFrame(_ frame: SpeechFrame) -> SpeechActuation? {
    guard frame.level > 0 else { return nil }
    let profile = speechLanguage.encodingProfile
    if frame.voiced {
        let tones = formantTones(
            frame, secondFormantGain: profile.secondFormantGain
        )
        let duration = 1 / SpeechActuationLimits.cappedPulseRate(frame.f0)
        return SpeechActuation(
            tones: tones,
            durationSeconds: duration,
            level: SpeechPulseEdgeGain.adjusted(
                level: frame.level, tones: tones, duration: duration,
                maximumReduction: profile.maximumPulseEdgeReduction
            ),
            isVoiced: true,
            pitchHz: frame.f0,
            firstFormantHz: frame.formants[0],
            secondFormantHz: frame.formants[1]
        )
    }

    // Both languages retain the original carrier range: truncating it
    // degraded consonant recognition in controlled Hungarian tests.
    let consonantTones = (0..<3).map { _ in
        (hz: Double.random(in: 2700...4300), amp: 1.0)
    }
    return SpeechActuation(
        tones: consonantTones,
        durationSeconds: SpeechActuationLimits.unvoicedPulseDurationSeconds,
        level: frame.level * 0.7,
        isVoiced: false,
        pitchHz: 0,
        firstFormantHz: 0,
        secondFormantHz: 0
    )
}

/// The same timebase drives both motor playback and speaker preview.
func enumerateSpeechActuations(
    _ frames: [SpeechFrame],
    realtime: Bool,
    emit: (Double, SpeechActuation) -> Void,
    waitForTime: (Double) -> Void = { _ in }
) {
    guard !frames.isEmpty else { return }
    let frameInterval = frames[0].frameIntervalSeconds
    let totalDuration = Double(frames.count) * frameInterval
    var elapsedSeconds = 0.0

    while elapsedSeconds < totalDuration && (!realtime || !interrupted()) {
        let frame = frames[min(frames.count - 1, Int(elapsedSeconds / frameInterval))]
        let actuation = actuationForSpeechFrame(frame)
        if let actuation { emit(elapsedSeconds, actuation) }
        let step = actuation?.durationSeconds ??
            (frame.level > 0 && !frame.voiced ?
                SpeechActuationLimits.unvoicedPulseDurationSeconds : 0.005)
        elapsedSeconds += step
        if realtime { waitForTime(elapsedSeconds) }
    }
}
