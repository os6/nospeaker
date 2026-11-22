import Foundation

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

require(SpeechActuationLimits.minimumPulseRateHz == 70,
        "Both languages must respect the original 70 Hz lower speech pulse bound")
require(SpeechActuationLimits.maximumPulseRateHz == 250,
        "Both English and Hungarian must share the original 250 Hz ceiling")
require(SpeechActuationLimits.unvoicedPulseDurationSeconds == 0.004,
        "Unvoiced speech must keep original 4 ms pulses")
require(SpeechActuationLimits.cappedPulseRate(190) == 190,
        "Rates below the ceiling must remain unchanged")
require(SpeechActuationLimits.cappedPulseRate(350) == 250,
        "Rates above the ceiling must be clamped")
require(SpeechActuationLimits.cappedPulseRate(0) == 70,
        "Invalid or too-slow pulse rates must not cause division by zero")
print("PASS: global 250 Hz speech pulse-rate ceiling")
