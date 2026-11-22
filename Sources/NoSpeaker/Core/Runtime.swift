import Foundation
import Darwin

// MARK: - Run state, keys, clock

var stopRequested = false
var skipRequested = false
var keyPressed = false
/// Leaving goes through the credits: the first Ctrl-C (or q, or esc) jumps there, the next one exits.
var jumpToCredits = false
var inCredits = false
func requestEnd() { if inCredits || jumpToCredits { stopRequested = true } else { jumpToCredits = true } }
func interrupted() -> Bool { stopRequested || skipRequested || jumpToCredits }

let timebase: mach_timebase_info_data_t = {
    var info = mach_timebase_info_data_t()
    mach_timebase_info(&info)
    return info
}()
let ticksPerSecond = 1e9 * Double(timebase.denom) / Double(timebase.numer)
let t0 = mach_absolute_time()
func now() -> Double {
    // Swift initializes globals lazily. Read the start timestamp first so the
    // current clock sample cannot precede its first initialization.
    let startTimestamp = t0
    let currentTimestamp = mach_absolute_time()
    return Double(currentTimestamp - startTimestamp) / ticksPerSecond
}
/// Waits for a moment on the clock: sleeps, and spins only for the last ~1.5 ms (keeps timing tight
/// without pinning a CPU core).
func waitUntil(_ t: UInt64) {
    let margin = UInt64(0.0015 * ticksPerSecond)
    while !stopRequested {
        let n = mach_absolute_time()
        if n >= t { return }
        if t - n > margin { usleep(useconds_t(Double(t - n - margin) / ticksPerSecond * 1e6)) }
    }
}
func pause(_ seconds: Double) {
    let end = now() + seconds
    while now() < end && !interrupted() { usleep(5000) }
}

/// Stops with a plain explanation: a headline, then what happened and what to do, indented.
func fail(_ message: String, headline: String = "nospeaker can't play on this Mac.", code: Int32 = 1) -> Never {
    restoreTerminal()
    let body = message.split(separator: "\n", omittingEmptySubsequences: false).map { "  " + $0 }.joined(separator: "\n")
    FileHandle.standardError.write(("\n  " + headline + "\n\n" + body + "\n\n").data(using: .utf8)!)
    exit(code)
}
/// A mistake in how it was run: says what's wrong and points at --help.
func usageError(_ message: String) -> Never {
    fail(message + "\nSee nospeaker --help for the options.", headline: "nospeaker didn't understand that.", code: 64)
}
