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

func actuationForSpeechFrame(_ frame: SpeechFrame) -> SpeechActuation? {
    guard frame.level > 0 else { return nil }

    if frame.voiced {
        return SpeechActuation(
            tones: speechLanguage == .hungarian && !frame.hungarianTones.isEmpty
                ? frame.hungarianTones : formantTones(frame),
            durationSeconds: 1 / frame.f0,
            level: frame.level,
            isVoiced: true,
            pitchHz: frame.f0,
            firstFormantHz: frame.formants[0],
            secondFormantHz: frame.formants[1]
        )
    }

    let consonantTones = speechLanguage == .hungarian
        ? frame.hungarianTones
        : (0..<3).map { _ in (hz: Double.random(in: 2700...4300), amp: 1.0) }
    guard !consonantTones.isEmpty else { return nil }
    return SpeechActuation(tones: consonantTones, durationSeconds: 0.004,
                           level: frame.level * 0.7, isVoiced: false,
                           pitchHz: 0, firstFormantHz: 0, secondFormantHz: 0)
}

/// Shared timebase for motor playback and offline speaker preview.
/// The callback never opens a device; the caller chooses where to send commands.
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
            (frame.level > 0 && !frame.voiced ? 0.004 : 0.005)
        elapsedSeconds += step
        if realtime { waitForTime(elapsedSeconds) }
    }
}
