// nospeaker · a90.com
//
// A MacBook's Force Touch trackpad has no speaker: the click you feel is faked by a small motor under the
// glass. This program drives that motor directly, through MultitouchSupport (a private macOS framework), and
// uses it to talk, sing, play a beat, and turn into an instrument under your finger.
//
//   nospeaker                      the show: about a minute and a half, in the terminal
//   nospeaker "any words"          say something
//   nospeaker --sweep              a rising tone from 100 Hz to 4 kHz
//   options                        --voice <name> (any voice from `say -v '?'`), --dark, --plain
//
// How it talks: macOS's own voice (`say`) speaks the line into memory. Every 10 ms, linear prediction finds
// the voice's two strongest resonances (formants), its loudness and its pitch. The motor plays those two
// resonances as sine tones, restarted on every beat of the pitch, so they buzz like a voice. The motor is loud
// from about 100 Hz to 4 kHz, which covers the most important part of speech.
//
// Private API: MultitouchSupport is undocumented and may change with any macOS update. The motor is never
// driven past its normal maximum.

import AVFoundation
import CoreAudio
import Darwin
import IOKit
import Foundation

// MARK: - Heap-allocated unfair lock & async-signal-safe lifecycle

/// Heap-allocated `os_unfair_lock` container: eliminates Swift `&globalVar` Law-of-Exclusivity UB
/// and satisfies Swift 6 `Sendable` checking across threads and C callbacks.
final class HeapUnfairLock<State>: @unchecked Sendable {
    private let lockPtr: UnsafeMutablePointer<os_unfair_lock>
    private var state: State

    init(_ initial: State) {
        self.lockPtr = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
        self.lockPtr.initialize(to: os_unfair_lock())
        self.state = initial
    }

    deinit {
        lockPtr.deinitialize(count: 1)
        lockPtr.deallocate()
    }

    @inline(__always)
    func withLock<R>(_ body: (inout State) -> R) -> R {
        os_unfair_lock_lock(lockPtr)
        defer { os_unfair_lock_unlock(lockPtr) }
        return body(&state)
    }
}

/// Monotonic lifecycle lattice: `running (0) -> jumpingToCredits (1) -> inCredits (2) -> stopped (3)`.
enum RunPhase: Int, Comparable, Sendable {
    case running = 0
    case jumpingToCredits = 1
    case inCredits = 2
    case stopped = 3

    static func < (lhs: RunPhase, rhs: RunPhase) -> Bool { lhs.rawValue < rhs.rawValue }
}

final class RunController: Sendable {
    private struct State {
        var phase: RunPhase = .running
        var skipRequested = false
        var keyPressed = false
        var cliMode = false
    }
    private let state = HeapUnfairLock(State())

    func setCLIMode(_ enabled: Bool) {
        state.withLock { $0.cliMode = enabled }
    }

    /// Leaving goes through the credits in the TUI show (`running -> jumpingToCredits`),
    /// and exits immediately on the second request (`jumpingToCredits | inCredits -> stopped`)
    /// or on the first request in CLI / pre-show mode.
    func requestEnd() {
        state.withLock { s in
            if s.cliMode {
                s.phase = .stopped
                return
            }
            switch s.phase {
            case .running:
                s.phase = .jumpingToCredits
            case .jumpingToCredits, .inCredits, .stopped:
                s.phase = .stopped
            }
        }
    }

    func requestHardStop() {
        state.withLock { $0.phase = .stopped }
    }

    /// Monotonically enters `.inCredits` unless `.stopped` has already been reached.
    func beginCreditsScene() -> Bool {
        state.withLock { s in
            guard s.phase != .stopped else { return false }
            if s.phase < .inCredits { s.phase = .inCredits }
            s.skipRequested = false
            return true
        }
    }

    var stopRequested: Bool {
        state.withLock { $0.phase == .stopped }
    }

    var shouldSkipToCredits: Bool {
        state.withLock { $0.phase == .jumpingToCredits || $0.phase == .stopped }
    }

    var interrupted: Bool {
        state.withLock { $0.phase == .jumpingToCredits || $0.phase == .stopped || $0.skipRequested }
    }

    func setSkipRequested(_ v: Bool) {
        state.withLock { $0.skipRequested = v }
    }

    var skipRequested: Bool {
        state.withLock { $0.skipRequested }
    }

    func setKeyPressed(_ v: Bool) {
        state.withLock { $0.keyPressed = v }
    }

    var keyPressed: Bool {
        state.withLock { $0.keyPressed }
    }
}

/// Non-blocking, close-on-exec self-pipe for 100% POSIX async-signal-safe signal delivery.
struct SignalPipe: Sendable {
    let readFD: Int32
    let writeFD: Int32

    init() {
        var fds: [Int32] = [-1, -1]
        if Darwin.pipe(&fds) == 0 {
            for fd in fds {
                let fl = fcntl(fd, F_GETFD)
                if fl >= 0 { _ = fcntl(fd, F_SETFD, fl | FD_CLOEXEC) }
                let st = fcntl(fd, F_GETFL)
                if st >= 0 { _ = fcntl(fd, F_SETFL, st | O_NONBLOCK) }
            }
            self.readFD = fds[0]
            self.writeFD = fds[1]
        } else {
            self.readFD = -1
            self.writeFD = -1
        }
    }
}

let signalPipe = SignalPipe()
let runControl = RunController()

func handleSigInt(_: Int32) {
    let saved = errno
    var b: UInt8 = 1
    if signalPipe.writeFD >= 0 { _ = Darwin.write(signalPipe.writeFD, &b, 1) }
    errno = saved
}

func handleSigTerm(_: Int32) {
    let saved = errno
    var b: UInt8 = 2
    if signalPipe.writeFD >= 0 { _ = Darwin.write(signalPipe.writeFD, &b, 1) }
    errno = saved
}

func startSignalWatcher() {
    guard signalPipe.readFD >= 0 else { return }
    let th = Thread {
        var b: UInt8 = 0
        var pfd = pollfd(fd: signalPipe.readFD, events: Int16(POLLIN), revents: 0)
        while true {
            let pr = Darwin.poll(&pfd, 1, -1)
            if pr < 0 {
                if errno == EINTR { continue }
                break
            }
            while Darwin.read(signalPipe.readFD, &b, 1) == 1 {
                if b == 1 {
                    runControl.requestEnd()
                } else {
                    runControl.requestHardStop()
                }
            }
        }
    }
    th.qualityOfService = .userInteractive
    th.start()
}

func requestEnd() { runControl.requestEnd() }
func interrupted() -> Bool { runControl.interrupted }

// MARK: - Mach monotonic clock

let ticksPerSecond: Double = {
    var tb = mach_timebase_info_data_t()
    guard mach_timebase_info(&tb) == KERN_SUCCESS, tb.numer > 0, tb.denom > 0 else {
        return 1e9
    }
    return 1e9 * Double(tb.denom) / Double(tb.numer)
}()
let t0 = mach_absolute_time()
func now() -> Double {
    let cur = mach_absolute_time()
    return cur >= t0 ? Double(cur - t0) / ticksPerSecond : 0.0
}

/// Computes `start + seconds` in Mach ticks without risking `UInt64(NaN/Inf/<0)` or overflow traps.
@inline(__always)
func deadlineTicks(from start: UInt64, after seconds: Double) -> UInt64 {
    guard seconds.isFinite, seconds > 0 else { return start }
    let bounded = min(seconds, 3600.0)
    let scaled = bounded * ticksPerSecond
    guard scaled.isFinite, scaled >= 0, scaled < Double(UInt64.max / 2) else { return start }
    let (res, overflow) = start.addingReportingOverflow(UInt64(scaled))
    return overflow ? UInt64.max : res
}

/// Waits for a moment on the clock: sleeps in <=20 ms interruptible slices, and spins only for the
/// last ~1.5 ms (keeps timing tight without pinning a CPU core or stalling Ctrl-C / skip).
func waitUntil(_ t: UInt64, allowSkip: Bool = true) {
    let margin = UInt64(max(1.0, 0.0015 * ticksPerSecond))
    while !(allowSkip ? runControl.interrupted : runControl.stopRequested) {
        let n = mach_absolute_time()
        if n >= t { return }
        let rem = t - n
        if rem > margin {
            let sleepSec = Double(rem - margin) / ticksPerSecond
            if sleepSec.isFinite && sleepSec > 0 {
                let us = min(20_000.0, sleepSec * 1e6)
                if us >= 1.0 { usleep(useconds_t(us)) }
            }
        }
    }
}

func pause(_ seconds: Double) {
    guard seconds.isFinite, seconds > 0 else { return }
    let end = now() + min(seconds, 3600.0)
    while now() < end && !interrupted() { usleep(5000) }
}

/// Strips C0 (`0x00...0x1F`, incl. `ESC`), `DEL` (`0x7F`), and C1 (`0x80...0x9F`, incl. `CSI`/`OSC`)
/// bytes from untrusted strings before writing to a terminal stream, capped to `maxBytes`.
func sanitizeTerminal(_ raw: String, maxBytes: Int = 256) -> String {
    var clean: [UInt8] = []
    clean.reserveCapacity(min(raw.utf8.count, maxBytes))
    for b in raw.utf8 {
        if b >= 0x20 && b <= 0x7E {
            clean.append(b)
            if clean.count >= maxBytes { break }
        }
    }
    return String(decoding: clean, as: UTF8.self)
}

/// Writes all UTF-8 bytes of `s` to `fd`, retrying on `EINTR` and bounded transient `EAGAIN`
/// so partial ANSI control sequences are never dropped mid-frame.
@discardableResult
func writeAll(_ fd: Int32, _ s: String) -> Bool {
    guard fd >= 0 else { return false }
    if s.isEmpty { return true }
    var copy = s
    return copy.withUTF8 { buf in
        guard let base = buf.baseAddress else { return true }
        var off = 0
        var transientRetries = 0
        while off < buf.count {
            let n = Darwin.write(fd, base + off, buf.count - off)
            if n > 0 {
                off += n
                transientRetries = 0
            } else if n < 0 && errno == EINTR {
                continue
            } else if n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) && transientRetries < 50 {
                transientRetries += 1
                usleep(1000)
            } else {
                return false
            }
        }
        return true
    }
}

/// Stops with a plain explanation: a headline, then what happened and what to do, indented.
func fail(_ message: String, headline: String = "nospeaker can't play on this Mac.", code: Int32 = 1) -> Never {
    stopRenderer()
    restoreTerminal()
    fdGuard.unsilence()
    stopTouch()
    motorRuntime.closeMotor()
    let safeHeadline = sanitizeTerminal(headline, maxBytes: 256)
    let body = message
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map { "  " + sanitizeTerminal(String($0), maxBytes: 256) }
        .joined(separator: "\n")
    _ = writeAll(STDERR_FILENO, "\n  " + safeHeadline + "\n\n" + body + "\n\n")
    exit(code)
}
/// A mistake in how it was run: says what's wrong and points at --help.
func usageError(_ message: String) -> Never {
    fail(message + "\nSee nospeaker --help for the options.", headline: "nospeaker didn't understand that.", code: 64)
}

// MARK: - The haptic motor (MultitouchSupport, resolved at run time)

typealias CreateList = @convention(c) () -> Unmanaged<CFArray>?
typealias GetID = @convention(c) (UnsafeMutableRawPointer, UnsafeMutablePointer<UInt64>) -> Int32
typealias IsBuiltIn = @convention(c) (UnsafeMutableRawPointer) -> Bool
typealias ActuatorCreate = @convention(c) (UInt64) -> Unmanaged<CFTypeRef>?
typealias ActuatorOpen = @convention(c) (CFTypeRef) -> Int32
typealias ActuatorClose = @convention(c) (CFTypeRef) -> Int32
typealias ActuationCreate = @convention(c) (CFDictionary, Int32) -> Unmanaged<CFTypeRef>?
typealias ActuationPlay = @convention(c) (CFTypeRef, CFTypeRef, UInt32, Float, Float) -> Int32
typealias FrameCallback = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32
typealias RegisterCallback = @convention(c) (UnsafeMutableRawPointer, FrameCallback) -> Void
typealias DeviceStart = @convention(c) (UnsafeMutableRawPointer, Int32) -> Void
typealias DeviceStop = @convention(c) (UnsafeMutableRawPointer) -> Void

struct MultitouchAPI: @unchecked Sendable {
    let handle: UnsafeMutableRawPointer?
    let createList: CreateList?
    let getID: GetID?
    let isBuiltIn: IsBuiltIn?
    let actuatorCreate: ActuatorCreate?
    let actuatorOpen: ActuatorOpen?
    let actuatorClose: ActuatorClose?
    let actuationCreate: ActuationCreate?
    let actuationPlay: ActuationPlay?
    let registerCallback: RegisterCallback?
    let unregisterCallback: RegisterCallback?
    let deviceStart: DeviceStart?
    let deviceStop: DeviceStop?

    init() {
        let h = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW)
        self.handle = h
        func resolve<T>(_ name: String, _: T.Type) -> T? {
            guard let h, let p = dlsym(h, name) else { return nil }
            return unsafeBitCast(p, to: T.self)
        }
        self.createList = resolve("MTDeviceCreateList", CreateList.self)
        self.getID = resolve("MTDeviceGetDeviceID", GetID.self)
        self.isBuiltIn = resolve("MTDeviceIsBuiltIn", IsBuiltIn.self)
        self.actuatorCreate = resolve("MTActuatorCreateFromDeviceID", ActuatorCreate.self)
        self.actuatorOpen = resolve("MTActuatorOpen", ActuatorOpen.self)
        self.actuatorClose = resolve("MTActuatorClose", ActuatorClose.self)
        self.actuationCreate = resolve("MTActuationCreateFromDictionary", ActuationCreate.self)
        self.actuationPlay = resolve("MTActuationActuate", ActuationPlay.self)
        self.registerCallback = resolve("MTRegisterContactFrameCallback", RegisterCallback.self)
        self.unregisterCallback = resolve("MTUnregisterContactFrameCallback", RegisterCallback.self)
        self.deviceStart = resolve("MTDeviceStart", DeviceStart.self)
        self.deviceStop = resolve("MTDeviceStop", DeviceStop.self)
    }
}

let mtAPI = MultitouchAPI()

/// The Mac's model identifier, like "MacBookPro18,3" or "Mac14,3", read with a NUL-guarded buffer.
func macModel() -> String {
    var size = 0
    guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0, size <= 256 else {
        return ""
    }
    var buf = [UInt8](repeating: 0, count: size + 1)
    var outSize = size
    let rc = buf.withUnsafeMutableBytes { raw -> Int32 in
        guard let base = raw.baseAddress else { return -1 }
        return sysctlbyname("hw.model", base, &outSize, nil, 0)
    }
    guard rc == 0 else { return "" }
    let prefix = buf.prefix(while: { $0 != 0 })
    return sanitizeTerminal(String(decoding: prefix, as: UTF8.self), maxBytes: 128)
}

func hasSmartBattery() -> Bool {
    let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
    guard svc != IO_OBJECT_NULL else { return false }
    IOObjectRelease(svc)
    return true
}

let isLaptop = macModel().hasPrefix("MacBook") || hasSmartBattery()

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

/// Total IEEE-754 finite clamp (`NaN -> fallback`, `-Inf/<=lo -> lo`, `+Inf/>=hi -> hi`).
@inline(__always)
func clampFinite(_ x: Double, lo: Double, hi: Double, fallback: Double) -> Double {
    if x.isNaN { return fallback }
    if x <= lo { return lo }
    if x >= hi { return hi }
    return x
}

@inline(__always)
func clampFinite32(_ x: Float, lo: Float, hi: Float, fallback: Float) -> Float {
    if x.isNaN { return fallback }
    if x <= lo { return lo }
    if x >= hi { return hi }
    return x
}

