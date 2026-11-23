import Foundation
import Darwin
import IOKit

// MARK: - The haptic motor (MultitouchSupport, resolved at run time)

let mt = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW)
func resolveMultitouchSymbol<T>(_ name: String, _: T.Type) -> T? {
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
typealias FrameCallback = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32
typealias RegisterCallback = @convention(c) (UnsafeMutableRawPointer, FrameCallback) -> Void
typealias DeviceStart = @convention(c) (UnsafeMutableRawPointer, Int32) -> Void
typealias DeviceStop = @convention(c) (UnsafeMutableRawPointer) -> Void

let createList = resolveMultitouchSymbol("MTDeviceCreateList", CreateList.self)
let getID = resolveMultitouchSymbol("MTDeviceGetDeviceID", GetID.self)
let isBuiltIn = resolveMultitouchSymbol("MTDeviceIsBuiltIn", IsBuiltIn.self)
let actuatorCreate = resolveMultitouchSymbol("MTActuatorCreateFromDeviceID", ActuatorCreate.self)
let actuatorOpen = resolveMultitouchSymbol("MTActuatorOpen", ActuatorOpen.self)
let actuatorClose = resolveMultitouchSymbol("MTActuatorClose", ActuatorClose.self)
let actuationCreate = resolveMultitouchSymbol("MTActuationCreateFromDictionary", ActuationCreate.self)
let actuationPlay = resolveMultitouchSymbol("MTActuationActuate", ActuationPlay.self)
let registerCallback = resolveMultitouchSymbol("MTRegisterContactFrameCallback", RegisterCallback.self)
let deviceStart = resolveMultitouchSymbol("MTDeviceStart", DeviceStart.self)
let deviceStop = resolveMultitouchSymbol("MTDeviceStop", DeviceStop.self)

var deviceCount = 0
var motorDeviceID: UInt64 = 0
var motorBuiltIn = false
var deviceList: CFArray?

/// The Mac's model identifier, like "MacBookPro18,3" or "Mac14,3".
func macModel() -> String {
    var size = 0
    sysctlbyname("hw.model", nil, &size, nil, 0)
    var buf = [CChar](repeating: 0, count: max(1, size))
    sysctlbyname("hw.model", &buf, &size, nil, 0)
    return String(cString: buf)
}
let isLaptop = macModel().hasPrefix("MacBook") || IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery")) != 0

/// Explains, in plain words, why there's no trackpad to play, and what would fix it.
func noTrackpad(_ found: Bool) -> Never {
    let message: String
    if !found && !isLaptop {
        message = """
        This Mac doesn't have a built-in trackpad, and no trackpad is connected.
        Connect a Magic Trackpad (2 or newer, the ones with Force Touch) and run it again.
        """
    } else if !found {
        message = "No trackpad was found. Make sure the trackpad is on and connected, then run it again."
    } else {
        message = """
        Found a trackpad, but it doesn't have a haptic motor (Force Touch), so it can't make sound.
        It needs a MacBook from 2015 or later, or a Magic Trackpad 2 or newer.
        """
    }
    fail(message)
}

func openMotor() -> CFTypeRef {
    guard let createList, let getID, let actuatorCreate, let actuatorOpen, actuationCreate != nil, actuationPlay != nil else {
        fail("This version of macOS doesn't have the trackpad functions this needs. It was made for macOS 12 to 27.")
    }
    guard let list = createList()?.takeRetainedValue(), CFArrayGetCount(list) > 0 else { noTrackpad(false) }
    deviceList = list
    var ids: [(id: UInt64, builtIn: Bool)] = []
    for i in 0..<CFArrayGetCount(list) {
        guard let raw = CFArrayGetValueAtIndex(list, i) else { continue }
        let dev = UnsafeMutableRawPointer(mutating: raw)
        var id: UInt64 = 0
        if getID(dev, &id) == 0 { ids.append((id, isBuiltIn?(dev) ?? false)) }
    }
    deviceCount = ids.count
    for d in ids.sorted(by: { $0.builtIn && !$1.builtIn }) {
        if let ref = actuatorCreate(d.id)?.takeRetainedValue(), actuatorOpen(ref) == 0 {
            motorDeviceID = d.id
            motorBuiltIn = d.builtIn
            return ref
        }
    }
    noTrackpad(true)
}

var motor: CFTypeRef?
var motorPointer: UnsafeMutableRawPointer?

/// Plays tones (Hz, relative strength) together for `ms` at overall `level` (0…1). Strengths are scaled to
/// add up to 1: past that is louder, but the driver starts stalling on long runs.
func playHapticTones(_ tones: [(hz: Double, amp: Double)], ms: Double, level: Float) {
    guard let motorPointer, !tones.isEmpty else { return }
    let sum = max(tones.reduce(0) { $0 + $1.amp }, 0.0001)
    let shape: [String: Any] = [
        "BaseWaveform": ["Type": "Gaussian", "Amplitude": 0.0, "DurationMS": ms],
        "Tones": tones.map { ["Type": "Sine", "Amplitude": $0.amp / sum, "DurationMS": ms, "DelayMS": 0.0, "FrequencykHz": $0.hz / 1000] },
    ]
    guard let act = actuationCreate!(shape as CFDictionary, 0) else { return }
    _ = actuationPlay!(act, motorPointer, 0, min(1, max(0, level)), 0)
    Unmanaged<AnyObject>.fromOpaque(act).release()
    let first = tones[0].hz
    updateLiveState {
        $0.actuations += 1; $0.hz = first; $0.level = Double(level); $0.lastPlay = now()
    }
}
