import Foundation

/// Only the Hungarian path uses this correction. The haptic driver begins
/// every new sine-tone command at zero phase; an integer number of carrier
/// cycles per pulse avoids an abrupt discontinuity at its end.
///
/// Never change pulse durations, the 70–250 Hz scheduling limit or levels.
enum HungarianPulsePhaseAlignment {
    static func tones(
        _ input: [(hz: Double, amp: Double)], duration: Double
    ) -> [(hz: Double, amp: Double)] {
        guard duration > 0 else { return input }
        return input.map { tone in
            let cycles = max(1, (tone.hz * duration).rounded())
            return (hz: cycles / duration, amp: tone.amp)
        }
    }
}