/// EWMA Thermal RC Governor (`T_{k+1} = alpha * T_k + (1 - alpha) * P_k`, `alpha = 0.98`)
/// inductively preserving `0 <= thermalState <= maxThermalEnvelope` (`0.70`) across all trajectories.
struct ThermalDutyGovernor: Sendable {
    let alpha: Double = 0.98
    let maxThermalEnvelope: Double = 0.70
    private(set) var thermalState: Double = 0.0
    private var lastStepTime: Double = -1.0

    mutating func admitLevel(_ requested: Float, at time: Double) -> Float {
        if lastStepTime >= 0, time > lastStepTime {
            let idleSteps = min(250, max(0, Int(((time - lastStepTime) / 0.02).rounded(.down))))
            if idleSteps > 0 {
                thermalState = max(0.0, thermalState * pow(alpha, Double(idleSteps)))
            }
        }
        lastStepTime = max(lastStepTime, time)
        let req = Double(clampFinite32(requested, lo: 0.0, hi: 1.0, fallback: 0.0))
        let budget = max(0.0, (maxThermalEnvelope - alpha * thermalState) / (1.0 - alpha))
        let admitted = min(req, min(1.0, budget))
        thermalState = min(maxThermalEnvelope, max(0.0, alpha * thermalState + (1.0 - alpha) * admitted))
        return Float(admitted)
    }
}

final class MotorRuntime: @unchecked Sendable {
    struct State {
        var deviceCount = 0
        var motorDeviceID: UInt64 = 0
        var motorBuiltIn = false
        var deviceList: CFArray?
        var motor: CFTypeRef?
        var touchActive = false
        var governor = ThermalDutyGovernor()
    }
    private let state = HeapUnfairLock(State())

    var motorBuiltIn: Bool { state.withLock { $0.motorBuiltIn } }

    func admitThermalLevel(_ requested: Float, at time: Double) -> Float {
        state.withLock { $0.governor.admitLevel(requested, at: time) }
    }

    func open() {
        guard let createList = mtAPI.createList,
              let getID = mtAPI.getID,
              let actuatorCreate = mtAPI.actuatorCreate,
              let actuatorOpen = mtAPI.actuatorOpen,
              mtAPI.actuationCreate != nil,
              mtAPI.actuationPlay != nil else {
            fail("This version of macOS doesn't have the trackpad functions this needs. It was made for macOS 12 to 27.")
        }
        guard let list = createList()?.takeRetainedValue(), CFArrayGetCount(list) > 0 else {
            noTrackpad(false)
        }
        var ids: [(id: UInt64, builtIn: Bool)] = []
        for i in 0..<CFArrayGetCount(list) {
            guard let raw = CFArrayGetValueAtIndex(list, i) else { continue }
            let dev = UnsafeMutableRawPointer(mutating: raw)
            var id: UInt64 = 0
            if getID(dev, &id) == 0 {
                ids.append((id, mtAPI.isBuiltIn?(dev) ?? false))
            }
        }
        for d in ids.sorted(by: { $0.builtIn && !$1.builtIn }) {
            if let ref = actuatorCreate(d.id)?.takeRetainedValue(), actuatorOpen(ref) == 0 {
                state.withLock { s in
                    s.deviceList = list
                    s.deviceCount = ids.count
                    s.motorDeviceID = d.id
                    s.motorBuiltIn = d.builtIn
                    s.motor = ref
                }
                return
            }
        }
        noTrackpad(true)
    }

    func activeMotor() -> CFTypeRef? {
        state.withLock { $0.motor }
    }

    func matchingTouchDevices() -> [UnsafeMutableRawPointer] {
        state.withLock { s in
            guard let list = s.deviceList, let getID = mtAPI.getID else { return [] }
            let wanted = s.motorDeviceID
            return (0..<CFArrayGetCount(list)).compactMap { i -> UnsafeMutableRawPointer? in
                guard let raw = CFArrayGetValueAtIndex(list, i) else { return nil }
                let dev = UnsafeMutableRawPointer(mutating: raw)
                var id: UInt64 = 0
                return getID(dev, &id) == 0 && id == wanted ? dev : nil
            }
        }
    }

    func setTouchActive(_ active: Bool) -> Bool {
        state.withLock { s in
            let prev = s.touchActive
            s.touchActive = active
            return prev
        }
    }

    func closeMotor() {
        let oldMotor: CFTypeRef? = state.withLock { s in
            let m = s.motor
            s.motor = nil
            s.deviceList = nil
            return m
        }
        if let oldMotor {
            _ = mtAPI.actuatorClose?(oldMotor)
        }
    }
}

let motorRuntime = MotorRuntime()

/// Plays tones (Hz, relative strength) together for `ms` at overall `level` (0…1).
/// Enforces non-negative NaN-free simplex normalization (`sum(amp) <= 1`), physical frequency
/// confinement (`[80, 4200] Hz`), duration confinement (`[1, 80] ms`), and EWMA thermal governing.
func play(_ tones: [(hz: Double, amp: Double)], ms: Double, level: Float) {
    guard let motor = motorRuntime.activeMotor(),
          let actuationCreate = mtAPI.actuationCreate,
          let actuationPlay = mtAPI.actuationPlay,
          !tones.isEmpty else { return }

    let sanitized: [(hz: Double, amp: Double)] = tones.prefix(6).map { t in
        (
            hz: clampFinite(t.hz, lo: 80.0, hi: 4200.0, fallback: 440.0),
            amp: clampFinite(t.amp, lo: 0.0, hi: 1000.0, fallback: 0.0)
        )
    }
    let sum = sanitized.reduce(0.0) { $0 + $1.amp }
    guard sum > 0.0 else { return }
    let denom = sum > 0.0001 ? sum : 0.0001
    let safeMS = clampFinite(ms, lo: 1.0, hi: 80.0, fallback: 10.0)
    let playTime = now()
    let admittedLevel = motorRuntime.admitThermalLevel(level, at: playTime)

    let shape: [String: Any] = [
        "BaseWaveform": ["Type": "Gaussian", "Amplitude": 0.0, "DurationMS": safeMS],
        "Tones": sanitized.map { t in
            let normAmp = clampFinite(t.amp / denom, lo: 0.0, hi: 1.0, fallback: 0.0)
            return [
                "Type": "Sine",
                "Amplitude": normAmp,
                "DurationMS": safeMS,
                "DelayMS": 0.0,
                "FrequencykHz": t.hz / 1000.0,
            ]
        },
    ]
    // Balanced CoreFoundation Create-rule ownership via ARC (`takeRetainedValue()`).
    guard let act = actuationCreate(shape as CFDictionary, 0)?.takeRetainedValue() else { return }
    _ = withExtendedLifetime(motor) {
        actuationPlay(act, motor, 0, admittedLevel, 0)
    }
    let first = sanitized[0].hz
    live {
        if $0.actuations < Int.max { $0.actuations += 1 }
        $0.hz = first
        $0.level = Double(admittedLevel)
        $0.lastPlay = playTime
    }
}

// MARK: - The first line

/// Its first words: "Good afternoon. I'm your trackpad. I don't have a speaker. I've been meaning to say something."
/// The greeting follows the clock; the rest is the line.
func greetingLine() -> String {
    let hour = Calendar.current.component(.hour, from: Date())
    let hello = hour < 5 ? "You're up late." : hour < 12 ? "Good morning." : hour < 17 ? "Good afternoon." : hour < 22 ? "Good evening." : "You're up late."
    return "\(hello) I'm your trackpad. I don't have a speaker. I've been meaning to say something."
}

// MARK: - Speakers (are they muted? the proof)

/// True when the Mac's default output is muted or at zero volume; nil if it can't tell.
func speakersMuted() -> Bool? {
    var device = AudioDeviceID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                          mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &device) == noErr,
          size == UInt32(MemoryLayout<AudioDeviceID>.size),
          device != kAudioObjectUnknown else { return nil }

    var known = false

    func readMute(_ element: AudioObjectPropertyElement) -> Bool? {
        var muted: UInt32 = 0
        var sz = UInt32(MemoryLayout<UInt32>.size)
        var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                           mScope: kAudioObjectPropertyScopeOutput, mElement: element)
        guard AudioObjectHasProperty(device, &a),
              AudioObjectGetPropertyData(device, &a, 0, nil, &sz, &muted) == noErr,
              sz == UInt32(MemoryLayout<UInt32>.size) else { return nil }
        return muted != 0
    }

    if let masterMuted = readMute(kAudioObjectPropertyElementMain) {
        known = true
        if masterMuted { return true }
    } else {
        let chMutes = [AudioObjectPropertyElement(1), AudioObjectPropertyElement(2)].compactMap(readMute)
        if !chMutes.isEmpty {
            known = true
            if chMutes.allSatisfy({ $0 }) { return true }
        }
    }

    func readVolume(_ element: AudioObjectPropertyElement) -> Float32? {
        var volume: Float32 = 1
        var sz = UInt32(MemoryLayout<Float32>.size)
        var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                                           mScope: kAudioObjectPropertyScopeOutput, mElement: element)
        guard AudioObjectHasProperty(device, &a),
              AudioObjectGetPropertyData(device, &a, 0, nil, &sz, &volume) == noErr,
              sz == UInt32(MemoryLayout<Float32>.size),
              volume.isFinite else { return nil }
        return volume
    }

    if let masterVol = readVolume(kAudioObjectPropertyElementMain) {
        return masterVol < 0.001
    }
    let chVols = [AudioObjectPropertyElement(1), AudioObjectPropertyElement(2)].compactMap(readVolume)
    if !chVols.isEmpty {
        return chVols.allSatisfy { $0 < 0.001 }
    }
    return known ? false : nil
}

// MARK: - Touch (for "play it")

struct Contact: Sendable {
    var down = false
    var x: Float = 0.5
    var y: Float = 0.5
    var size: Float = 0.0
}

let touchState = HeapUnfairLock(Contact())
func currentContact() -> Contact { touchState.withLock { $0 } }

func onTouchFrame(
    _: UnsafeMutableRawPointer?,
    _ data: UnsafeMutableRawPointer?,
    _ count: Int32,
    _: Double,
    _: Int32
) -> Int32 {
    var best = Contact()
    if let data, count > 0, count <= 32, Int(bitPattern: data) % 4 == 0 {
        let rawBase = UnsafeRawPointer(data)
        // Inspect at most 4 contacts: for all count >= 1 and idx < min(count, 4),
        // idx * 96 + 52 <= count * 88, preventing OOB reads even on 88-byte MTTouch layouts.
        let limit = min(Int(count), 4)
        for i in 0..<limit {
            let rec = rawBase.advanced(by: i * 96)
            let state = rec.loadUnaligned(fromByteOffset: 20, as: Int32.self)
            guard (3...5).contains(state) else { continue }
            let rawX = rec.loadUnaligned(fromByteOffset: 32, as: Float.self)
            let rawY = rec.loadUnaligned(fromByteOffset: 36, as: Float.self)
            let rawSize = rec.loadUnaligned(fromByteOffset: 48, as: Float.self)
            guard rawX.isFinite, rawY.isFinite, rawSize.isFinite,
                  rawX >= -0.25, rawX <= 1.25,
                  rawY >= -0.25, rawY <= 1.25,
                  rawSize >= 0.0, rawSize <= 10.0 else { continue }
            best = Contact(
                down: true,
                x: min(1.0, max(0.0, rawX)),
                y: min(1.0, max(0.0, rawY)),
                size: min(4.0, max(0.0, rawSize))
            )
        }
    }
    touchState.withLock { $0 = best }
    return 0
}

func startTouch() -> Bool {
    guard let registerCallback = mtAPI.registerCallback, let deviceStart = mtAPI.deviceStart else { return false }
    let devs = motorRuntime.matchingTouchDevices()
    guard !devs.isEmpty else { return false }
    _ = motorRuntime.setTouchActive(true)
    let quiet = !terminalController.isTaken
    if quiet { fdGuard.silence() }
    for d in devs { registerCallback(d, onTouchFrame); deviceStart(d, 0) }
    if quiet { usleep(200_000); fdGuard.unsilence() }
    return true
}

func stopTouch() {
    guard motorRuntime.setTouchActive(false) else { return }
    for d in motorRuntime.matchingTouchDevices() {
        mtAPI.unregisterCallback?(d, onTouchFrame)
        mtAPI.deviceStop?(d)
    }
    touchState.withLock { $0 = Contact() }
}

// MARK: - Speech analysis

struct Frame: Sendable {
    var formants: [Double] = [500, 1500, 2500]
    var amps: [Double] = [1, 0.5, 0.25]
    var level: Float = 0
    var voiced = false
    var f0 = 110.0
}

struct AppConfig: Sendable {
    var voiceName: String?
}

let hop = 0.010
let defaultSampleRate = 16000.0
let maxAllowedAudioFrames: Int64 = 1_440_000   // 30 s @ 48 kHz (<= 5.76 MiB Float32, safe for UInt32)
let maxSpeechInputBytes = 512
let appConfig = HeapUnfairLock(AppConfig())

/// Strict allowlist check for voice names (`[A-Za-z0-9 _()-]{1,64}` or Unicode letters/marks, never starting with `-`).
func isValidVoiceToken(_ voice: String) -> Bool {
    guard !voice.isEmpty, voice.utf8.count <= 64, !voice.hasPrefix("-") else { return false }
    return voice.unicodeScalars.allSatisfy { s in
        if s.value < 0x20 || (s.value >= 0x7F && s.value <= 0x9F) { return false }
        if CharacterSet.letters.contains(s)
            || CharacterSet.decimalDigits.contains(s)
            || CharacterSet.nonBaseCharacters.contains(s) {
            return true
        }
        return s == " " || s == "_" || s == "-" || s == "(" || s == ")"
    }
}

/// Neutralizes Apple Speech Synthesis Embedded Commands (`[[slnc ...]]`, `[[inpt ...]]`)
/// and control characters, folding common typographic quotes/dashes to ASCII and keeping
/// strictly printable ASCII excluding `[` (91) and `]` (93), capped at 512 bytes.
func sanitizeSpeechText(_ raw: String) -> Data {
    var clean: [UInt8] = []
    clean.reserveCapacity(min(raw.utf8.count, maxSpeechInputBytes))
    for scalar in raw.unicodeScalars {
        let mapped: UInt8?
        switch scalar.value {
        case 0x2018, 0x2019: mapped = 0x27 // '‘', '’' -> '\''
        case 0x201C, 0x201D: mapped = 0x22 // '“', '”' -> '"'
        case 0x2013, 0x2014: mapped = 0x2D // '–', '—' -> '-'
        case 0x20...0x7E where scalar.value != 91 && scalar.value != 93:
            mapped = UInt8(scalar.value)
        default:
            mapped = nil
        }
        if let b = mapped {
            clean.append(b)
            if clean.count >= maxSpeechInputBytes { break }
        }
    }
    return Data(clean)
}

/// Parses the exact voice name column from a `say -v '?'` output line (`<Voice Name> <locale> # <sample>`),
/// preventing partial prefix collisions (e.g. `"Bad"` vs `"Bad News"`) and comment/locale matching.
func extractVoiceNameFromSayLine(_ line: Substring) -> String? {
    let beforeComment = line.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
    let trimmed = beforeComment.trimmingCharacters(in: CharacterSet(charactersIn: " \t\r"))
    guard !trimmed.isEmpty else { return nil }
    guard let splitIdx = trimmed.lastIndex(where: { $0 == " " || $0 == "\t" }) else { return nil }
    let localeToken = trimmed[trimmed.index(after: splitIdx)...]
    let voicePart = trimmed[..<splitIdx].trimmingCharacters(in: CharacterSet(charactersIn: " \t"))
    guard !voicePart.isEmpty, localeToken.count >= 4, localeToken.count <= 12,
          localeToken.contains(where: { $0 == "_" || $0 == "-" }),
          localeToken.unicodeScalars.allSatisfy({
              CharacterSet.alphanumerics.contains($0) || $0 == "_" || $0 == "-"
          }) else { return nil }
    return voicePart
}

