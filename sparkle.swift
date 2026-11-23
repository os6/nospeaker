// sparkle · the nospeaker sparkle, alone: an arpeggio up, then the motor's purest note, on the trackpad.
// About one second, no windows, no audio. Made for "done" sounds (e.g. a Claude Code Stop hook).
//
//   sparkle          at 50% strength
//   sparkle 80       at 80% (0 to 100; never past the motor's normal maximum)
//
// Exits with 1 when there's no Force Touch trackpad to play on, so a hook can fall back to a normal sound:
//   sparkle 50 || afplay /System/Library/Sounds/Glass.aiff

import Darwin
import Foundation

let mt = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW)
func sym<T>(_ name: String, _: T.Type) -> T? {
    guard let mt, let p = dlsym(mt, name) else { return nil }
    return unsafeBitCast(p, to: T.self)
}
typealias CreateList = @convention(c) () -> Unmanaged<CFArray>?
typealias GetID = @convention(c) (UnsafeMutableRawPointer, UnsafeMutablePointer<UInt64>) -> Int32
typealias IsBuiltIn = @convention(c) (UnsafeMutableRawPointer) -> Bool
typealias ActuatorCreate = @convention(c) (UInt64) -> Unmanaged<CFTypeRef>?
typealias ActuatorOpen = @convention(c) (CFTypeRef) -> Int32
typealias ActuatorClose = @convention(c) (CFTypeRef) -> Int32
typealias ActuationCreate = @convention(c) (CFDictionary, Int32) -> UnsafeMutableRawPointer?
typealias ActuationPlay = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer, UInt32, Float, Float) -> Int32

guard let createList = sym("MTDeviceCreateList", CreateList.self),
      let getID = sym("MTDeviceGetDeviceID", GetID.self),
      let actuatorCreate = sym("MTActuatorCreateFromDeviceID", ActuatorCreate.self),
      let actuatorOpen = sym("MTActuatorOpen", ActuatorOpen.self),
      let actuationCreate = sym("MTActuationCreateFromDictionary", ActuationCreate.self),
      let actuationPlay = sym("MTActuationActuate", ActuationPlay.self) else { exit(1) }
let isBuiltIn = sym("MTDeviceIsBuiltIn", IsBuiltIn.self)
let actuatorClose = sym("MTActuatorClose", ActuatorClose.self)

let volume = Float(max(0, min(100, Double(CommandLine.arguments.dropFirst().first ?? "50") ?? 50)) / 100)

// The motor: the built-in trackpad first, then any other Force Touch trackpad.
guard let list = createList()?.takeRetainedValue() else { exit(1) }
var ids: [(id: UInt64, builtIn: Bool)] = []
for i in 0..<CFArrayGetCount(list) {
    guard let raw = CFArrayGetValueAtIndex(list, i) else { continue }
    let dev = UnsafeMutableRawPointer(mutating: raw)
    var id: UInt64 = 0
    if getID(dev, &id) == 0 { ids.append((id, isBuiltIn?(dev) ?? false)) }
}
var motor: CFTypeRef?
for d in ids.sorted(by: { $0.builtIn && !$1.builtIn }) {
    if let ref = actuatorCreate(d.id)?.takeRetainedValue(), actuatorOpen(ref) == 0 { motor = ref; break }
}
guard let motor else { exit(1) }
let motorPointer = Unmanaged.passUnretained(motor as AnyObject).toOpaque()

var timebase = mach_timebase_info_data_t()
mach_timebase_info(&timebase)
let ticksPerSecond = 1e9 * Double(timebase.denom) / Double(timebase.numer)
func waitUntil(_ t: UInt64) {
    let margin = UInt64(0.0015 * ticksPerSecond)
    while true {
        let n = mach_absolute_time()
        if n >= t { return }
        if t - n > margin { usleep(useconds_t(Double(t - n - margin) / ticksPerSecond * 1e6)) }
    }
}

/// One sine tone for `ms` at `level` (0…1, scaled by the volume).
func tone(_ hz: Double, ms: Double, level: Float) {
    let shape: [String: Any] = [
        "BaseWaveform": ["Type": "Gaussian", "Amplitude": 0.0, "DurationMS": ms],
        "Tones": [["Type": "Sine", "Amplitude": 1.0, "DurationMS": ms, "DelayMS": 0.0, "FrequencykHz": hz / 1000]],
    ]
    guard let act = actuationCreate(shape as CFDictionary, 0) else { return }
    _ = actuationPlay(act, motorPointer, 0, min(1, max(0, level)) * volume, 0)
    Unmanaged<AnyObject>.fromOpaque(act).release()
}

// A5 C6 E6 A6 C7, ~70 ms each, then 3951 Hz fading out over 0.6 s.
for f in [880.0, 1046.5, 1318.51, 1760.0, 2093.0] {
    let seg = (0.07 * f).rounded() / f
    let end = mach_absolute_time() + UInt64(seg * ticksPerSecond)
    tone(f, ms: seg * 1000, level: 0.9)
    waitUntil(end)
}
let start = mach_absolute_time()
let seg = (0.02 * 3951).rounded() / 3951
var t = 0.0
while t < 0.6 {
    tone(3951, ms: seg * 1000, level: Float(exp(-t / 0.18)))
    t += seg
    waitUntil(start + UInt64(t * ticksPerSecond))
}
usleep(30_000)
_ = actuatorClose?(motor)
