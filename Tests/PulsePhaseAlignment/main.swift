import Foundation

func require(_ value: @autoclosure () -> Bool, _ reason: String) {
    guard value() else {
        fputs("FAIL: \(reason)\n", stderr)
        exit(1)
    }
}

for rate in [70.0, 110.0, 180.0, 220.0, 250.0] {
    let duration = 1 / rate
    for frequency in stride(from: 300.0, through: 3900.0, by: 37.0) {
        let output = HungarianPulsePhaseAlignment.tones(
            [(hz: frequency, amp: 0.75)], duration: duration
        )[0]
        let cycles = output.hz * duration
        require(abs(cycles - cycles.rounded()) < 1e-9,
                "the pulse must finish at zero phase")
        require(abs(output.hz - frequency) <= rate / 2 + 1e-9,
                "frequency correction must not exceed half the pulse rate")
        require(output.amp == 0.75,
                "the relative amplitude must not change")
    }
}
require(HungarianPulsePhaseAlignment.tones(
    [(hz: 1800, amp: 1), (hz: 3300, amp: 0.5)],
    duration: 1 / 250
).count == 2, "the Hungarian tone count must remain unchanged")
print("PASS: Hungarian phase correction without fricative randomization")