/// True if `say` has a voice by this exact name. Fails closed on invalid tokens, launch errors, or timeouts.
/// Drains stdout via non-blocking `poll`+`read` under a strict 5.0 s monotonic deadline so a hung child
/// holding stdout open can never stall the process prior to `exitSem.wait`.
func voiceExists(_ name: String) -> Bool {
    guard isValidVoiceToken(name) else { return false }
    let p = Process(), pipe = Pipe()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/say")
    p.arguments = ["-v", "?"]
    p.standardInput = FileHandle.nullDevice
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    let exitSem = DispatchSemaphore(value: 0)
    p.terminationHandler = { _ in exitSem.signal() }
    guard (try? p.run()) != nil else { return false }

    let readFD = pipe.fileHandleForReading.fileDescriptor
    let fl = fcntl(readFD, F_GETFL)
    if fl >= 0 { _ = fcntl(readFD, F_SETFL, fl | O_NONBLOCK) }

    let deadline = now() + 5.0
    var collected: [UInt8] = []
    collected.reserveCapacity(8192)
    var chunk = [UInt8](repeating: 0, count: 4096)
    var sawEOF = false
    var timedOutOrAborted = false

    while !sawEOF && collected.count < 262_144 {
        if runControl.stopRequested {
            timedOutOrAborted = true
            break
        }
        let rem = deadline - now()
        if rem <= 0 {
            timedOutOrAborted = true
            break
        }
        var pfd = pollfd(fd: readFD, events: Int16(POLLIN | POLLHUP), revents: 0)
        let waitMs = Int32(max(1.0, min(100.0, rem * 1000.0)))
        let pr = Darwin.poll(&pfd, 1, waitMs)
        if pr < 0 {
            if errno == EINTR { continue }
            break
        }
        if pr == 0 { continue }
        let n = chunk.withUnsafeMutableBytes { raw -> Int in
            guard let base = raw.baseAddress else { return -1 }
            return Darwin.read(readFD, base, raw.count)
        }
        if n > 0 {
            let room = 262_144 - collected.count
            collected.append(contentsOf: chunk.prefix(min(n, room)))
        } else if n == 0 {
            sawEOF = true
        } else if errno != EINTR && errno != EAGAIN && errno != EWOULDBLOCK {
            break
        }
    }
    try? pipe.fileHandleForReading.close()

    let remExit = max(0.0, deadline - now())
    if timedOutOrAborted || exitSem.wait(timeout: .now() + remExit) == .timedOut {
        p.terminate()
        if exitSem.wait(timeout: .now() + 0.5) == .timedOut { kill(p.processIdentifier, SIGKILL) }
        p.waitUntilExit()
        return false
    }
    p.waitUntilExit()
    guard p.terminationReason == .exit, p.terminationStatus == 0,
          let list = String(bytes: collected, encoding: .utf8) else { return false }
    return list.split(separator: "\n").contains { line in
        guard let candidate = extractVoiceNameFromSayLine(line) else { return false }
        return candidate.caseInsensitiveCompare(name) == .orderedSame
    }
}

func render(_ text: String) -> [Frame] {
    if runControl.shouldSkipToCredits || runControl.stopRequested { return [] }
    let payload = sanitizeSpeechText(text)
    guard payload.contains(where: { $0 != 0x20 }) else { return [] }
    let configuredVoice = appConfig.withLock { $0.voiceName }
    if let v = configuredVoice, !isValidVoiceToken(v) {
        let safeV = sanitizeTerminal(v, maxBytes: 64)
        fail("There's no voice called \"\(safeV)\" on this Mac.\nList the voices you have with: say -v '?'", headline: "nospeaker can't use that voice.", code: 64)
    }

    // Create an exclusive 0700 directory via mkdtemp so temp paths cannot be hijacked via symlinks/TOCTOU.
    let rawTmp = NSTemporaryDirectory()
    let baseDir: String
    if rawTmp.hasPrefix("/"), rawTmp.utf8.count <= 400 {
        baseDir = rawTmp.hasSuffix("/") ? rawTmp : (rawTmp + "/")
    } else {
        baseDir = "/tmp/"
    }
    var template = Array((baseDir + "nospeaker.XXXXXXXX").utf8CString)
    let created = template.withUnsafeMutableBufferPointer { buf -> Bool in
        guard let base = buf.baseAddress else { return false }
        return mkdtemp(base) != nil
    }
    guard created else {
        if runControl.shouldSkipToCredits || runControl.stopRequested { return [] }
        fail("It couldn't create a private temporary directory for speech synthesis.")
    }
    let dirPath = template.withUnsafeBufferPointer { buf in
        let bytes = buf.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
    let dirURL = URL(fileURLWithPath: dirPath, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: dirURL) }

    var dirStat = stat()
    guard lstat(dirPath, &dirStat) == 0,
          (dirStat.st_mode & S_IFMT) == S_IFDIR,
          dirStat.st_uid == geteuid(),
          (dirStat.st_mode & 0o077) == 0 else {
        if runControl.shouldSkipToCredits || runControl.stopRequested { return [] }
        fail("Temporary directory ownership or permission verification failed.")
    }

    let url = dirURL.appendingPathComponent("speech.wav", isDirectory: false)
    var staticArgs = ["-o", url.path, "--file-format=WAVE", "--data-format=LEF32@16000"]
    if let v = configuredVoice { staticArgs += ["-v", v] }
    staticArgs += ["-f", "-"]

    let p = Process()
    let stdinPipe = Pipe()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/say")
    p.arguments = staticArgs
    p.standardInput = stdinPipe
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice

    let exitSem = DispatchSemaphore(value: 0)
    p.terminationHandler = { _ in exitSem.signal() }
    do {
        try p.run()
    } catch {
        if runControl.shouldSkipToCredits || runControl.stopRequested { return [] }
        fail("It couldn't run macOS's voice (/usr/bin/say), which it needs to talk.")
    }

    _ = fcntl(stdinPipe.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
    try? stdinPipe.fileHandleForWriting.write(contentsOf: payload)
    try? stdinPipe.fileHandleForWriting.close()

    let synthDeadline = now() + 15.0
    var synthExited = false
    var synthTimedOut = false
    while !synthExited {
        if runControl.shouldSkipToCredits || runControl.stopRequested {
            p.terminate()
            if exitSem.wait(timeout: .now() + 0.2) == .timedOut { kill(p.processIdentifier, SIGKILL) }
            p.waitUntilExit()
            return []
        }
        let rem = synthDeadline - now()
        if rem <= 0 {
            synthTimedOut = true
            break
        }
        if exitSem.wait(timeout: .now() + min(0.05, rem)) == .success {
            synthExited = true
        }
    }
    if synthTimedOut {
        p.terminate()
        if exitSem.wait(timeout: .now() + 0.5) == .timedOut { kill(p.processIdentifier, SIGKILL) }
        p.waitUntilExit()
        if runControl.shouldSkipToCredits || runControl.stopRequested { return [] }
        fail("macOS's voice (/usr/bin/say) took too long to prepare that line.", headline: "nospeaker couldn't prepare its voice.")
    }
    p.waitUntilExit()

    // Handle foreground process-group signal delivery (e.g. Ctrl-C killing child `/usr/bin/say`
    // concurrently with or slightly ahead of SignalWatcher draining `signalPipe`).
    if p.terminationReason == .uncaughtSignal {
        let sig = p.terminationStatus
        if sig == SIGINT {
            usleep(10_000)
            if !runControl.shouldSkipToCredits && !runControl.stopRequested {
                runControl.requestEnd()
            }
            return []
        } else if sig == SIGTERM || sig == SIGHUP || sig == SIGQUIT {
            runControl.requestHardStop()
            return []
        }
    }
    if runControl.shouldSkipToCredits || runControl.stopRequested { return [] }

    var wavStat = stat()
    let validFile = p.terminationReason == .exit
        && p.terminationStatus == 0
        && lstat(url.path, &wavStat) == 0
        && (wavStat.st_mode & S_IFMT) == S_IFREG
        && wavStat.st_nlink == 1
        && wavStat.st_uid == geteuid()
        && wavStat.st_size > 0
        && wavStat.st_size <= 24 * 1024 * 1024

    guard validFile,
          let file = try? AVAudioFile(forReading: url),
          file.length >= 0,
          file.length <= maxAllowedAudioFrames else {
        if runControl.shouldSkipToCredits || runControl.stopRequested { return [] }
        if let configuredVoice {
            let safeV = sanitizeTerminal(configuredVoice, maxBytes: 64)
            fail("There's no voice called \"\(safeV)\" on this Mac.\nList the voices you have with: say -v '?'", headline: "nospeaker can't use that voice.")
        }
        fail("macOS's voice (say) couldn't speak that line.", headline: "nospeaker couldn't prepare its voice.")
    }
    if file.length == 0 { return [] }
    let format = file.processingFormat
    let actualSampleRate = format.sampleRate
    guard actualSampleRate.isFinite, actualSampleRate >= 8000, actualSampleRate <= 96000,
          format.channelCount >= 1,
          let frameCap = UInt32(exactly: file.length),
          let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCap)),
          (try? file.read(into: buf)) != nil,
          let ch = buf.floatChannelData?[0] else {
        if runControl.shouldSkipToCredits || runControl.stopRequested { return [] }
        fail("macOS's voice (say) produced unreadable audio.", headline: "nospeaker couldn't prepare its voice.")
    }
    var f = analyse(Array(UnsafeBufferPointer(start: ch, count: Int(buf.frameLength))), sampleRate: actualSampleRate)
    while let first = f.first, first.level == 0 { f.removeFirst() }
    while let last = f.last, last.level == 0 { f.removeLast() }
    return f
}

func lpc(_ x: [Double], order p: Int) -> ([Double], Double) {
    guard p >= 1 else { return ([1.0], 0.0) }
    var a = [Double](repeating: 0, count: p + 1); a[0] = 1
    guard x.count > p else { return (a, 0.0) }
    var r = [Double](repeating: 0, count: p + 1)
    for k in 0...p {
        var s = 0.0
        for i in k..<x.count { s += x[i] * x[i - k] }
        guard s.isFinite else { return (a, 0.0) }
        r[k] = s
    }
    guard r[0] > 1e-12 else { return (a, 0.0) }
    r[0] *= 1.0001
    var e = r[0]
    for i in 1...p {
        guard e.isFinite, e > 1e-12 else { break }
        var acc = r[i]
        for j in 1..<i { acc += a[j] * r[i - j] }
        let k = -acc / e
        // Schur reflection stability guard: |k| < 1 ensures e' = e * (1 - k^2) > 0
        // and keeps all predictor roots strictly inside the unit circle.
        guard k.isFinite, abs(k) < 0.999999 else { break }
        var na = a
        for j in 1..<i { na[j] = a[j] + k * a[i - j] }
        na[i] = k
        a = na
        e *= (1.0 - k * k)
    }
    return (a, (e.isFinite && e > 1e-12) ? e : 0.0)
}

struct C: Sendable {
    var re: Double, im: Double
    static func + (l: C, r: C) -> C { C(re: l.re + r.re, im: l.im + r.im) }
    static func - (l: C, r: C) -> C { C(re: l.re - r.re, im: l.im - r.im) }
    static func * (l: C, r: C) -> C { C(re: l.re * r.re - l.im * r.im, im: l.re * r.im + l.im * r.re) }
    /// Smith's scaled complex division: eliminates `r.re^2 + r.im^2` IEEE-754 Float64 underflow (`0/0 = NaN`).
    static func / (l: C, r: C) -> C {
        let are = abs(r.re), aim = abs(r.im)
        if are.isNaN || aim.isNaN || (are < 1e-300 && aim < 1e-300) {
            return C(re: 0.0, im: 0.0)
        }
        if are >= aim {
            let ratio = r.im / r.re
            let denom = r.re + r.im * ratio
            return C(re: (l.re + l.im * ratio) / denom, im: (l.im - l.re * ratio) / denom)
        } else {
            let ratio = r.re / r.im
            let denom = r.im + r.re * ratio
            return C(re: (l.re * ratio + l.im) / denom, im: (l.im * ratio - l.re) / denom)
        }
    }
}

func roots(_ a: [Double]) -> [C] {
    let p = a.count - 1
    guard p >= 1, a.allSatisfy(\.isFinite) else { return [] }
    var z = (0..<p).map { k -> C in
        let ang = 2 * Double.pi * Double(k) / Double(p) + 0.4
        return C(re: 0.9 * cos(ang), im: 0.9 * sin(ang))
    }
    func poly(_ x: C) -> C { var s = C(re: 1, im: 0); for k in 1...p { s = s * x + C(re: a[k], im: 0) }; return s }
    for _ in 0..<300 {
        var moved = 0.0
        var aborted = false
        for i in 0..<p {
            var d = C(re: 1, im: 0)
            for j in 0..<p where j != i { d = d * (z[i] - z[j]) }
            if !d.re.isFinite || !d.im.isFinite || (abs(d.re) < 1e-30 && abs(d.im) < 1e-30) {
                d = C(re: 1e-12, im: 0)
            }
            let num = poly(z[i])
            guard num.re.isFinite, num.im.isFinite else { aborted = true; break }
            let step = num / d
            guard step.re.isFinite, step.im.isFinite else { aborted = true; break }
            let nextZ = z[i] - step
            guard nextZ.re.isFinite, nextZ.im.isFinite else { aborted = true; break }
            let mag = hypot(nextZ.re, nextZ.im)
            z[i] = mag > 4.0 ? C(re: nextZ.re * (4.0 / mag), im: nextZ.im * (4.0 / mag)) : nextZ
            moved = max(moved, abs(step.re) + abs(step.im))
        }
        if aborted || moved < 1e-10 { break }
    }
    return z
}

func analyse(_ x: [Float], sampleRate: Double = defaultSampleRate) -> [Frame] {
    let win = max(64, Int((0.025 * sampleRate).rounded())), hopN = max(1, Int((hop * sampleRate).rounded())), order = 18
    guard x.count >= win else { return [] }
    let hamming = (0..<win).map { 0.54 - 0.46 * cos(2 * .pi * Double($0) / Double(win - 1)) }
    var frames: [Frame] = [], rmsList: [Double] = []
    var prev = Frame()
    var prefixSq = [Double](repeating: 0.0, count: win + 1)
    let lagLo = max(1, Int((sampleRate / 300.0).rounded(.down)))
    let lagHi = min(win - 41, Int((sampleRate / 70.0).rounded(.down)))

    var i = 0
    while i + win <= x.count {
        let seg: [Double] = (0..<win).map { offset in
            let v = x[i + offset]
            return v.isFinite ? min(1.0, max(-1.0, Double(v))) : 0.0
        }
        var zc = 0
        prefixSq[0] = 0.0
        for k in 0..<win {
            prefixSq[k + 1] = prefixSq[k] + seg[k] * seg[k]
            if k > 0 && ((seg[k] >= 0) != (seg[k - 1] >= 0)) { zc += 1 }
        }
        let frameEnergy = prefixSq[win]
        rmsList.append(sqrt(max(0.0, frameEnergy) / Double(win)))

        var f = prev
        // Early energy silence gate: skip pitch search, LPC, and 300-iteration Durand-Kerner on silent frames.
        guard frameEnergy > 1e-10 else {
            f.voiced = false
            frames.append(f)
            i += hopN
            continue
        }

        // Prefix-sum O(W + L) normalized autocorrelation pitch estimation (>121x faster energy normalization).
        var bestLag = 0, bestR = 0.0
        if lagLo <= lagHi {
            for lag in lagLo...lagHi {
                let n = win - lag
                let ea = prefixSq[n]
                let eb = frameEnergy - prefixSq[lag]
                var cross = 0.0
                for k in 0..<n { cross += seg[k] * seg[k + lag] }
                let r = cross / max(sqrt(max(0.0, ea * eb)), 1e-12)
                if r.isFinite && r > bestR { bestR = r; bestLag = lag }
            }
        }
        f.voiced = bestR > 0.35 && Double(zc) / Double(win) < 0.22
        if f.voiced, bestLag > 0 { f.f0 = sampleRate / Double(bestLag) }

        var pe = [Double](repeating: 0, count: win)
        for k in 0..<win { pe[k] = (seg[k] - 0.97 * (k > 0 ? seg[k - 1] : 0)) * hamming[k] }
        let (a, err) = lpc(pe, order: order)
        var cands: [Double] = []
        if err > 0 {
            for z in roots(a) where z.re.isFinite && z.im.isFinite && z.im > 0 {
                let rMag = hypot(z.re, z.im)
                guard rMag > 1e-6, rMag < 1.0 else { continue }
                let hz = atan2(z.im, z.re) * sampleRate / (2 * .pi)
                let bw = -log(rMag) * sampleRate / .pi
                if hz.isFinite, bw.isFinite, hz > 150, hz < 4200, bw > 0, bw < 500 {
                    cands.append(hz)
                }
            }
        }
        func pick(_ lo: Double, _ hi: Double, near: Double) -> Double? {
            cands.filter { $0 >= lo && $0 <= hi }.min { abs($0 - near) < abs($1 - near) }
        }
        if let f1 = pick(200, 1000, near: prev.formants[0]) { f.formants[0] = f1 }
        if let f2 = pick(max(f.formants[0] + 200, 650), 2700, near: prev.formants[1]) { f.formants[1] = f2 }
        if let f3 = pick(max(f.formants[1] + 300, 1700), 3900, near: prev.formants[2]) { f.formants[2] = f3 }
        if err > 0 {
            f.amps = f.formants.map { hz in
                let w = 2 * Double.pi * hz / sampleRate
                var re = 0.0, im = 0.0
                for k in 0...order { re += a[k] * cos(w * Double(k)); im -= a[k] * sin(w * Double(k)) }
                let mag = hypot(re, im)
                return mag.isFinite ? clampFinite(1.0 / max(mag, 1e-6), lo: 0.0, hi: 1e6, fallback: 0.5) : 0.5
            }
        }
        frames.append(f)
        prev = f
        i += hopN
    }
    let peak = max(rmsList.filter(\.isFinite).max() ?? 0.0, 1e-9)
    for k in frames.indices {
        let rel = rmsList[k] / peak
        if !rel.isFinite || rel < 0.02 {
            frames[k].level = 0
            frames[k].voiced = false
        } else {
            frames[k].level = Float(clampFinite(pow(rel, 0.45), lo: 0.0, hi: 1.0, fallback: 0.0))
            if frames[k].level == 0 { frames[k].voiced = false }
        }
    }
    func median(_ v: [Double]) -> Double { v.sorted()[v.count / 2] }
    let raw = frames
    for k in frames.indices {
        let lo = max(0, k - 2), hi = min(frames.count - 1, k + 2)
        for j in 0..<3 { frames[k].formants[j] = median((lo...hi).map { raw[$0].formants[j] }) }
        frames[k].f0 = clampFinite(median((lo...hi).map { raw[$0].f0 }), lo: 70.0, hi: 250.0, fallback: 110.0)
    }
    return frames
}

/// A voiced frame as two tones, F1 and F2. Two rather than three: in a blind test two were clearer, and louder,
/// because the motor's strength is split fewer ways.
func voiceTones(_ f: Frame) -> [(hz: Double, amp: Double)] {
    let a0 = clampFinite(f.amps[0], lo: 0.0, hi: 1e6, fallback: 0.5)
    let a1 = clampFinite(f.amps[1] * 1.8, lo: 0.0, hi: 1e6, fallback: 0.5)
    let sum = max(a0 + a1, 1e-9)
    return [(f.formants[0], a0 / sum), (f.formants[1], a1 / sum)]
}

// MARK: - Live state shared with the screen

enum Scene: Sendable { case intro, heart, sweep, talk, sing, beat, rap, yourTurn, touch, say, outro }

struct LiveState: Sendable {
    var scene: Scene = .intro
    var part = 1
    var partName = "LOADING"
    var hz = 0.0, level = 0.0, lastPlay = -9.0
    var f0 = 0.0, f1 = 0.0, f2 = 0.0
    var caption = "", captionStart = 0.0, captionDur = 1.0
    var kick = -9.0, snare = -9.0, hat = -9.0
    var step = -1, bar = 0, bars = 4, bpm = 92.0
    var noteRow = -1, noteName = ""
    var touchSeen = false, touchDown = false, touchX = 0.5, touchY = 0.5, touchEnds = 0.0, touchWaitUntil = 0.0, touchMissed = false
    var waitingForKey = false
    var followOpenedAt = -9.0
    // Say anything: what's being typed, and where it is (typing, preparing, speaking).
    var inputActive = false, inputText = "", inputSubmitted = false, inputDone = false
    var sayStatus = "typing", sayCount = 0
    var muted: Bool? = nil
    var actuations = 0
    var started = 0.0
    var stepDone = 0, stepTotal = 0
}

let liveStore = HeapUnfairLock(LiveState())
func live(_ f: (inout LiveState) -> Void) { liveStore.withLock(f) }
func snapshot() -> LiveState { liveStore.withLock { $0 } }

let partCount = 10
/// Moves the show to a new part: what the screen draws, and the part number and name in the status bar.
func enter(_ scene: Scene, _ part: Int, _ name: String) {
    runControl.setSkipRequested(false)
    live { $0.scene = scene; $0.part = part; $0.partName = name }
}
func caption(_ text: String, seconds: Double) {
    live { $0.caption = text; $0.captionStart = now(); $0.captionDur = seconds }
}

// MARK: - Notes

func hz(_ note: String) -> Double {
    let names: [String: Int] = ["C": -9, "C#": -8, "D": -7, "D#": -6, "E": -5, "F": -4, "F#": -3, "G": -2, "G#": -1, "A": 0, "A#": 1, "B": 2]
    guard let lastChar = note.last,
          let octave = Int(String(lastChar)),
          (-1...9).contains(octave),
          let semi = names[String(note.dropLast())] else { return 440 }
    return 440 * pow(2, Double(semi + (octave - 4) * 12) / 12)
}

// MARK: - The show's parts (sound)

/// A felt-and-heard thump: a fast pitch dive.
func thump(_ amp: Double) {
    let start = mach_absolute_time()
    var t = 0.0
    while t < 0.11 && !runControl.stopRequested {
        let f = 120 + 780 * exp(-t / 0.02)
        let seg = 1 / f
        play([(f, 1)], ms: seg * 1000, level: Float(amp * exp(-t / 0.05)))
        t += seg
        waitUntil(deadlineTicks(from: start, after: t), allowSkip: false)
    }
}

func heartbeat() {
    for _ in 0..<2 where !interrupted() {
        thump(1); pause(0.17); thump(0.7); pause(0.75)
    }
}

func sweep(seconds: Double = 6) {
    guard seconds.isFinite, seconds > 0 else { return }
    let start = mach_absolute_time()
    var t = 0.0
    while t < seconds && !interrupted() {
        let f = 100 * pow(40, t / seconds)
        let seg = max(1, (0.02 * f).rounded()) / f
        play([(f, 1)], ms: seg * 1000, level: 1)
        t += seg
        waitUntil(deadlineTicks(from: start, after: t))
    }
}

func talk(_ frames: [Frame], text: String) {
    guard !frames.isEmpty else { return }
    let total = Double(frames.count) * hop
    caption(text, seconds: total)
    let start = mach_absolute_time()
    var t = 0.0
    while t < total && !interrupted() {
        let idx = max(0, min(frames.count - 1, Int((t / hop).rounded(.down))))
        let f = frames[idx]
        var step = 0.005
        if f.level > 0 {
            if f.voiced && f.f0.isFinite && f.f0 >= 40 {
                step = 1 / f.f0
                play(voiceTones(f), ms: step * 1000, level: f.level)
                live { $0.f0 = f.f0; $0.f1 = f.formants[0]; $0.f2 = f.formants[1] }
            } else {
                step = 0.004
                play((0..<3).map { _ in (Double.random(in: 2700...4300), 1.0) }, ms: step * 1000, level: f.level * 0.7)
            }
        }
        t += step
        waitUntil(deadlineTicks(from: start, after: t))
    }
    live { $0.f0 = 0; $0.f1 = 0; $0.f2 = 0 }
}

/// An original hook in the motor's loudest, cleanest octave, with scoops, glides and vibrato.
let rollNotes = ["C7", "A6", "G6", "E6", "C6", "A5"]
func sing() {
    let beat = 60.0 / 112
    let melody: [(String, Double)] = [("E6", 0.5), ("G6", 0.5), ("A6", 1), ("G6", 0.5), ("E6", 0.5), ("C6", 1),
                                      ("E6", 0.5), ("G6", 0.5), ("A6", 0.5), ("C7", 0.5), ("A6", 1), ("G6", 1),
                                      ("E6", 0.5), ("C6", 0.5), ("A5", 1), ("C6", 0.5), ("E6", 0.5), ("A6", 2.5)]
    let phraseEnds: Set<Int> = [5, 11, 17]
    var previous: Double?
    let start = mach_absolute_time()
    var t = 0.0, at = 0.0
    for (i, (name, beats)) in melody.enumerated() {
        if interrupted() { break }
        let target = hz(name), length = beats * beat
        let sounding = phraseEnds.contains(i) ? length * 0.86 : length
        live { $0.noteRow = rollNotes.firstIndex(of: name) ?? -1; $0.noteName = name }
        let from = previous
        while t < at + sounding && !interrupted() {
            let age = t - at
            var f = target
            if let from, age < 0.045 { f = from * pow(target / from, age / 0.045) }
            else if from == nil, age < 0.04 { f = target * pow(2, -0.6 * (1 - age / 0.04) / 12) }
            if age > 0.2 { f *= pow(2, min(1, (age - 0.2) / 0.25) * 0.22 * sin(2 * .pi * 5.8 * age) / 12) }
            var level = age < 0.015 ? 0.6 + 0.4 * age / 0.015 : 1.0
            if i == melody.count - 1 { level *= max(0, 1 - age / length) }
            let seg = max(1, ((age < 0.06 ? 0.02 : 0.045) * f).rounded()) / f
            play([(f, 1)], ms: min(seg, at + sounding - t + 0.004) * 1000, level: Float(level))
            t += seg
            waitUntil(deadlineTicks(from: start, after: t))
        }
        previous = phraseEnds.contains(i) ? nil : target
        live { $0.noteRow = -1 }
        at += length
        if t < at { t = at; waitUntil(deadlineTicks(from: start, after: t)) }
    }
}

/// Drums, bass and (from `rapBar`) a rapped line, mixed into each actuation. Everything restarts on one
/// carrier period: the bass note, or the voice's own pitch while it raps, so the ear hears that as the low
/// note. While the voice talks, the bass drops out and the drums duck.
func groove(bars: Int, rapBar: Int, rap: [Frame], rapText: String) {
    let bpm = 92.0
    let s16 = 15 / bpm, barLen = 16 * s16
    let kickP = Array("X.........X..x.."), snareP = Array("....X.......X..."), hatP = Array("x.x.x.x.x.x.xxx.")
    let bassHz = [110.0, 87.31, 130.81, 98.0]
    let bassRhythm = Array("x.....x...x.....")
    struct Hit { let t: Double; let kind: Int; let acc: Double }
    var hits: [Hit] = []
    for i in 0..<(bars * 16) {
        for (k, p) in [kickP, snareP, hatP].enumerated() where p[i % 16] != "." {
            hits.append(Hit(t: Double(i) * s16, kind: k, acc: p[i % 16] == "X" ? 1 : 0.65))
        }
    }
    hits.sort { $0.t < $1.t }
    live { $0.bpm = bpm; $0.bars = bars }
    let rapStart = Double(rapBar) * barLen
    let end = Double(bars) * barLen
    var t = 0.0, next = 0, rapping = false
    var ringing: [Hit] = []
    let start = mach_absolute_time()
    while t < end && !runControl.stopRequested {
        if (runControl.skipRequested && !rapping) || runControl.shouldSkipToCredits { break }
        if rapping && runControl.skipRequested { break }
        while next < hits.count, hits[next].t <= t + 0.0005 {
            let h = hits[next]
            ringing.append(h)
            let when = now()
            live { if h.kind == 0 { $0.kick = when } else if h.kind == 1 { $0.snare = when } else { $0.hat = when } }
            next += 1
        }
        ringing.removeAll { t - $0.t > 0.2 }
        let i16 = max(0, Int((t / s16).rounded(.down)))
        live { $0.step = i16 % 16; $0.bar = i16 / 16 }
        if !rapping, t >= rapStart {
            rapping = true
            enter(.rap, 6, "RAP")
            caption(rapText, seconds: Double(rap.count) * hop)
        }
        var frame: Frame?
        if t >= rapStart {
            let idx = max(0, Int(((t - rapStart) / hop).rounded(.down)))
            if idx < rap.count { frame = rap[idx] }
        }
        let talking = (frame?.level ?? 0) > 0
        let bass = bassHz[(i16 / 16) % bassHz.count]
        var carrier = bass
        if let f = frame, talking, f.voiced, f.f0.isFinite, f.f0 >= 40 { carrier = f.f0 }
        var tones: [(hz: Double, amp: Double)] = []
        var step = 1 / carrier
        if let f = frame, talking {
            if f.voiced {
                for v in voiceTones(f) { tones.append((v.hz, Double(f.level) * v.amp)) }
                live { $0.f0 = f.f0; $0.f1 = f.formants[0]; $0.f2 = f.formants[1] }
            } else {
                step = 0.004
                for _ in 0..<2 { tones.append((Double.random(in: 2700...4300), Double(f.level) * 0.4)) }
            }
        } else {
            let pos = i16 % 16
            let lastHit = (0...pos).last { bassRhythm[$0] != "." } ?? 0
            let age = t - Double((i16 / 16) * 16 + lastHit) * s16
            let env = (age < 0.01 ? age / 0.01 : 1) * (0.25 + 0.75 * exp(-age * 7))
            for (target, w) in [(880.0, 0.6), (1320.0, 0.4)] {
                tones.append((max(1, (target / bass).rounded()) * bass, 0.45 * env * w))
            }
        }
        for h in ringing {
            let age = t - h.t
            let duck = talking ? [0.4, 0.25, 0.0][h.kind] : 1.0
            switch h.kind {
            case 0 where age < 0.14:
                tones.append((150 + 850 * exp(-age / 0.018), duck * 0.9 * h.acc * 1.3 * exp(-age / 0.05)))
            case 1 where age < 0.16:
                let e = duck * 0.9 * h.acc * exp(-age / 0.045)
                tones.append((Double.random(in: 1300...3800), e * 0.55))
                tones.append((Double.random(in: 1300...3800), e * 0.45))
            case 2 where age < 0.05 && duck > 0:
                tones.append((3951, 0.9 * h.acc * 0.55 * exp(-age / 0.012)))
            default: break
            }
        }
        if next < hits.count {
            let dt = hits[next].t - t
            if dt > 0.0035, dt < step { step = dt }
        }
        tones.sort { $0.amp > $1.amp }
        let use = Array(tones.prefix(6))
        let total = use.reduce(0) { $0 + $1.amp }
        if total > 0.01 { play(use, ms: step * 1000, level: Float(min(1, total))) }
        t += step
        waitUntil(deadlineTicks(from: start, after: t))
    }
    live { $0.step = -1; $0.f0 = 0; $0.f1 = 0; $0.f2 = 0 }
}

/// Touch to play: the trackpad as an instrument. Slide for pitch (snapped to the motor's cleanest notes, with a
/// glide), move up for more vibrato, press with more of your finger for louder.
func touchToPlay() {
    guard startTouch() else { live { $0.touchMissed = true }; pause(1.5); return }
    defer { stopTouch() }
    live { $0.touchWaitUntil = now() + 8 }
    let waitEnd = now() + 8
    while now() < waitEnd && !interrupted() && !currentContact().down { usleep(5000) }
    guard currentContact().down else { live { $0.touchMissed = true }; pause(1.5); return }
    let endAt = now() + 12
    live { $0.touchSeen = true; $0.touchEnds = endAt }
    let scale = ["G5", "A5", "B5", "C6", "E6", "F6", "G6", "A6", "B6", "C7"].map(hz)
    var current = scale[4]
    var lastDown = false, downAt = 0.0
    while now() < endAt && !interrupted() {
        let c = currentContact()
        let safeX: Float = c.x.isFinite ? min(0.999999, max(0.0, c.x)) : 0.5
        let safeY: Float = c.y.isFinite ? min(1.0, max(0.0, c.y)) : 0.5
        let safeSize: Float = c.size.isFinite ? min(4.0, max(0.0, c.size)) : 0.0
        live {
            $0.touchDown = c.down
            if c.down { $0.touchX = Double(safeX); $0.touchY = Double(safeY) }
        }
        guard c.down else { lastDown = false; usleep(3000); continue }
        if !lastDown { downAt = now() }
        lastDown = true
        let idx = min(scale.count - 1, max(0, Int((Double(safeX) * Double(scale.count)).rounded(.down))))
        let target = scale[idx]
        let nextCur = current * pow(target / current, 0.3)
        current = (nextCur.isFinite && nextCur >= 80 && nextCur <= 4200) ? nextCur : target
        let age = max(0, now() - downAt)
        let depth = 0.05 + 0.45 * Double(safeY)
        let f = current * pow(2, depth * sin(2 * .pi * 6 * age) / 12)
        let level = min(1, max(0.5, 0.3 + Double(safeSize) * 0.8))
        let seg = max(1, (0.02 * f).rounded()) / f
        let stepStart = mach_absolute_time()
        play([(f, 1)], ms: seg * 1000, level: Float(level))
        live { $0.noteName = noteName(f) }
        waitUntil(deadlineTicks(from: stepStart, after: seg))
    }
    live { $0.touchDown = false }
}

func noteName(_ f: Double) -> String {
    guard f.isFinite, f >= 20.0, f <= 20000.0 else { return "-" }
    let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    let midi = Int((69 + 12 * log2(f / 440)).rounded())
    let noteIdx = ((midi % 12) + 12) % 12
    let octave = Int(floor(Double(midi) / 12.0)) - 1
    return names[noteIdx] + String(octave)
}

/// A sparkle to close: an arpeggio up, then the motor's purest note.
func sparkle() {
    for n in ["A5", "C6", "E6", "A6", "C7"] where !runControl.stopRequested {
        let f = hz(n)
        let seg = (0.07 * f).rounded() / f
        let stepStart = mach_absolute_time()
        play([(f, 1)], ms: seg * 1000, level: 0.9)
        waitUntil(deadlineTicks(from: stepStart, after: seg), allowSkip: false)
    }
    let start = mach_absolute_time()
    var t = 0.0
    while t < 0.6 && !runControl.stopRequested {
        let seg = (0.02 * 3951).rounded() / 3951
        play([(3951, 1)], ms: seg * 1000, level: Float(exp(-t / 0.18)))
        t += seg
        waitUntil(deadlineTicks(from: start, after: t), allowSkip: false)
    }
}

/// Lines to try in Say anything, shown one at a time in the empty box. Tab types the one showing.
let saySuggestions = ["can you hear me?", "please stop clicking me", "this is not a speaker", "nobody believes me",
                      "i live under the glass", "hello from the trackpad"]
func saySuggestion(at t: Double) -> String {
    guard t.isFinite, t >= 0 else { return saySuggestions[0] }
    let slot = Int((t / 3.0).truncatingRemainder(dividingBy: Double(saySuggestions.count)))
    return saySuggestions[((slot % saySuggestions.count) + saySuggestions.count) % saySuggestions.count]
}

/// Say anything: you type a line and the trackpad says it. Up to five lines; return on an empty line or esc
/// goes to the credits, and so do 25 seconds without typing.
func sayAnything() {
    for _ in 0..<5 where !runControl.shouldSkipToCredits {
        live { $0.inputActive = true; $0.inputText = ""; $0.inputSubmitted = false; $0.sayStatus = "typing"; $0.caption = "" }
        var lastChange = now(), lastText = ""
        while !runControl.shouldSkipToCredits {
            let st = snapshot()
            if st.inputSubmitted || st.inputDone { break }
            if st.inputText != lastText { lastText = st.inputText; lastChange = now() }
            if now() - lastChange > 25 { live { $0.inputDone = true }; break }
            usleep(20_000)
        }
        let st = snapshot()
        live { $0.inputActive = false }
        let text = st.inputText.trimmingCharacters(in: .whitespaces)
        if st.inputDone || text.isEmpty || runControl.shouldSkipToCredits { break }
        live { $0.sayStatus = "preparing" }
        let frames = render(text)
        if runControl.shouldSkipToCredits { break }
        live { $0.sayStatus = "speaking"; $0.sayCount += 1 }
        talk(frames, text: text)
        pause(0.6)
    }
    live { $0.inputActive = false }
}

// MARK: - Terminal & FD Isolation

/// Idempotent, close-on-exec stdout/stderr `/dev/null` redirection guard.
final class IdempotentFDGuard: Sendable {
    private struct Descriptors {
        var savedOut: Int32 = -1
        var savedErr: Int32 = -1
        var activeOutFD: Int32 = STDOUT_FILENO
    }
    private let state = HeapUnfairLock(Descriptors())

    var renderOutputFD: Int32 { state.withLock { $0.activeOutFD } }

    func silence() {
        state.withLock { d in
            guard d.savedOut < 0 else { return }
            let nullFD = Darwin.open("/dev/null", O_WRONLY | O_CLOEXEC)
            guard nullFD >= 0 else { return }
            let dupOut = fcntl(STDOUT_FILENO, F_DUPFD_CLOEXEC, 0)
            let dupErr = fcntl(STDERR_FILENO, F_DUPFD_CLOEXEC, 0)
            guard dupOut >= 0, dupErr >= 0 else {
                if dupOut >= 0 { close(dupOut) }
                if dupErr >= 0 { close(dupErr) }
                close(nullFD)
                return
            }
            fflush(stdout)
            fflush(stderr)
            guard dup2(nullFD, STDOUT_FILENO) >= 0, dup2(nullFD, STDERR_FILENO) >= 0 else {
                _ = dup2(dupOut, STDOUT_FILENO)
                _ = dup2(dupErr, STDERR_FILENO)
                close(dupOut)
                close(dupErr)
                close(nullFD)
                return
            }
            close(nullFD)
            d.savedOut = dupOut
            d.savedErr = dupErr
            d.activeOutFD = dupOut
        }
    }

    func unsilence() {
        state.withLock { d in
            guard d.savedOut >= 0, d.savedErr >= 0 else { return }
            fflush(stdout)
            fflush(stderr)
            _ = dup2(d.savedOut, STDOUT_FILENO)
            _ = dup2(d.savedErr, STDERR_FILENO)
            close(d.savedOut)
            close(d.savedErr)
            d.savedOut = -1
            d.savedErr = -1
            d.activeOutFD = STDOUT_FILENO
        }
    }
}

let fdGuard = IdempotentFDGuard()

@discardableResult
func out(_ s: String) -> Bool {
    writeAll(fdGuard.renderOutputFD, s)
}

final class TerminalController: Sendable {
    private struct State {
        var savedTermios = termios()
        var termiosSaved = false
        var taken = false
    }
    private let state = HeapUnfairLock(State())
    private let fds: IdempotentFDGuard

    init(fdGuard: IdempotentFDGuard) {
        self.fds = fdGuard
    }

    var isTaken: Bool { state.withLock { $0.taken } }

    private static func getTermios(_ t: inout termios) -> Bool {
        while true {
            let rc = tcgetattr(STDIN_FILENO, &t)
            if rc == 0 { return true }
            if errno != EINTR { return false }
        }
    }

    private static func setTermios(_ t: inout termios) {
        while tcsetattr(STDIN_FILENO, TCSANOW, &t) < 0 && errno == EINTR {}
    }

    func take() {
        let didAcquire = state.withLock { s -> Bool in
            guard !s.taken else { return false }
            s.taken = true
            var orig = termios()
            if Self.getTermios(&orig) {
                s.savedTermios = orig
                s.termiosSaved = true
                var raw = orig
                raw.c_lflag &= ~tcflag_t(ICANON | ECHO)
                withUnsafeMutableBytes(of: &raw.c_cc) { cc in
                    if Int(VMIN) < cc.count { cc[Int(VMIN)] = 1 }
                    if Int(VTIME) < cc.count { cc[Int(VTIME)] = 0 }
                }
                Self.setTermios(&raw)
            } else {
                s.termiosSaved = false
            }
            return true
        }
        guard didAcquire else { return }
        fds.silence()
        _ = out("\u{1B}[?1049h\u{1B}[?25l" + fillScreen())
    }

    func restore() {
        let snapshotState = state.withLock { s -> (wasTaken: Bool, saved: termios, hasTermios: Bool) in
            guard s.taken else { return (false, s.savedTermios, false) }
            s.taken = false
            let hasT = s.termiosSaved
            s.termiosSaved = false
            return (true, s.savedTermios, hasT)
        }
        guard snapshotState.wasTaken else { return }
        _ = out("\u{1B}[0m\u{1B}[2J\u{1B}[?25h\u{1B}[?1049l")
        fds.unsilence()
        if snapshotState.hasTermios {
            var orig = snapshotState.saved
            Self.setTermios(&orig)
        }
    }
}

let terminalController = TerminalController(fdGuard: fdGuard)
func takeTerminal() { terminalController.take() }
func restoreTerminal() { terminalController.restore() }
func onExitRestore() {
    stopRenderer()
    terminalController.restore()
    fdGuard.unsilence()
}

/// Paints the whole terminal in the theme's background (not just the show's 80×24 block), so the show sits
/// centred on one page however big the window is.
func fillScreen() -> String {
    let size = terminalSize()
    let bg = themeStore.withLock { $0.screenBackground }
    let row = String(repeating: " ", count: size.w)
    var s = ""
    s.reserveCapacity(size.h * (size.w + 12) + 32)
    s += "\u{1B}[0m" + bg + "\u{1B}[2J"
    for y in 0..<size.h { s += "\u{1B}[\(y + 1);1H" + row }
    return s
}

func terminalSize() -> (w: Int, h: Int) {
    var ws = winsize()
    if ioctl(fdGuard.renderOutputFD, TIOCGWINSZ, &ws) == 0, ws.ws_col > 0, ws.ws_row > 0 {
        return (min(Int(ws.ws_col), 512), min(Int(ws.ws_row), 256))
    }
    return (80, 24)
}

struct Cell: Equatable, Sendable { var ch: Character = " "; var fg: UInt8 = 250; var bg: UInt8 = 16; var bold = false }

struct ThemePalette: Sendable {
    var rgbTable: [String] = (0..<256).map { n -> String in
        let v: (Int, Int, Int)
        if n < 16 {
            let base = [(0, 0, 0), (128, 0, 0), (0, 128, 0), (128, 128, 0), (0, 0, 128), (128, 0, 128), (0, 128, 128), (192, 192, 192),
                        (128, 128, 128), (255, 0, 0), (0, 255, 0), (255, 255, 0), (0, 0, 255), (255, 0, 255), (0, 255, 255), (255, 255, 255)]
            v = base[n]
        } else if n >= 232 {
            let g = 8 + (n - 232) * 10
            v = (g, g, g)
        } else {
            let c = n - 16
            let f = { (x: Int) in x == 0 ? 0 : 55 + x * 40 }
            v = (f(c / 36), f((c / 6) % 6), f(c % 6))
        }
        return "\(v.0);\(v.1);\(v.2)"
    }
    var screenBackground = "\u{1B}[48;2;0;0;0m"
    var lightTheme = false
}

let themeStore = HeapUnfairLock(ThemePalette())

/// Mono: black on off-white (default), or `--dark` for white on black. Greys run between the two.
func applyTheme(light: Bool) {
    themeStore.withLock { theme in
        theme.lightTheme = light
        let paper = light ? (246, 245, 241) : (0, 0, 0)
        let ink = light ? (12, 12, 12) : (255, 255, 255)
        func str(_ c: (Int, Int, Int)) -> String { "\(c.0);\(c.1);\(c.2)" }
        func mix(_ u: Double) -> (Int, Int, Int) {
            (Int(Double(paper.0) + Double(ink.0 - paper.0) * u),
             Int(Double(paper.1) + Double(ink.1 - paper.1) * u),
             Int(Double(paper.2) + Double(ink.2 - paper.2) * u))
        }
        for n in 232...255 { theme.rgbTable[n] = str(mix(0.05 + 0.95 * Double(n - 232) / 23)) }
        theme.rgbTable[16] = str(paper)
        theme.screenBackground = "\u{1B}[48;2;\(str(paper))m"
    }
}

/// Verified 1-column terminal glyph predicate: printable ASCII (`0x20...0x7E`) plus the exact
/// 13 single-width Unicode box/symbol glyphs used by the UI, guaranteeing `wcwidth == 1`
/// and zero C0/C1/combining/wide-character column desynchronization.
func isVerifiedSingleColumnGlyph(_ ch: Character) -> Bool {
    guard ch.unicodeScalars.count == 1, let s = ch.unicodeScalars.first else { return false }
    if s.value >= 0x20 && s.value <= 0x7E { return true }
    switch s.value {
    case 0x00B7, 0x00BB, 0x201C, 0x201D,
         0x2500, 0x2502, 0x256D, 0x256E, 0x256F, 0x2570,
         0x2588, 0x25B6, 0x25B8:
        return true
    default:
        return false
    }
}

/// Total Euclidean non-negative modulo (`0 <= modPositive(i, count) < count` for all `count > 0`).
@inline(__always)
func modPositive(_ i: Int, _ count: Int) -> Int {
    guard count > 0 else { return 0 }
    let r = i % count
    return r < 0 ? r + count : r
}

/// Total normalized index quantizer (`0 <= safeIndex(u, count) < count` across all IEEE-754 bit patterns).
@inline(__always)
func safeIndex(_ u: Double, count: Int) -> Int {
    guard count > 1 else { return 0 }
    let clamped = clampFinite(u, lo: 0.0, hi: 1.0, fallback: 0.0)
    return min(count - 1, max(0, Int(clamped * Double(count - 1) + 0.5)))
}

final class Canvas {
    let w = 80, h = 24
    var cells = [Cell](repeating: Cell(), count: 80 * 24)
    func clear() { for i in cells.indices { cells[i] = Cell() } }
    func put(_ x: Int, _ y: Int, _ ch: Character, _ fg: UInt8, bg: UInt8 = 16, bold: Bool = false) {
        guard x >= 0, y >= 0, x < w, y < h else { return }
        let safeCh: Character = isVerifiedSingleColumnGlyph(ch) ? ch : " "
        cells[y * w + x] = Cell(ch: safeCh, fg: fg, bg: bg, bold: bold)
    }
    func text(_ x: Int, _ y: Int, _ s: String, _ fg: UInt8, bg: UInt8 = 16, bold: Bool = false) {
        var i = x
        for c in s { put(i, y, c, fg, bg: bg, bold: bold); i += 1 }
    }
    func centered(_ y: Int, _ s: String, _ fg: UInt8, bold: Bool = false) { text((w - s.count) / 2, y, s, fg, bold: bold) }
    /// What the terminal is showing now, committed strictly after a full `out(frame)` write succeeds.
    var shown: [Cell]?
    func changes(originX: Int, originY: Int, rgbTable: [String]) -> String {
        var s = ""
        var pen: Cell?
        var writeAt = -1
        for i in 0..<(w * h) {
            let c = cells[i]
            if let shown, shown[i] == c { continue }
            if writeAt != i { s += "\u{1B}[\(originY + i / w + 1);\(originX + i % w + 1)H" }
            if pen == nil || pen!.bold != c.bold { s += c.bold ? "\u{1B}[1m" : "\u{1B}[22m" }
            if pen == nil || pen!.fg != c.fg { s += "\u{1B}[38;2;\(rgbTable[Int(c.fg)])m" }
            if pen == nil || pen!.bg != c.bg { s += "\u{1B}[48;2;\(rgbTable[Int(c.bg)])m" }
            s.append(c.ch)
            pen = c
            writeAt = (i % w == w - 1) ? -1 : i + 1
        }
        return s.isEmpty ? "" : s + "\u{1B}[0m"
    }
    func commitShown() { shown = cells }
}

// MARK: - Look
// Every screen: "a90.com presents", the slanted ASCII NO SPEAKER logo with "trackpad" under it, the current part's
// visual, a status bar (part, motor frequency, speaker state) and a scroller. Black on off-white by default.

let inkC: UInt8 = 255, bodyC: UInt8 = 251, midC: UInt8 = 247, dimC: UInt8 = 243, ruleC: UInt8 = 240, faintC: UInt8 = 236
let paperC: UInt8 = 16

func typed(_ s: String, since: Double, cps: Double, at t: Double) -> String {
    let dt = (t - since) * cps
    guard dt.isFinite, dt > 0 else { return "" }
    let n = dt >= Double(s.count) ? s.count : Int(dt)
    return String(s.prefix(max(0, n)))
}
func dots(_ label: String, _ value: String, width: Int) -> String {
    label + " " + String(repeating: ".", count: max(1, width - label.count - value.count - 2)) + " "
}

// ASCII lettering: thin slanted strokes that look right at any line spacing.
let asciiLogo = [
    "    _   __ ____      _____  ____   ______ ___     __ __  ______ ____",
    "   / | / // __ \\    / ___/ / __ \\ / ____//   |   / //_/ / ____// __ \\",
    "  /  |/ // / / /    \\__ \\ / /_/ // __/  / /| |  / ,<   / __/  / /_/ /",
    " / /|  // /_/ /    ___/ // ____// /___ / ___ | / /| | / /___ / _, _/",
    "/_/ |_/ \\____/    /____//_/    /_____//_/  |_|/_/ |_|/_____//_/ |_|",
]
let logoWidth = asciiLogo.map(\.count).max() ?? 0
let slantGlyphs: [Character: [String]] = [
    "0": ["   ____ ", "  / __ \\", " / / / /", "/ /_/ / ", "\\____/  "],
    "1": ["   ___", "  <  /", "  / / ", " / /  ", "/_/   "],
    "2": ["   ___ ", "  |__ \\", "  __/ /", " / __/ ", "/____/ "],
    "3": ["   _____", "  |__  /", "   /_ < ", " ___/ / ", "/____/  "],
    "4": ["   __ __", "  / // /", " / // /_", "/__  __/", "  /_/   "],
    "5": ["    ______", "   / ____/", "  /___ \\  ", " ____/ /  ", "/_____/   "],
    "6": ["   _____", "  / ___/", " / __ \\ ", "/ /_/ / ", "\\____/  "],
    "7": [" _____", "/__  /", "  / / ", " / /  ", "/_/   "],
    "8": ["   ____ ", "  ( __ )", " / __  |", "/ /_/ / ", "\\____/  "],
    "9": ["   ____ ", "  / __ \\", " / /_/ /", " \\__, / ", "/____/  "],
    "H": ["    __  __", "   / / / /", "  / /_/ / ", " / __  /  ", "/_/ /_/   "],
    "z": ["      ", " ____ ", "/_  / ", " / /_ ", "/___/ "],
    " ": ["   ", "   ", "   ", "   ", "   "],
]
/// The lockup: NO SPEAKER, a row of air, then a rule as wide as the logo with the description on the left and
/// "trackpad" on the right:  ─  haptic voice synthesis  ───────  trackpad  ─
let logoTag = "trackpad"
let logoTagColumn = logoWidth - 3 - logoTag.count
func logoLockup() -> [String] { asciiLogo + ["", String(repeating: " ", count: logoTagColumn) + logoTag] }
func drawLogo(_ cv: Canvas, y: Int) {
    let x0 = (80 - logoWidth) / 2
    for (i, line) in asciiLogo.enumerated() { cv.text(x0, y + i, line, inkC, bold: true) }
    let row = y + asciiLogo.count + 1
    for x in x0..<(x0 + logoWidth) { cv.put(x, row, "─", dimC) }
    cv.text(x0 + 1, row, "  haptic voice synthesis  ", midC)
    cv.text(x0 + logoTagColumn - 2, row, "  " + logoTag + "  ", inkC, bold: true)
}
func drawSlant(_ cv: Canvas, _ text: String, y: Int, color: UInt8 = inkC) {
    var rows = [String](repeating: "", count: 5)
    for ch in text { let g = slantGlyphs[ch] ?? slantGlyphs[" "]!; for r in 0..<5 { rows[r] += g[r] } }
    let w = rows.map(\.count).max() ?? 0
    for (i, line) in rows.enumerated() {
        for (j, ch) in line.enumerated() where ch != " " { cv.put((80 - w) / 2 + j, y + i, ch, color, bold: true) }
    }
}
/// Classic ASCII shading, light to dense.
let ramp: [Character] = [" ", ".", ":", "-", "=", "+", "*", "#", "%", "@"]
func shade(_ v: Double) -> Character {
    ramp[safeIndex(v, count: ramp.count)]
}
/// "[=======>        ]" style bar, inside the given width (brackets included).
func asciiBar(_ v: Double, width: Int) -> String {
    let inner = max(1, width - 2)
    let u = clampFinite(v, lo: 0.0, hi: 1.0, fallback: 0.0)
    let fill = min(inner, max(0, Int(u * Double(inner))))
    return "[" + String(repeating: "=", count: max(0, fill - 1)) + (fill > 0 ? ">" : "") + String(repeating: " ", count: inner - fill) + "]"
}

/// A silver shimmer travelling along `i` (no colour).
let silver: [UInt8] = [245, 246, 247, 248, 249, 250, 251, 252, 253, 254, 255, 255, 254, 253, 252, 251, 250, 249, 248, 247, 246]
func shimmer(_ i: Int) -> UInt8 {
    silver[modPositive(i, silver.count)]
}

let scrollText = "      ·  a90.com presents  NO SPEAKER  ·    the trackpad has no speaker. every sound you hear is its haptic motor, driven through MultitouchSupport, a private macOS framework.    range: 100 to 4000 vibrations per second.    voice: two formants, retriggered on every pitch beat.    thanks for listening.    a90.com    "
let scrollChars = Array(scrollText)

struct RenderMemory {
    var rollHistory = [Int](repeating: -1, count: 62)
    var trail: [(x: Double, y: Double)] = []
    var marquee = 0

    mutating func remember(_ s: LiveState, _ t: Double) {
        rollHistory.removeFirst()
        rollHistory.append(s.scene == .sing && t - s.lastPlay < 0.1 ? s.noteRow : -1)
        if s.scene == .touch, s.touchDown {
            trail.append((s.touchX, s.touchY))
            if trail.count > 14 { trail.removeFirst() }
        }
    }
}

func draw(_ cv: Canvas, _ s: LiveState, _ t: Double, _ mem: RenderMemory) {
    cv.clear()
    // "a90.com presents", framed by rules.
    let presents = "a90.com presents"
    let width = logoWidth, side = (width - presents.count - 4) / 2
    let header = String(repeating: "─", count: side) + "  " + presents + "  " + String(repeating: "─", count: width - presents.count - 4 - side)
    cv.centered(0, header, dimC)
    cv.text((80 - header.count) / 2 + side + 2, 0, presents, bodyC, bold: true)
    drawLogo(cv, y: 2)
    if s.scene == .intro { drawSplash(cv, s, t); return }

    switch s.scene {
    case .heart: drawHeart(cv, s, t)
    case .sweep: drawSweep(cv, s, t)
    case .talk: drawTalk(cv, s, t)
    case .sing: drawSing(cv, s, t, rollHistory: mem.rollHistory)
    case .beat, .rap: drawBeat(cv, s, t)
    case .yourTurn: drawYourTurn(cv, s, t)
    case .touch: drawTouch(cv, s, t, trail: mem.trail)
    case .say: drawSay(cv, s, t)
    case .outro: drawOutro(cv, s, t)
    default: break
    }

    // Status bar: the part, the motor, and the proof.
    let badge = String(format: " %02d/%02d ", s.part, partCount)
    cv.text(1, 21, badge, paperC, bg: inkC, bold: true)
    cv.text(1 + badge.count + 1, 21, s.partName, inkC, bold: true)
    let active = t - s.lastPlay < 0.08 && s.hz.isFinite
    cv.text(24, 21, "motor", dimC)
    cv.text(30, 21, active ? String(format: "%4.0f hz", s.hz) : "idle", active ? inkC : dimC, bold: active)
    cv.text(38, 21, asciiBar(active ? s.level : 0, width: 10), bodyC)
    if let muted = s.muted {
        let chip = muted ? " SPEAKERS MUTED " : " SPEAKERS ON · MUTE "
        let blink = !muted && Int(max(0, t) * 2.5) % 2 == 0
        cv.text(79 - chip.count, 21, chip, blink ? inkC : paperC, bg: blink ? faintC : inkC, bold: true)
    }
    cv.text(2, 22, "space skip · q end", faintC)
    // Scroller.
    for x in 0..<80 {
        let idx = (x + mem.marquee) % scrollChars.count
        let c = scrollChars[idx]
        cv.put(x, 23, c, shimmer((x + mem.marquee) / 2), bold: true)
    }
}

func drawSplash(_ cv: Canvas, _ s: LiveState, _ t: Double) {
    let x = 10, done = s.stepDone
    cv.text(x, 11, "$", midC); cv.text(x + 2, 11, typed("./nospeaker", since: s.started, cps: 30, at: t), inkC, bold: true)
    func line(_ y: Int, _ label: String, _ value: String) {
        let d = dots(label, value, width: 56)
        cv.text(x + 2, y, d, midC); cv.text(x + 2 + d.count, y, value, inkC, bold: true)
    }
    if done >= 1 { line(12, "loading the trackpad's haptics", mtAPI.handle != nil ? "ok" : "missing") }
    if done >= 2 { line(13, motorRuntime.motorBuiltIn ? "connecting to the built-in trackpad" : "connecting to the trackpad", "ready") }
    if done >= 2 {
        let total = max(1, s.stepTotal - 2), voices = max(0, min(total, done - 2))
        if voices < total {
            let width = 28, fill = Int(Double(width) * Double(voices) / Double(total))
            let barText = String(repeating: "=", count: max(0, fill - 1)) + (fill > 0 ? ">" : "") + String(repeating: " ", count: width - fill)
            let spin = Int(max(0, t) * 10) % 4
            cv.text(x + 2, 14, "preparing the voice [\(barText)] \(voices)/\(total) " + ["|", "/", "-", "\\"][spin], bodyC)
        } else {
            line(14, "preparing the voice", "ready")
        }
    }
    drawProof(cv, s, t, y: 17)
    cv.centered(19, "keep your hands off the trackpad until the end", dimC)
    let ready = s.stepTotal > 0 && done >= s.stepTotal
    cv.centered(22, ready && s.muted != true ? "space to start anyway  ·  q end" : "space skip  ·  q end", dimC)
}

/// The proof, as an inverted banner: muted, or a blinking reminder to mute.
func drawProof(_ cv: Canvas, _ s: LiveState, _ t: Double, y: Int) {
    guard let muted = s.muted else { return }
    let text = "   " + (muted ? "SPEAKERS MUTED  ·  EVERY SOUND YOU HEAR IS THE TRACKPAD" : "SPEAKERS ARE ON  ·  MUTE YOUR MAC FIRST") + "   "
    let blink = !muted && Int(max(0, t) * 2.5) % 2 == 0
    cv.text((80 - text.count) / 2, y, text, blink ? inkC : paperC, bg: blink ? faintC : inkC, bold: true)
}

let heartArt = [",d88b.d88b,", "88888888888", "`Y8888888Y'", "  `Y888Y'", "    `Y'"]
func drawHeart(_ cv: Canvas, _ s: LiveState, _ t: Double) {
    let rawPulse = max(0, 1 - (t - s.lastPlay) / 0.35) * s.level
    let pulse = rawPulse.isFinite ? min(1.0, max(0.0, rawPulse)) : 0.0
    let shades: [UInt8] = [236, 238, 240, 243, 246, 249, 252, 255]
    let color = shades[min(shades.count - 1, max(0, Int(pulse * Double(shades.count - 1) + 0.5)))]
    for (y, row) in heartArt.enumerated() { cv.text(34, 11 + y, row, color, bold: pulse > 0.3) }
    cv.centered(19, "waking up the motor", pulse > 0.3 ? inkC : dimC, bold: pulse > 0.3)
}

func xForHz(_ f: Double) -> Int {
    let clamped = f.isFinite ? max(100.0, min(4000.0, f)) : 100.0
    return 3 + Int(log(clamped / 100.0) / log(40.0) * 73.0)
}

func drawSweep(_ cv: Canvas, _ s: LiveState, _ t: Double) {
    let f = (t - s.lastPlay < 0.1 && s.hz.isFinite && s.hz > 0) ? min(9999.0, s.hz) : 0
    drawSlant(cv, f > 0 ? String(Int(f)) + " Hz" : "100 Hz", y: 10)
    // A live wave: more cycles as the pitch climbs.
    let levels: [Character] = ["_", ".", "-", "~", "^"]
    let cycles = 1 + 22 * log(max(100, f) / 100) / log(40)
    for x in 0..<76 {
        let v = f > 0 ? sin(2 * .pi * cycles * Double(x) / 76 - t * 12) : 0
        let lvlIdx = v.isFinite ? min(4, max(0, Int((v + 1) / 2 * 4.99))) : 2
        cv.put(2 + x, 16, f > 0 ? levels[lvlIdx] : "-", f > 0 ? shimmer(x / 3 + Int(max(0, t) * 10)) : faintC, bold: true)
    }
    // Ruler, 100 Hz to 4 kHz (log), with a marker.
    for x in 3...76 { cv.put(x, 18, "-", faintC) }
    for (mark, name) in [(100.0, "100"), (250, "250"), (500, "500"), (1000, "1k"), (2000, "2k"), (4000, "4k")] {
        let x = xForHz(mark)
        cv.put(x, 18, "+", dimC)
        cv.text(max(2, x - name.count / 2), 19, name, midC)
    }
    if f > 0 { cv.put(xForHz(f), 17, "v", inkC, bold: true) }
}

func drawCaption(_ cv: Canvas, _ s: LiveState, _ t: Double, y: Int) {
    let rawProg = (t - s.captionStart) / max(0.2, s.captionDur) * 1.15
    let progress = rawProg.isFinite ? min(1.0, max(0.0, rawProg)) : 0.0
    let shown = String(s.caption.prefix(max(0, Int(Double(s.caption.count) * progress))))
    // A blinking caret while it types; the closing quote once the line is done.
    let caret = progress >= 1 ? "”" : Int(max(0, t) * 3) % 2 == 0 ? "█" : " "
    var lines: [String] = [], line = ""
    for word in shown.split(separator: " ", omittingEmptySubsequences: false) {
        if line.count + word.count + 1 > 64 { lines.append(line); line = String(word) } else { line += line.isEmpty ? String(word) : " " + word }
    }
    lines.append(line + caret)
    // Quotes hug the words on both ends: “like this”.
    let shown2 = Array(lines.suffix(2))
    for (i, l) in shown2.enumerated() {
        if i == 0 && lines.count <= 2 { cv.text(7, y, "“", midC, bold: true) }
        cv.text(8, y + i, l, inkC, bold: true)
    }
}

func meter(_ cv: Canvas, y: Int, label: String, value: Double, lo: Double, hi: Double) {
    cv.text(6, y, label, inkC, bold: true)
    let valid = value.isFinite && value > 0
    let v = valid ? (value - lo) / (hi - lo) : 0
    cv.text(10, y, asciiBar(v, width: 46), bodyC)
    cv.text(57, y, valid ? String(format: "%5.0f hz", value) : "    -   ", valid ? inkC : dimC)
}

func drawTalk(_ cv: Canvas, _ s: LiveState, _ t: Double) {
    cv.text(6, 10, "▸ SPEAKING", inkC, bold: true)
    drawCaption(cv, s, t, y: 11)
    let on = t - s.lastPlay < 0.08
    meter(cv, y: 14, label: "F0", value: on ? s.f0 : 0, lo: 60, hi: 260)
    meter(cv, y: 15, label: "F1", value: on ? s.f1 : 0, lo: 150, hi: 1000)
    meter(cv, y: 16, label: "F2", value: on ? s.f2 : 0, lo: 600, hi: 2800)
    // The two formants as peaks on a log frequency strip.
    for x in 3...76 {
        let fx = 100 * pow(40, Double(x - 3) / 73)
        var v = 0.0
        if on {
            for (f, a) in [(s.f1, 1.0), (s.f2, 0.8)] where f.isFinite && f > 0 { v += a * exp(-pow(log(fx / f) / 0.12, 2)) }
            v *= s.level
        }
        let c = shade(min(1, v))
        cv.put(x, 18, c == " " ? "." : c, c == " " ? faintC : inkC)
        cv.put(x, 19, "-", faintC)
    }
    cv.text(3, 20, "100", dimC); cv.text(xForHz(1000) - 1, 20, "1k", dimC); cv.text(74, 20, "4k", dimC)
    cv.text(25, 20, "two tones, one motor, no speaker", midC)
}

func drawSing(_ cv: Canvas, _ s: LiveState, _ t: Double, rollHistory: [Int]) {
    for (i, n) in rollNotes.enumerated() {
        let y = 10 + i
        cv.text(2, y, n, s.noteRow == i ? inkC : dimC, bold: s.noteRow == i)
        for x in 6..<68 { cv.put(x, y, "·", faintC) }
    }
    for (k, row) in rollHistory.enumerated() where row >= 0 {
        let isNow = k == rollHistory.count - 1
        cv.put(6 + k, 10 + row, isNow ? "o" : "=", isNow ? inkC : shimmer(k / 3), bold: true)
    }
    cv.text(70, 11, "»", inkC, bold: true)
    cv.text(72, 11, s.noteRow >= 0 ? s.noteName : "", inkC, bold: true)
    if s.noteRow >= 0, s.hz.isFinite { cv.text(70, 12, String(format: "%4.0fhz", s.hz), midC) }
    cv.centered(17, "an original hook in the motor's loudest, cleanest octave", bodyC)
    cv.centered(18, "scoops · glides · vibrato", dimC)
}

func drawBeat(_ cv: Canvas, _ s: LiveState, _ t: Double) {
    let pads: [(String, Double)] = [("KICK", s.kick), ("SNARE", s.snare), ("HAT", s.hat)]
    let rapping = s.scene == .rap
    let top = 10, height = 3
    for (i, p) in pads.enumerated() {
        let x0 = 4 + i * 25, w = 22
        let hot = t - p.1 < 0.13
        for y in top..<(top + height) {
            for x in x0..<(x0 + w) {
                let edgeY = y == top || y == top + height - 1, edgeX = x == x0 || x == x0 + w - 1
                let ch: Character = edgeY && edgeX ? "+" : edgeY ? "-" : edgeX ? "|" : " "
                cv.put(x, y, ch, hot ? paperC : ruleC, bg: hot ? inkC : paperC)
            }
        }
        cv.text(x0 + (w - p.0.count) / 2, top + 1, p.0, hot ? paperC : bodyC, bg: hot ? inkC : paperC, bold: true)
    }
    // Step sequencer.
    let lanes = [("K", "X.........X..x.."), ("S", "....X.......X..."), ("H", "x.x.x.x.x.x.xxx.")]
    let ly = 14
    for (j, lane) in lanes.enumerated() {
        cv.text(8, ly + j, lane.0, inkC, bold: true)
        for (i, ch) in lane.1.enumerated() {
            let x = 11 + i * 4
            let isStep = i == s.step
            let filled = ch != "."
            cv.text(x - 1, ly + j, filled ? " x " : " . ", isStep ? paperC : filled ? inkC : dimC, bg: isStep ? (filled ? inkC : midC) : paperC, bold: filled)
        }
    }
    if rapping {
        drawCaption(cv, s, t, y: 18)
    } else {
        cv.centered(19, String(format: "%.0f bpm  ·  bar %d/%d  ·  kick, snare, hats and bass from one motor", s.bpm, s.bar + 1, s.bars), midC)
    }
}

func drawYourTurn(_ cv: Canvas, _ s: LiveState, _ t: Double) {
    cv.centered(11, "Y O U R   T U R N", inkC, bold: true)
    drawCaption(cv, s, t, y: 14)
    cv.centered(18, "in a moment you'll play it with your finger", midC)
}

func drawTouch(_ cv: Canvas, _ s: LiveState, _ t: Double, trail: [(x: Double, y: Double)]) {
    let x0 = 3, y0 = 10, w = 38, h = 11
    let edge: UInt8 = s.touchDown ? inkC : dimC
    cv.text(x0, y0, "╭" + String(repeating: "─", count: w - 2) + "╮", edge)
    for y in (y0 + 1)..<(y0 + h - 1) { cv.put(x0, y, "│", edge); cv.put(x0 + w - 1, y, "│", edge) }
    cv.text(x0, y0 + h - 1, "╰" + String(repeating: "─", count: w - 2) + "╯", edge)
    let names = ["G5", "A5", "B5", "C6", "E6", "F6", "G6", "A6", "B6", "C7"]
    for (i, n) in names.enumerated() where i % 3 == 0 { cv.text(x0 + 2 + i * 34 / names.count, y0 + h - 2, n, ruleC) }
    for (k, p) in trail.enumerated() {
        let sx = p.x.isFinite ? min(1.0, max(0.0, p.x)) : 0.5
        let sy = p.y.isFinite ? min(1.0, max(0.0, p.y)) : 0.5
        let px = x0 + 1 + Int(sx * Double(w - 3)), py = y0 + 1 + Int((1 - sy) * Double(h - 3))
        let isNow = k == trail.count - 1 && s.touchDown
        cv.put(px, py, isNow ? "@" : "o", isNow ? inkC : shimmer(k), bold: true)
    }
    let rx = 45
    if s.touchMissed {
        cv.text(rx, 12, "no touch, skipping", dimC)
    } else if !s.touchSeen {
        let blink = Int(max(0, t) * 3) % 2 == 0
        cv.text(rx, 11, "▶ PUT A FINGER ON", blink ? inkC : midC, bold: true)
        cv.text(rx, 12, "  THE TRACKPAD", blink ? inkC : midC, bold: true)
        cv.text(rx, 14, "glide lightly, no need to click", midC)
        cv.text(rx, 16, String(format: "waiting %.0fs", max(0, s.touchWaitUntil - t)), dimC)
    } else {
        cv.text(rx, 10, "TOUCH TO PLAY", inkC, bold: true)
        cv.text(rx, 12, "slide left/right   pitch", bodyC)
        cv.text(rx, 13, "move up            vibrato", bodyC)
        cv.text(rx, 14, "glide lightly, don't click", dimC)
        let on = s.touchDown && t - s.lastPlay < 0.08 && s.hz.isFinite
        cv.text(rx, 16, "note", dimC); cv.text(rx + 6, 16, on ? s.noteName : "-", inkC, bold: true)
        cv.text(rx + 12, 16, on ? String(format: "%4.0f hz", s.hz) : "", midC)
        cv.text(rx, 17, asciiBar(on ? s.level : 0, width: 22), bodyC)
        let left = max(0, s.touchEnds - t)
        cv.text(rx, 19, asciiBar(left / 12, width: 22), inkC)
        cv.text(rx + 22, 19, String(format: "%2.0fs", left), dimC)
    }
}

func drawSay(_ cv: Canvas, _ s: LiveState, _ t: Double) {
    cv.text(6, 10, "▸ SAY ANYTHING", inkC, bold: true)
    cv.text(6, 11, "type something and press return. it'll say it.", midC)
    // The input box.
    let w = 68, x0 = 6
    cv.text(x0, 12, "+" + String(repeating: "-", count: w - 2) + "+", s.inputActive ? bodyC : ruleC)
    cv.text(x0, 13, "|", s.inputActive ? bodyC : ruleC); cv.text(x0 + w - 1, 13, "|", s.inputActive ? bodyC : ruleC)
    cv.text(x0, 14, "+" + String(repeating: "-", count: w - 2) + "+", s.inputActive ? bodyC : ruleC)
    if s.inputActive {
        let caret = Int(max(0, t) * 2.5) % 2 == 0 ? "_" : " "
        let shown = String(s.inputText.suffix(w - 6))
        cv.text(x0 + 2, 13, ">", midC)
        cv.text(x0 + 4, 13, shown + caret, inkC, bold: true)
        if s.inputText.isEmpty {
            cv.text(x0 + 6, 13, "try: " + saySuggestion(at: t), dimC)
            cv.text(x0 + w - 3 - 13, 13, "tab to use it", faintC)
        }
    }
    switch s.sayStatus {
    case "preparing":
        let spin = Int(max(0, t) * 10) % 4
        cv.text(6, 16, "preparing the voice " + ["|", "/", "-", "\\"][spin], midC)
    case "speaking":
        drawCaption(cv, s, t, y: 16)
    default:
        if s.sayCount > 0 { cv.text(6, 16, "type another one, or finish below", midC) }
    }
    let finish = "when you're done, press  ESC  to see the credits"
    cv.text(6, 19, finish, inkC, bold: true)
    if let r = finish.range(of: " ESC ") {
        cv.text(6 + finish.distance(from: finish.startIndex, to: r.lowerBound), 19, " ESC ", paperC, bg: inkC, bold: true)
    }
    cv.text(6 + finish.count + 2, 19, "· return says it", dimC)
}

func formatCountASCII(_ n: Int) -> String {
    let raw = Array(String(max(0, n)))
    var out = ""
    out.reserveCapacity(raw.count + raw.count / 3)
    for (idx, ch) in raw.enumerated() {
        if idx > 0 && (raw.count - idx) % 3 == 0 { out.append(",") }
        out.append(ch)
    }
    return out
}

func drawOutro(_ cv: Canvas, _ s: LiveState, _ t: Double) {
    let rows: [(String, String)] = [
        ("code · sound · design", "a90"), ("web", "a90.com"),
        ("speakers used", "0"), ("vibrations", formatCountASCII(s.actuations)),
        ("runtime", String(format: "%.1f s", max(0, t - s.started))),
    ]
    cv.centered(10, "C R E D I T S", inkC, bold: true)
    for (i, r) in rows.enumerated() {
        let d = dots(r.0, r.1, width: 52)
        cv.text(14, 12 + i, d, dimC)
        cv.text(14 + d.count, 12 + i, r.1, inkC, bold: true)
    }
    if s.waitingForKey {
        let line = "follow @codycollier for more  ·  press  F  to open"
        let x = (80 - line.count) / 2
        cv.text(x, 18, line, inkC, bold: true)
        if let f = line.range(of: " F ") {
            cv.text(x + line.distance(from: line.startIndex, to: f.lowerBound), 18, " F ", paperC, bg: inkC, bold: true)
        }
        if t - s.followOpenedAt < 2.5 {
            cv.centered(19, "opened x.com/codycollier in your browser", bodyC)
        } else {
            let blink = Int(max(0, t) * 2) % 2 == 0
            cv.centered(19, "any other key exits", blink ? midC : dimC)
        }
    } else {
        cv.centered(19, "thanks for listening", dimC)
    }
}

/// Deterministic join-barrier coordinator ensuring the render thread finishes its final
/// `out(frame)` syscall strictly before `restoreTerminal()` closes `savedOut`.
final class RendererLifecycleCoordinator: Sendable {
    private let running = HeapUnfairLock<Bool>(false)
    private let exitedSemaphore = DispatchSemaphore(value: 0)

    func tryStart() -> Bool {
        running.withLock { cur in
            guard !cur else { return false }
            cur = true
            return true
        }
    }

    var shouldContinue: Bool {
        running.withLock { $0 }
    }

    func notifyLoopExited() {
        exitedSemaphore.signal()
    }

    func stopAndJoin(timeoutSeconds: Double = 2.0) {
        let wasRunning = running.withLock { cur -> Bool in
            let prev = cur
            cur = false
            return prev
        }
        if wasRunning {
            _ = exitedSemaphore.wait(timeout: .now() + timeoutSeconds)
        }
    }
}

let rendererLifecycle = RendererLifecycleCoordinator()

func startRenderer() {
    guard rendererLifecycle.tryStart() else { return }
    let th = Thread {
        defer { rendererLifecycle.notifyLoopExited() }
        let cv = Canvas()
        var mem = RenderMemory()
        var lastSize = (w: 0, h: 0)
        var lastMutePoll = -9.0
        var frameCount: UInt64 = 0
        var next = now()
        while rendererLifecycle.shouldContinue {
            let s = snapshot()
            let t = max(now(), s.captionStart)
            frameCount &+= 1
            // Screen memory: piano roll and touch trail.
            mem.remember(s, t)
            if t - lastMutePoll > 0.5 { lastMutePoll = t; let m = speakersMuted(); live { $0.muted = m } }
            let size = terminalSize()
            var prefix = ""
            if size != lastSize { prefix = fillScreen(); lastSize = size; cv.shown = nil }
            draw(cv, s, t, mem)
            let rgb = themeStore.withLock { $0.rgbTable }
            let diff = cv.changes(originX: max(0, (size.w - 80) / 2), originY: max(0, (size.h - 24) / 2), rgbTable: rgb)
            let frame = prefix + diff
            if frame.isEmpty {
                cv.commitShown()
            } else if out(frame) {
                cv.commitShown()
            } else {
                cv.shown = nil
            }
            // A steady frame clock: 24 fps while playing (the scroller steps every other frame, 12 chars/s),
            // 8 fps while waiting on the credits (one step a frame).
            let period = s.waitingForKey ? 0.125 : 1.0 / 24
            if s.waitingForKey || frameCount % 2 == 0 {
                mem.marquee = (mem.marquee + 1) % scrollChars.count
            }
            next += period
            let wait = next - now()
            if wait.isFinite && wait > 0 {
                let cappedUs = min(125_000.0, wait * 1e6)
                if cappedUs >= 1.0 { usleep(useconds_t(cappedUs)) }
            } else {
                next = now()
            }
        }
    }
    th.qualityOfService = .userInitiated
    th.start()
}

func stopRenderer() { rendererLifecycle.stopAndJoin() }

/// True when a byte is ready on stdin within `ms` milliseconds.
func waitForInput(ms: Int) -> Bool {
    var fds = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
    while true {
        let r = Darwin.poll(&fds, 1, Int32(max(0, min(ms, 1000))))
        if r < 0 && errno == EINTR { continue }
        return r > 0
    }
}

func startKeys() {
    let th = Thread {
        var pendingByte: UInt8?

        func nextStdinByte() -> Int? {
            if let b = pendingByte {
                pendingByte = nil
                return Int(b)
            }
            var raw: UInt8 = 0
            while !runControl.stopRequested {
                let n = Darwin.read(STDIN_FILENO, &raw, 1)
                if n == 1 { return Int(raw) }
                if n == 0 { return nil }
                if errno == EINTR { continue }
                if errno == EAGAIN || errno == EWOULDBLOCK { usleep(10_000); continue }
                return nil
            }
            return nil
        }

        while !runControl.stopRequested {
            guard let byteVal = nextStdinByte() else { break }
            let c = UInt8(byteVal)

            // Decode UTF-8 multi-byte sequences atomically so continuation bytes (0x80...0xBF)
            // are never dropped piecemeal or misinterpreted, and fold common smart punctuation to ASCII.
            if c >= 0x80 {
                let needed: Int
                if (0xC2...0xDF).contains(c) { needed = 1 }
                else if (0xE0...0xEF).contains(c) { needed = 2 }
                else if (0xF0...0xF4).contains(c) { needed = 3 }
                else { continue }

                var seq: [UInt8] = [c]
                var valid = true
                for _ in 0..<needed {
                    guard waitForInput(ms: 30) else { valid = false; break }
                    var cont: UInt8 = 0
                    guard Darwin.read(STDIN_FILENO, &cont, 1) == 1 else { valid = false; break }
                    if (cont & 0xC0) == 0x80 {
                        seq.append(cont)
                    } else {
                        pendingByte = cont
                        valid = false
                        break
                    }
                }
                guard valid, let decoded = String(bytes: seq, encoding: .utf8),
                      decoded.unicodeScalars.count == 1,
                      let scalar = decoded.unicodeScalars.first,
                      scalar.value >= 0xA0 else { continue }

                if snapshot().inputActive {
                    let mapped: Character?
                    switch scalar.value {
                    case 0x2018, 0x2019: mapped = "'"
                    case 0x201C, 0x201D: mapped = "\""
                    case 0x2013, 0x2014: mapped = "-"
                    default: mapped = nil
                    }
                    if let ch = mapped {
                        live { if $0.inputText.count < 70 { $0.inputText.append(ch) } }
                    }
                } else {
                    runControl.setKeyPressed(true)
                }
                continue
            }

            // Typing a line for it to say: every key is text, except return, backspace, tab and esc.
            if snapshot().inputActive {
                if c == 27 {
                    if waitForInput(ms: 30) {
                        var b: UInt8 = 0
                        guard Darwin.read(STDIN_FILENO, &b, 1) == 1 else { continue }
                        if b == 27 { live { $0.inputDone = true }; continue }
                        if b == UInt8(ascii: "[") || b == UInt8(ascii: "O") {
                            var chByte: UInt8 = 0
                            while waitForInput(ms: 30), Darwin.read(STDIN_FILENO, &chByte, 1) == 1 {
                                if chByte == UInt8(ascii: "M") {
                                    var discard: UInt8 = 0
                                    for _ in 0..<3 where waitForInput(ms: 30) { _ = Darwin.read(STDIN_FILENO, &discard, 1) }
                                    break
                                }
                                if (0x40...0x7E).contains(chByte) { break }
                            }
                        }
                    } else {
                        live { $0.inputDone = true }
                    }
                } else if c == 13 || c == 10 {
                    live { $0.inputSubmitted = true }
                } else if c == 9 {
                    let suggestion = saySuggestion(at: now())
                    live { if $0.inputText.isEmpty { $0.inputText = suggestion } }
                } else if c == 127 || c == 8 {
                    live { if !$0.inputText.isEmpty { $0.inputText.removeLast() } }
                } else if (32...126).contains(c), c != 91, c != 93 {
                    let ch = Character(UnicodeScalar(c))
                    live { if $0.inputText.count < 70 { $0.inputText.append(ch) } }
                }
                continue
            }
            if c == 27 {
                // Esc alone quits; double-Esc also quits; Esc followed quickly by "[" or "O" is a sequence.
                guard waitForInput(ms: 30) else { requestEnd(); continue }
                var next: UInt8 = 0
                guard Darwin.read(STDIN_FILENO, &next, 1) == 1 else { continue }
                if next == 27 { requestEnd(); continue }
                if next == UInt8(ascii: "[") || next == UInt8(ascii: "O") {
                    var b: UInt8 = 0
                    while waitForInput(ms: 30), Darwin.read(STDIN_FILENO, &b, 1) == 1 {
                        if b == UInt8(ascii: "M") {
                            var discard: UInt8 = 0
                            for _ in 0..<3 where waitForInput(ms: 30) { _ = Darwin.read(STDIN_FILENO, &discard, 1) }
                            break
                        }
                        if (0x40...0x7E).contains(b) { break }
                    }
                }
                continue
            }
            // On the credits, F opens the X profile (debounced and reaped) and stays put; any other key exits.
            if c == UInt8(ascii: "f") || c == UInt8(ascii: "F"), snapshot().waitingForKey {
                let at = now()
                var shouldLaunch = false
                live {
                    if at - $0.followOpenedAt >= 5.0 {
                        $0.followOpenedAt = at
                        shouldLaunch = true
                    }
                }
                if shouldLaunch {
                    DispatchQueue.global(qos: .utility).async {
                        let p = Process()
                        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                        p.arguments = ["-u", "https://x.com/codycollier"]
                        p.standardInput = FileHandle.nullDevice
                        p.standardOutput = FileHandle.nullDevice
                        p.standardError = FileHandle.nullDevice
                        let exitSem = DispatchSemaphore(value: 0)
                        p.terminationHandler = { _ in exitSem.signal() }
                        guard (try? p.run()) != nil else { return }
                        if exitSem.wait(timeout: .now() + 10.0) == .timedOut {
                            p.terminate()
                        }
                        p.waitUntilExit()
                    }
                }
                continue
            }
            runControl.setKeyPressed(true)
            if c == UInt8(ascii: "q") || c == UInt8(ascii: "Q") { requestEnd() }
            if c == UInt8(ascii: " ") || c == UInt8(ascii: "s") { runControl.setSkipRequested(true) }
        }
    }
    th.start()
}

// MARK: - The show

func show(visuals: Bool) {
    let say = { (s: String) in if !visuals { print(s) } }
    live { $0.started = now() }
    if visuals { takeTerminal(); startKeys(); startRenderer() }
    pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0)

    // 1. Intro: what's about to happen, while the voice is prepared (a real loading bar).
    enter(.intro, 1, "LOADING")
    say("a90.com presents NO SPEAKER. Your trackpad doesn't have one. In a moment it's going to talk.")
    let introStart = now()
    let rapLine = "No speaker. No wires. Just a motor and a beat."
    let turnLine = "Your turn. Be gentle."
    let byeLine = "Okay. Back to clicking."
    let greeting = greetingLine()
    let phrases = [greeting, rapLine, turnLine, byeLine]
    let steps = 2 + phrases.count
    func progress(_ done: Int, _ label: String) {
        live { $0.stepDone = done; $0.stepTotal = steps }
    }
    progress(0, "opening MultitouchSupport.framework")
    pause(0.6)
    progress(1, "connecting to the trackpad")
    pause(0.5)
    var voices: [String: [Frame]] = [:]
    for (i, line) in phrases.enumerated() where !runControl.shouldSkipToCredits {
        progress(2 + i, "preparing the voice \(i + 1)/\(phrases.count)")
        voices[line] = render(line)
    }
    progress(steps, "ready")
    pause(max(0.6, 4.0 - (now() - introStart)))
    // The proof is the point: hold here until the speakers are muted (space starts anyway; 15 s at most).
    if visuals {
        let holdUntil = now() + 15
        while speakersMuted() == false && !interrupted() && now() < holdUntil { usleep(100_000) }
        if speakersMuted() == true { live { $0.muted = true }; pause(1.2) }
        runControl.setSkipRequested(false)
    }

    // 2. It wakes up: a heartbeat, no words yet.
    if !runControl.shouldSkipToCredits { enter(.heart, 2, "WAKING UP"); pause(0.3); heartbeat() }
    // 3. Its first words: hello, who it is, what it knows (the reveal).
    if !runControl.shouldSkipToCredits { enter(.talk, 3, "FIRST WORDS"); say("“\(greeting)”"); pause(0.4); talk(voices[greeting] ?? [], text: greeting); pause(0.9) }
    // 4. How: the sweep.
    if !runControl.shouldSkipToCredits { enter(.sweep, 4, "SWEEP"); say("sweep 100 Hz → 4 kHz"); pause(0.3); sweep(); pause(0.4) }
    // 5. Melody.
    if !runControl.shouldSkipToCredits { enter(.sing, 5, "MELODY"); say("♪ melody"); pause(0.4); sing(); pause(0.5) }
    // 6. Beat, then the rap over it.
    if !runControl.shouldSkipToCredits {
        enter(.beat, 6, "BEAT"); say("beat · then rap: “\(rapLine)”")
        groove(bars: 4, rapBar: 2, rap: voices[rapLine] ?? [], rapText: rapLine); pause(0.5)
    }
    // 7. Your turn.
    if !runControl.shouldSkipToCredits { enter(.yourTurn, 7, "YOUR TURN"); say("“\(turnLine)”"); pause(0.3); talk(voices[turnLine] ?? [], text: turnLine); pause(0.4) }
    // 8. Touch to play.
    if !runControl.shouldSkipToCredits { enter(.touch, 8, "TOUCH TO PLAY"); say("touch the trackpad: slide for pitch (12 s)"); touchToPlay() }
    // 9. Say anything (only with the screen: it needs typing).
    if !runControl.shouldSkipToCredits && visuals { enter(.say, 9, "SAY ANYTHING"); sayAnything() }
    // 10. Outro.
    if runControl.beginCreditsScene() {
        enter(.outro, 10, "OUTRO")
        talk(voices[byeLine] ?? render(byeLine), text: byeLine)
        live { $0.scene = .outro }
        sparkle()
        if visuals {
            runControl.setKeyPressed(false)
            live { $0.waitingForKey = true }
            while !runControl.keyPressed && !runControl.stopRequested { usleep(20_000) }
        } else {
            pause(1.0)
        }
    }

    let s = snapshot()
    if visuals { stopRenderer(); restoreTerminal() }
    let elapsed = max(0.0, now() - s.started)
    signOff(seconds: elapsed.isFinite ? Int(min(elapsed, 86400.0)) : 0, actuations: s.actuations)
}

func signOff(seconds: Int, actuations: Int) {
    // The sign-off: the logo stays in their terminal as a souvenir, with what to run next.
    // Plain bold and dim only, so it reads in any terminal theme.
    let esc = "\u{1B}["
    let vibrations = formatCountASCII(actuations)
    let rawArg0 = sanitizeTerminal(CommandLine.arguments.first ?? "nospeaker", maxBytes: 200)
    var me = (rawArg0.contains("/") && !rawArg0.isEmpty) ? rawArg0 : "nospeaker"
    let home = sanitizeTerminal(NSHomeDirectory(), maxBytes: 200)
    if !home.isEmpty, me.hasPrefix(home + "/") { me = "~" + me.dropFirst(home.count) }
    let clampedSeconds = max(0, seconds)
    print("")
    let lockup = logoLockup()
    for (i, line) in lockup.enumerated() { print("  " + (i < asciiLogo.count ? "\(esc)1m" : "\(esc)2m") + line + "\(esc)0m") }
    print("")
    print("  \(esc)1m\(clampedSeconds / 60):" + String(format: "%02d", clampedSeconds % 60) + "\(esc)0m  ·  \(esc)1m\(vibrations)\(esc)0m vibrations  ·  \(esc)1m0\(esc)0m speakers used")
    print("  more        \(esc)1mx.com/codycollier\(esc)0m")
    print("  play again  \(esc)2m\(me)\(esc)0m")
    print("  say a line  \(esc)2m\(me) \"hello there\"\(esc)0m")
    print("")
}

// MARK: - Main

func runMain() {
    let rawArgs = Array(CommandLine.arguments.dropFirst())
    let optSliceEnd = rawArgs.firstIndex(of: "--") ?? rawArgs.count
    var optArgs = Array(rawArgs[..<optSliceEnd])
    let postDashArgs = optSliceEnd < rawArgs.count ? Array(rawArgs[(optSliceEnd + 1)...]) : []

    func option(_ flag: String, example: String) -> String? {
        var found: String?
        while let i = optArgs.firstIndex(of: flag) {
            guard i + 1 < optArgs.count, !optArgs[i + 1].hasPrefix("-") else {
                usageError("\(flag) needs a value, like: \(flag) \(example)")
            }
            if found != nil {
                usageError("\(flag) can only be specified once.")
            }
            found = optArgs[i + 1]
            optArgs.removeSubrange(i...(i + 1))
        }
        return found
    }
    func flag(_ f: String) -> Bool {
        var seen = false
        while let i = optArgs.firstIndex(of: f) {
            optArgs.remove(at: i)
            seen = true
        }
        return seen
    }

    let wantsHelp = flag("--help")
    let wantsShortHelp = flag("-h")
    if wantsHelp || wantsShortHelp {
        print("""
        NO SPEAKER · a90.com presents
        Your MacBook's trackpad has no speaker. This makes it talk anyway, through its haptic motor.

          nospeaker                         the show (space skips a part, q goes to the end)
          nospeaker "any words"             just say something
          nospeaker --sweep                 a rising tone, 100 Hz to 4 kHz
          --voice Daniel                    any voice from `say -v '?'`
          --dark                            white on black instead of black on white
          --plain                           no visuals

        Mute your Mac: it still talks. Put it on a table, and keep your hands off the trackpad until it asks.
        a90.com · x.com/codycollier
        """)
        exit(0)
    }

    let selectedVoice = option("--voice", example: "Daniel")
    if let v = selectedVoice, !voiceExists(v) {
        let safeV = sanitizeTerminal(v, maxBytes: 64)
        fail("There's no voice called \"\(safeV)\" on this Mac.\nList the voices you have with: say -v '?'", headline: "nospeaker can't use that voice.", code: 64)
    }
    appConfig.withLock { $0.voiceName = selectedVoice }
    applyTheme(light: !flag("--dark"))
    let plain = flag("--plain")
    let wantsSweep = flag("--sweep")
    if let unknown = optArgs.first(where: { $0.hasPrefix("-") }) {
        let safeOpt = sanitizeTerminal(unknown, maxBytes: 64)
        usageError("\"\(safeOpt)\" isn't an option.")
    }
    let args = optArgs + postDashArgs

    signal(SIGPIPE, SIG_IGN)
    startSignalWatcher()
    signal(SIGINT, handleSigInt)
    signal(SIGTERM, handleSigTerm)
    signal(SIGHUP, handleSigTerm)
    signal(SIGQUIT, handleSigTerm)
    atexit(onExitRestore)

    motorRuntime.open()
    defer {
        stopTouch()
        motorRuntime.closeMotor()
    }

    if wantsSweep || !args.isEmpty {
        runControl.setCLIMode(true)
        pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0)
        if wantsSweep { print("sweeping 100 Hz → 4 kHz…"); sweep(seconds: 5) }
        if !args.isEmpty && !runControl.interrupted {
            let text = args.joined(separator: " ")
            let safeText = sanitizeTerminal(text, maxBytes: 512)
            let frames = render(text)
            if !runControl.interrupted {
                print("trackpad: “\(safeText)”")
                talk(frames, text: safeText)
            }
        }
    } else {
        let interactive = isatty(STDOUT_FILENO) == 1 && isatty(STDIN_FILENO) == 1
        // Too small a window: say so, and start by itself as soon as it's big enough.
        if !plain && interactive {
            var size = terminalSize()
            if size.w < 80 || size.h < 24 {
                runControl.setCLIMode(true)
                print("\n  nospeaker needs a slightly bigger window: at least 80 × 24.")
                print("  Drag the window's corner to make it bigger, and it starts by itself.  (ctrl-c to stop)\n")
                while (size.w < 80 || size.h < 24) && !runControl.stopRequested {
                    usleep(200_000)
                    size = terminalSize()
                }
                if runControl.stopRequested { return }
                runControl.setCLIMode(false)
            }
        }
        let size = terminalSize()
        let visuals = !plain && interactive && size.w >= 80 && size.h >= 24
        if !visuals { runControl.setCLIMode(true) }
        show(visuals: visuals)
    }
    usleep(120_000)
}

runMain()
