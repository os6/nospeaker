// nospeaker · a90.com
//
// A MacBook's Force Touch trackpad has no speaker: the click you feel is faked by a small motor under the
// glass. This program drives that motor directly, through MultitouchSupport (a private macOS framework), and
// uses it to talk, sing, play a beat, and turn into an instrument under your finger.
//
//   nospeaker                      the show: about a minute and a half, in the terminal
//   nospeaker "any words"          say something
//   nospeaker --sweep              a rising tone from 100 Hz to 4 kHz
//   options                        --voice <name> (any voice from `say -v '?'`), --dark, --plain, --external,
//                                  --lights (the keyboard backlight, Caps Lock light and screen play along)
//   nospeaker --music song.mid     play your own MIDI file (--parts 3,4, --only 6-31.5, --no-drums)
//
// How it talks: macOS's own voice (`say`) speaks the line into memory. Every 10 ms, linear prediction finds
// the voice's two strongest resonances (formants), its loudness and its pitch. The motor plays those two
// resonances as sine tones, restarted on every beat of the pitch, so they buzz like a voice. The motor is loud
// from about 100 Hz to 4 kHz, which covers the most important part of speech.
//
// Private API: MultitouchSupport is undocumented and may change with any macOS update. The motor is never
// driven past its normal maximum. --lights adds two more private frameworks, CoreBrightness (the keyboard
// backlight) and DisplayServices (the screen's brightness), also resolved at run time; the sound doesn't change.

import AVFoundation
import CoreAudio
import Darwin
import IOKit
import IOKit.hid
import CoreGraphics
import Foundation

// MARK: - Run state, keys, clock

var stopRequested = false
var skipRequested = false
var keyPressed = false
/// Leaving goes through the credits: the first Ctrl-C (or q, or esc) jumps there, the next one exits.
var jumpToCredits = false
var inCredits = false
func requestEnd() { if inCredits || jumpToCredits { stopRequested = true } else { jumpToCredits = true } }
func interrupted() -> Bool { stopRequested || skipRequested || jumpToCredits }

var timebase = mach_timebase_info_data_t()
mach_timebase_info(&timebase)
let ticksPerSecond = 1e9 * Double(timebase.denom) / Double(timebase.numer)
let t0 = mach_absolute_time()
func now() -> Double { Double(mach_absolute_time() - t0) / ticksPerSecond }
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

// MARK: - The haptic motor (MultitouchSupport, resolved at run time)

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
typealias FrameCallback = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32
typealias RegisterCallback = @convention(c) (UnsafeMutableRawPointer, FrameCallback) -> Void
typealias DeviceStart = @convention(c) (UnsafeMutableRawPointer, Int32) -> Void
typealias DeviceStop = @convention(c) (UnsafeMutableRawPointer) -> Void

let createList = sym("MTDeviceCreateList", CreateList.self)
let getID = sym("MTDeviceGetDeviceID", GetID.self)
let isBuiltIn = sym("MTDeviceIsBuiltIn", IsBuiltIn.self)
let actuatorCreate = sym("MTActuatorCreateFromDeviceID", ActuatorCreate.self)
let actuatorOpen = sym("MTActuatorOpen", ActuatorOpen.self)
let actuatorClose = sym("MTActuatorClose", ActuatorClose.self)
let actuationCreate = sym("MTActuationCreateFromDictionary", ActuationCreate.self)
let actuationPlay = sym("MTActuationActuate", ActuationPlay.self)
let registerCallback = sym("MTRegisterContactFrameCallback", RegisterCallback.self)
let deviceStart = sym("MTDeviceStart", DeviceStart.self)
let deviceStop = sym("MTDeviceStop", DeviceStop.self)

var deviceCount = 0
var motorDeviceID: UInt64 = 0
var motorBuiltIn = false
var deviceList: CFArray?
/// --external: play through an external Magic Trackpad instead of the built-in trackpad.
var preferExternal = false

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
    // --external: play only through an external trackpad (a Magic Trackpad), never the built-in one.
    if preferExternal {
        for d in ids where !d.builtIn {
            if let ref = actuatorCreate(d.id)?.takeRetainedValue(), actuatorOpen(ref) == 0 {
                motorDeviceID = d.id
                motorBuiltIn = d.builtIn
                return ref
            }
        }
        fail("""
        --external was given, but no external trackpad was found.
        Turn on your Magic Trackpad (2 or newer, the ones with Force Touch), connect it, and run it again.
        """)
    }
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
func play(_ tones: [(hz: Double, amp: Double)], ms: Double, level: Float) {
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
    live {
        $0.actuations += 1; $0.hz = first; $0.level = Double(level); $0.lastPlay = now()
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
    var device = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                          mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &device) == noErr else { return nil }
    var known = false
    var muted: UInt32 = 0
    size = 4
    addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    if AudioObjectHasProperty(device, &addr), AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &muted) == noErr {
        known = true
        if muted != 0 { return true }
    }
    // Volume: the main element, else the first channel.
    for element in [kAudioObjectPropertyElementMain, 1] {
        var volume: Float32 = 1
        size = 4
        addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
        if AudioObjectHasProperty(device, &addr), AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &volume) == noErr {
            return volume < 0.001
        }
    }
    return known ? false : nil
}

// MARK: - Touch (for "play it")

struct Contact { var down = false; var x: Float = 0; var y: Float = 0; var size: Float = 0 }
var touchLock = os_unfair_lock()
var currentContact = Contact()
var contact: Contact {
    os_unfair_lock_lock(&touchLock); defer { os_unfair_lock_unlock(&touchLock) }
    return currentContact
}
let touchCallback: FrameCallback = { _, data, count, _, _ in
    var best = Contact()
    if let data, count > 0 {
        for i in 0..<Int(count) {
            let rec = data.advanced(by: i * 96)
            let state = rec.load(fromByteOffset: 20, as: Int32.self)
            guard (3...5).contains(state) else { continue }
            best = Contact(down: true, x: rec.load(fromByteOffset: 32, as: Float.self),
                           y: rec.load(fromByteOffset: 36, as: Float.self), size: rec.load(fromByteOffset: 48, as: Float.self))
        }
    }
    os_unfair_lock_lock(&touchLock); currentContact = best; os_unfair_lock_unlock(&touchLock)
    return 0
}
/// Only the trackpad whose motor we opened.
func touchDevices() -> [UnsafeMutableRawPointer] {
    guard let deviceList, let getID else { return [] }
    return (0..<CFArrayGetCount(deviceList)).compactMap { i -> UnsafeMutableRawPointer? in
        guard let raw = CFArrayGetValueAtIndex(deviceList, i) else { return nil }
        let dev = UnsafeMutableRawPointer(mutating: raw)
        var id: UInt64 = 0
        return getID(dev, &id) == 0 && id == motorDeviceID ? dev : nil
    }
}
let unregisterCallback = sym("MTUnregisterContactFrameCallback", RegisterCallback.self)
func startTouch() -> Bool {
    guard let registerCallback, let deviceStart else { return false }
    let devs = touchDevices()
    let quiet = !terminalTaken
    if quiet { silenceOthers() }
    for d in devs { registerCallback(d, touchCallback); deviceStart(d, 0) }
    if quiet { usleep(200_000); unsilence() }
    return !devs.isEmpty
}
func stopTouch() {
    for d in touchDevices() {
        unregisterCallback?(d, touchCallback)
        deviceStop?(d)
    }
}

// MARK: - Speech analysis

struct Frame {
    var formants: [Double] = [500, 1500, 2500]
    var amps: [Double] = [1, 0.5, 0.25]
    var level: Float = 0
    var voiced = false
    var f0 = 110.0
}
let hop = 0.010
let sampleRate = 16000.0
var voiceName: String?

/// True if `say` has a voice by this name. (`say` quietly falls back to the default voice for unknown names.)
func voiceExists(_ name: String) -> Bool {
    let p = Process(), pipe = Pipe()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/say")
    p.arguments = ["-v", "?"]
    p.standardOutput = pipe
    guard (try? p.run()) != nil else { return true }   // can't check: let `say` decide
    let list = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    p.waitUntilExit()
    let wanted = name.lowercased()
    return list.split(separator: "\n").contains { line in
        let l = line.lowercased()
        return l.hasPrefix(wanted + " ") || l.hasPrefix(wanted + "\t")
    }
}

func render(_ text: String) -> [Frame] {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("nospeaker-\(getpid()).wav")
    defer { try? FileManager.default.removeItem(at: url) }
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/say")
    p.arguments = ["-o", url.path, "--file-format=WAVE", "--data-format=LEF32@16000"] + (voiceName.map { ["-v", $0] } ?? []) + [text]
    do { try p.run() } catch { fail("It couldn't run macOS's voice (/usr/bin/say), which it needs to talk.") }
    p.waitUntilExit()
    guard p.terminationStatus == 0, let file = try? AVAudioFile(forReading: url),
          let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
          (try? file.read(into: buf)) != nil, let ch = buf.floatChannelData?[0] else {
        if let voiceName {
            fail("There's no voice called \"\(voiceName)\" on this Mac.\nList the voices you have with: say -v '?'", headline: "nospeaker can't use that voice.")
        }
        fail("macOS's voice (say) couldn't speak that line.", headline: "nospeaker couldn't prepare its voice.")
    }
    var f = analyse(Array(UnsafeBufferPointer(start: ch, count: Int(buf.frameLength))))
    while let first = f.first, first.level == 0 { f.removeFirst() }
    while let last = f.last, last.level == 0 { f.removeLast() }
    return f
}

func lpc(_ x: [Double], order p: Int) -> ([Double], Double) {
    var r = [Double](repeating: 0, count: p + 1)
    for k in 0...p { var s = 0.0; for i in k..<x.count { s += x[i] * x[i - k] }; r[k] = s }
    var a = [Double](repeating: 0, count: p + 1); a[0] = 1
    guard r[0] > 1e-12 else { return (a, 0) }
    r[0] *= 1.0001
    var e = r[0]
    for i in 1...p {
        var acc = r[i]
        for j in 1..<i { acc += a[j] * r[i - j] }
        let k = -acc / e
        var na = a
        for j in 1..<i { na[j] = a[j] + k * a[i - j] }
        na[i] = k
        a = na
        e *= 1 - k * k
    }
    return (a, e)
}

struct C {
    var re: Double, im: Double
    static func + (l: C, r: C) -> C { C(re: l.re + r.re, im: l.im + r.im) }
    static func - (l: C, r: C) -> C { C(re: l.re - r.re, im: l.im - r.im) }
    static func * (l: C, r: C) -> C { C(re: l.re * r.re - l.im * r.im, im: l.re * r.im + l.im * r.re) }
    static func / (l: C, r: C) -> C {
        let d = r.re * r.re + r.im * r.im
        return C(re: (l.re * r.re + l.im * r.im) / d, im: (l.im * r.re - l.re * r.im) / d)
    }
}

func roots(_ a: [Double]) -> [C] {
    let p = a.count - 1
    var z = (0..<p).map { k -> C in
        let ang = 2 * Double.pi * Double(k) / Double(p) + 0.4
        return C(re: 0.9 * cos(ang), im: 0.9 * sin(ang))
    }
    func poly(_ x: C) -> C { var s = C(re: 1, im: 0); for k in 1...p { s = s * x + C(re: a[k], im: 0) }; return s }
    for _ in 0..<300 {
        var moved = 0.0
        for i in 0..<p {
            var d = C(re: 1, im: 0)
            for j in 0..<p where j != i { d = d * (z[i] - z[j]) }
            if d.re == 0 && d.im == 0 { d = C(re: 1e-12, im: 0) }
            let step = poly(z[i]) / d
            z[i] = z[i] - step
            moved = max(moved, abs(step.re) + abs(step.im))
        }
        if moved < 1e-10 { break }
    }
    return z
}

func analyse(_ x: [Float]) -> [Frame] {
    let win = Int(0.025 * sampleRate), hopN = Int(hop * sampleRate), order = 18
    let hamming = (0..<win).map { 0.54 - 0.46 * cos(2 * .pi * Double($0) / Double(win - 1)) }
    var frames: [Frame] = [], rmsList: [Double] = []
    var prev = Frame()
    var i = 0
    while i + win <= x.count {
        let seg = (0..<win).map { Double(x[i + $0]) }
        rmsList.append(sqrt(seg.reduce(0) { $0 + $1 * $1 } / Double(win)))
        var f = prev
        var zc = 0
        for k in 1..<win where (seg[k] >= 0) != (seg[k - 1] >= 0) { zc += 1 }
        var bestLag = 0, bestR = 0.0
        for lag in Int(sampleRate / 300)...Int(sampleRate / 70) where lag < win - 40 {
            var s = 0.0, ea = 0.0, eb = 0.0
            for k in 0..<(win - lag) { s += seg[k] * seg[k + lag]; ea += seg[k] * seg[k]; eb += seg[k + lag] * seg[k + lag] }
            let r = s / max(sqrt(ea * eb), 1e-12)
            if r > bestR { bestR = r; bestLag = lag }
        }
        f.voiced = bestR > 0.35 && Double(zc) / Double(win) < 0.22
        if f.voiced, bestLag > 0 { f.f0 = sampleRate / Double(bestLag) }
        var pe = [Double](repeating: 0, count: win)
        for k in 0..<win { pe[k] = (seg[k] - 0.97 * (k > 0 ? seg[k - 1] : 0)) * hamming[k] }
        let (a, err) = lpc(pe, order: order)
        var cands: [Double] = []
        if err > 0 {
            for z in roots(a) where z.im > 0 {
                let hz = atan2(z.im, z.re) * sampleRate / (2 * .pi)
                let bw = -log(max(1e-9, sqrt(z.re * z.re + z.im * z.im))) * sampleRate / .pi
                if hz > 150, hz < 4200, bw < 500 { cands.append(hz) }
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
                return 1 / max(sqrt(re * re + im * im), 1e-6)
            }
        }
        frames.append(f)
        prev = f
        i += hopN
    }
    let peak = rmsList.max() ?? 1
    for k in frames.indices {
        let rel = rmsList[k] / max(peak, 1e-9)
        frames[k].level = rel < 0.02 ? 0 : Float(min(1, pow(rel, 0.45)))
        if frames[k].level == 0 { frames[k].voiced = false }
    }
    func median(_ v: [Double]) -> Double { v.sorted()[v.count / 2] }
    let raw = frames
    for k in frames.indices {
        let lo = max(0, k - 2), hi = min(frames.count - 1, k + 2)
        for j in 0..<3 { frames[k].formants[j] = median((lo...hi).map { raw[$0].formants[j] }) }
        frames[k].f0 = min(250, max(70, median((lo...hi).map { raw[$0].f0 })))
    }
    return frames
}

/// A voiced frame as two tones, F1 and F2. Two rather than three: in a blind test two were clearer, and louder,
/// because the motor's strength is split fewer ways.
func voiceTones(_ f: Frame) -> [(hz: Double, amp: Double)] {
    let w = [f.amps[0], f.amps[1] * 1.8]
    let sum = max(w[0] + w[1], 1e-9)
    return [(f.formants[0], w[0] / sum), (f.formants[1], w[1] / sum)]
}

// MARK: - Live state shared with the screen

enum Scene { case intro, heart, sweep, talk, sing, beat, rap, yourTurn, touch, say, outro }

struct LiveState {
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
let liveLock = NSLock()
var liveState = LiveState()
func live(_ f: (inout LiveState) -> Void) { liveLock.lock(); f(&liveState); liveLock.unlock() }
func snapshot() -> LiveState { liveLock.lock(); defer { liveLock.unlock() }; return liveState }

let partCount = 10
/// Moves the show to a new part: what the screen draws, and the part number and name in the status bar.
func enter(_ scene: Scene, _ part: Int, _ name: String) {
    skipRequested = false
    live { $0.scene = scene; $0.part = part; $0.partName = name }
}
func caption(_ text: String, seconds: Double) { live { $0.caption = text; $0.captionStart = now(); $0.captionDur = seconds } }

// MARK: - Lights (--lights): the keyboard backlight, the Caps Lock light and the screen play along

/// What the music tells the lights, sent by the sound loops as it happens. A cue says what's in the music (a beat,
/// a note, a syllable), not which part of the show is on, so anything that makes sound can drive the lights.
enum LightCue {
    /// A beat (a kick, a heartbeat): the keyboard jumps to this strength (0…1), then fades.
    case beat(Double)
    /// A note of the tune that sounds for `seconds`: a keyboard pulse, and Caps Lock on while it sounds.
    case note(seconds: Double, strength: Double)
    /// The note still sounds (one whose length isn't known ahead): Caps Lock stays on this much longer.
    case held(seconds: Double)
    /// A small hit (a snare, a hi-hat): Caps Lock blinks.
    case tick
    /// A syllable starts: a keyboard pulse of this strength, and a Caps Lock blink.
    case syllable(Double)
    /// The pitch now, 0 (low) to 1 (high): the keyboard's brightness follows it for as long as these keep coming.
    case pitch(Double)
    /// What the screen does from now on.
    case screen(ScreenCue)
}

/// The screen sets the stage and then steps back, so the keyboard stays the thing to watch (a bright screen drowns
/// its light). All of it is slow on purpose: at most one faded flicker a beat, never a strobe, since fast flashing
/// can trigger seizures in people with photosensitive epilepsy.
enum ScreenCue {
    /// Back to the brightness it had before the show, eased over 0.6 s.
    case rest
    /// Dark: the display's backlight off.
    case dark
    /// A hard cut to full brightness for `seconds`, then dark.
    case full(seconds: Double)
    /// Up to `peak` (0…1) at once, then a fade that reaches dark by itself after `seconds`.
    case flicker(peak: Double, seconds: Double)
}

/// The latest cues, written by `lightCue` and read by the light threads.
struct LightState {
    var pulseAt = -9.0, pulse = 0.0            // the last keyboard pulse, and how strong
    var pitchAt = -9.0, pitch = 0.0            // the last pitch
    var capsFrom = -9.0, capsUntil = -9.0      // Caps Lock is on between these
    var screen = ScreenCue.rest, screenAt = -9.0
}
let lightLock = NSLock()
var lightState = LightState()
var lightsRunning = false
/// The running light threads: each enters on start and leaves when its loop ends.
let lightThreads = DispatchGroup()

/// Sends a cue to the lights. Called from the sound loops, so it only notes the time; the light threads do the
/// slow part. Without --lights it does nothing.
func lightCue(_ cue: LightCue) {
    guard lightsRunning else { return }
    let t = now()
    lightLock.lock(); defer { lightLock.unlock() }
    func pulse(_ s: Double) {
        if t - lightState.pulseAt > 0.02 || s > lightState.pulse { lightState.pulse = s }
        lightState.pulseAt = t
    }
    func caps(for seconds: Double) {
        // A note right after one that's still lit goes dark briefly first, so repeated notes show as blinks.
        let gap = t < lightState.capsUntil + 0.04 ? min(0.04, seconds / 3) : 0
        lightState.capsFrom = t + gap
        lightState.capsUntil = t + seconds
    }
    switch cue {
    case .beat(let s): pulse(s)
    case .note(let seconds, let s): pulse(s); caps(for: seconds)
    case .held(let seconds): lightState.capsUntil = max(lightState.capsUntil, t + seconds)
    case .tick: caps(for: 0.07)
    case .syllable(let s): pulse(s); caps(for: 0.08)
    case .pitch(let p): lightState.pitch = p; lightState.pitchAt = t
    case .screen(let s): lightState.screen = s; lightState.screenAt = t
    }
}

/// A tone's place in the motor's range, 100 Hz → 0 to 4 kHz → 1, on a log scale (as the ear hears pitch).
func tonePitch(_ hz: Double) -> Double { min(1, max(0, log(hz / 100) / log(40))) }

/// Finds where syllables start in speech, one 10 ms frame at a time: the level jumping well above where it's
/// been lately, or sound after silence. Each frame counts once, however many motor periods it spans.
struct SyllableFinder {
    private var slow = 0.0, lastFrame = -1, lastHit = -99
    mutating func feed(_ level: Float, frame: Int) -> Double? {
        guard frame != lastFrame else { return nil }
        lastFrame = frame
        let l = Double(level)
        defer { slow += (l - slow) * 0.15 }    // remembers about the last 60 ms
        guard l > 0.1, l > slow * 1.4 + 0.08, frame - lastHit >= 9 else { return nil }    // at most 11 a second
        lastHit = frame
        return l
    }
}

/// The keyboard backlight, through KeyboardBrightnessClient: the private CoreBrightness class behind the keyboard
/// brightness slider in Control Center. Resolved at run time like MultitouchSupport, so nothing is linked, and on a
/// Mac without it (or a macOS that renamed it) `init` returns nil and the show plays without it.
final class KeyboardBacklight {
    private typealias CopyIDs = @convention(c) (AnyObject, Selector) -> Unmanaged<NSArray>?
    private typealias GetLevel = @convention(c) (AnyObject, Selector, UInt64) -> Float
    private typealias GetFlag = @convention(c) (AnyObject, Selector, UInt64) -> ObjCBool
    private typealias SetFlag = @convention(c) (AnyObject, Selector, ObjCBool, UInt64) -> ObjCBool
    private typealias SetLevel = @convention(c) (AnyObject, Selector, Float, Int32, ObjCBool, UInt64) -> ObjCBool

    let id: UInt64
    private let client: NSObject
    private let setLevel: SetLevel
    private let setSel: Selector
    // What the keyboard was doing before, put back by `restore()`.
    private var original: Float = 0.5, wasAuto = false, wasIdleSuspended = false
    private var began = false

    init?() {
        guard dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_NOW) != nil,
              let cls = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type else { return nil }
        let c = cls.init()
        let sel = NSSelectorFromString("setBrightness:fadeSpeed:commit:forKeyboard:")
        guard c.responds(to: sel) else { return nil }
        // The built-in keyboard's backlight ID (an external keyboard can have one too).
        var ids: [UInt64] = []
        let copySel = NSSelectorFromString("copyKeyboardBacklightIDs")
        if c.responds(to: copySel),
           let list = unsafeBitCast(c.method(for: copySel), to: CopyIDs.self)(c, copySel)?.takeRetainedValue() {
            ids = list.compactMap { ($0 as? NSNumber)?.uint64Value }
        }
        guard !ids.isEmpty else { return nil }
        client = c
        setSel = sel
        setLevel = unsafeBitCast(c.method(for: sel), to: SetLevel.self)
        id = ids.first { KeyboardBacklight.ask(c, "isKeyboardBuiltIn:", $0) ?? false } ?? ids[0]
    }

    /// Asks a yes/no question about one keyboard, or nil if this macOS doesn't have that method.
    private static func ask(_ c: NSObject, _ name: String, _ kb: UInt64) -> Bool? {
        let sel = NSSelectorFromString(name)
        guard c.responds(to: sel) else { return nil }
        return unsafeBitCast(c.method(for: sel), to: GetFlag.self)(c, sel, kb).boolValue
    }
    private func flag(_ name: String) -> Bool? { KeyboardBacklight.ask(client, name, id) }
    private func setFlag(_ name: String, _ on: Bool) {
        let sel = NSSelectorFromString(name)
        guard client.responds(to: sel) else { return }
        _ = unsafeBitCast(client.method(for: sel), to: SetFlag.self)(client, sel, ObjCBool(on), id)
    }

    /// Takes the backlight over: remembers its level, and turns off auto-brightness (the light sensor would fight
    /// the show) and idle dimming (hands are off the keyboard while it plays). `restore()` puts all three back.
    func begin() {
        guard !began else { return }
        began = true
        wasAuto = flag("isAutoBrightnessEnabledForKeyboard:") ?? false
        wasIdleSuspended = flag("isIdleDimmingSuspendedOnKeyboard:") ?? false
        // Suspending idle dimming first wakes a keyboard that has gone dark from idling, so the level read next is
        // the real one. Read while dimmed, it's 0, and restoring 0 would leave the keyboard dark.
        if !wasIdleSuspended { setFlag("suspendIdleDimming:forKeyboard:", true); usleep(150_000) }
        let sel = NSSelectorFromString("brightnessForKeyboard:")
        if client.responds(to: sel) { original = unsafeBitCast(client.method(for: sel), to: GetLevel.self)(client, sel, id) }
        if wasAuto { setFlag("enableAutoBrightness:forKeyboard:", false) }
    }

    /// Sets the brightness now (0…1), with no fade and without saving it as the user's setting.
    func set(_ level: Double) {
        _ = setLevel(client, setSel, Float(min(1, max(0, level))), 0, false, id)
    }

    /// Puts it back. It never commits a level, so the user's saved brightness is never written.
    func restore() {
        guard began else { return }
        began = false
        _ = setLevel(client, setSel, original, 0, false, id)
        usleep(100_000)
        if !wasIdleSuspended { setFlag("suspendIdleDimming:forKeyboard:", false) }
        if wasAuto { setFlag("enableAutoBrightness:forKeyboard:", true) }
    }
}

/// The Caps Lock key's light, set directly through IOKit HID. Only the light: Caps Lock itself (what you type)
/// doesn't change, and the light goes back to how it was at the end.
final class CapsLight {
    private let manager: IOHIDManager
    private let device: IOHIDDevice
    private let led: IOHIDElement
    private let original: Int
    private var shown = -1

    /// Nil when there's no keyboard with a Caps Lock light, or macOS won't let this program set it.
    init?() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard] as CFDictionary)
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess,
              let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return nil }
        // The built-in keyboard first, else any keyboard with a Caps Lock light.
        func builtIn(_ d: IOHIDDevice) -> Bool { (IOHIDDeviceGetProperty(d, "Built-In" as CFString) as? Bool) ?? false }
        for d in devices.sorted(by: { builtIn($0) && !builtIn($1) }) {
            let match = [kIOHIDElementUsagePageKey: kHIDPage_LEDs, kIOHIDElementUsageKey: kHIDUsage_LED_CapsLock] as CFDictionary
            guard let e = (IOHIDDeviceCopyMatchingElements(d, match, 0) as? [IOHIDElement])?.first else { continue }
            let placeholder = IOHIDValueCreateWithIntegerValue(kCFAllocatorDefault, e, 0, 0)
            var value = Unmanaged.passUnretained(placeholder)
            let ok = withExtendedLifetime(placeholder) { IOHIDDeviceGetValue(d, e, &value) == kIOReturnSuccess }
            let was = ok ? IOHIDValueGetIntegerValue(value.takeUnretainedValue()) : 0
            // Asks once, before the show, by setting the light to what it already is: macOS may refuse a program
            // without Input Monitoring, and during the show there'd be nowhere to say so.
            let r = IOHIDDeviceSetValue(d, e, IOHIDValueCreateWithIntegerValue(kCFAllocatorDefault, e, mach_absolute_time(), was))
            guard r == kIOReturnSuccess else { return nil }
            device = d; led = e; original = was
            return
        }
        return nil
    }
    func set(_ on: Bool) {
        let v = on ? 1 : 0
        guard v != shown else { return }
        shown = v
        _ = IOHIDDeviceSetValue(device, led, IOHIDValueCreateWithIntegerValue(kCFAllocatorDefault, led, mach_absolute_time(), v))
    }
    func restore() { shown = -1; set(original != 0) }
}

/// The MacBook's own, built-in display, even when an external display is the main one (its brightness can't be set
/// this way, and the trackpad and keyboard are on the MacBook anyway).
func showDisplay() -> CGDirectDisplayID {
    var ids = [CGDirectDisplayID](repeating: 0, count: 16)
    var count: UInt32 = 0
    CGGetOnlineDisplayList(16, &ids, &count)
    return ids.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 } ?? CGMainDisplayID()
}

/// The screen's brightness, moved as the brightness keys move it, through DisplayServices (a private framework,
/// resolved at run time like the others): the backlight itself dims and brightens, so it stays smooth. (The picture's
/// gamma steps visibly on some displays, and resetting it resets other apps' gamma too, so it isn't used.)
/// Nil without DisplayServices; the show then leaves the screen alone.
final class ScreenLight {
    private typealias GetBrightness = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness = @convention(c) (UInt32, Float) -> Int32
    private let display = showDisplay()
    private let put: SetBrightness
    /// Where the screen was when it started (0…1): it goes back there at the end.
    let rest: Double
    private var shown: Double

    init?() {
        guard let ds = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW),
              let g = dlsym(ds, "DisplayServicesGetBrightness"), let p = dlsym(ds, "DisplayServicesSetBrightness") else { return nil }
        var b: Float = 0
        guard unsafeBitCast(g, to: GetBrightness.self)(display, &b) == 0 else { return nil }
        put = unsafeBitCast(p, to: SetBrightness.self)
        rest = min(1, max(0, Double(b)))
        shown = rest
    }
    /// 0…1: dark (the backlight off) to full.
    func set(_ level: Double) {
        let l = min(1, max(0, level))
        guard abs(l - shown) >= 0.002 || (l == 0 && shown != 0) else { return }    // always all the way to 0
        shown = l
        _ = put(display, Float(l))
    }
    func restore() { shown = rest; _ = put(display, Float(rest)) }
}
var backlight: KeyboardBacklight?
var capsLight: CapsLight?
var screenLight: ScreenLight?

/// Brightness steps look even to the eye when the level is raised to about this power (the eye is far more
/// sensitive to changes in the dark).
let lightGamma = 1.8

/// The lights run on their own threads, apart from the motor's loops: setting the backlight is a message to
/// corebrightnessd, too slow to send from inside a loop that times the motor to the microsecond.
func startLights() {
    guard !lightsRunning, backlight != nil || capsLight != nil || screenLight != nil else { return }
    backlight?.begin()
    lightsRunning = true
    // Keyboard and Caps Lock, 100 times a second. Each sends only real changes, so a steady light costs nothing.
    let th = Thread {
        defer { lightThreads.leave() }
        var pulse = 0.0, seenPulse = -9.0, follow = 0.0, shown = -1.0, last = now()
        while lightsRunning {
            let t = now(), dt = t - last
            last = t
            lightLock.lock(); let s = lightState; lightLock.unlock()
            // Pulses jump to their strength, then fade out over ~150 ms.
            if s.pulseAt != seenPulse { seenPulse = s.pulseAt; pulse = max(pulse, s.pulse) }
            pulse *= exp(-dt / 0.15)
            // Pitch, while it's being sent: from a dim floor up, rising fast and falling a little slower.
            let target = t - s.pitchAt < 0.08 ? 0.15 + 0.85 * s.pitch : 0
            follow += (target - follow) * (1 - exp(-dt / (target > follow ? 0.03 : 0.12)))
            let b = pow(min(1, max(pulse, follow)), lightGamma)
            if let bl = backlight, abs(b - shown) >= 0.015 || (b < 0.01 && shown >= 0.01) || (b == 1 && shown != 1) { bl.set(b); shown = b }
            capsLight?.set(t >= s.capsFrom && t < s.capsUntil)
            usleep(10_000)
        }
    }
    th.qualityOfService = .userInteractive
    lightThreads.enter()
    th.start()
    // The screen on a thread of its own, 60 times a second, so nothing else can make it stutter.
    guard let sc = screenLight else { return }
    let st = Thread {
        defer { lightThreads.leave() }
        var level = sc.rest, easeFrom = sc.rest, seenCue = -9.0
        while lightsRunning {
            let t = now()
            lightLock.lock(); let cue = lightState.screen, at = lightState.screenAt; lightLock.unlock()
            if at != seenCue { seenCue = at; easeFrom = level }
            let age = t - at
            switch cue {
            case .rest:
                let k = min(1, max(0, age / 0.6))
                level = easeFrom + (sc.rest - easeFrom) * k * k * (3 - 2 * k)    // smoothstep: eases in and out
            case .dark:
                level = 0
            case .full(let seconds):
                level = age < seconds ? 1 : 0
            case .flicker(let peak, let seconds):
                // Up in 30 ms, then quick at first and gentle at the end, so there's nothing left to cut at 0.
                level = age < 0.03 ? peak * age / 0.03 : peak * pow(max(0, 1 - (age - 0.03) / max(0.01, seconds - 0.03)), 2)
            }
            sc.set(level)
            usleep(16_000)
        }
    }
    st.qualityOfService = .userInteractive
    lightThreads.enter()
    st.start()
}

/// Puts every light back as it was. The screen first eases back to its own brightness (unless it's ending in a
/// hurry), then the threads stop, and only once they really have does each light go back: a thread caught in the
/// middle of a slow call could otherwise land its last write after the restore and undo it.
func stopLights() {
    guard lightsRunning else { return }
    if screenLight != nil && !stopRequested { lightCue(.screen(.rest)); usleep(650_000) }
    lightsRunning = false
    _ = lightThreads.wait(timeout: .now() + 1)
    backlight?.restore()
    capsLight?.restore()
    screenLight?.restore()
}

// MARK: - Notes

func hz(_ note: String) -> Double {
    let names: [String: Int] = ["C": -9, "C#": -8, "D": -7, "D#": -6, "E": -5, "F": -4, "F#": -3, "G": -2, "G#": -1, "A": 0, "A#": 1, "B": 2]
    guard let octave = Int(String(note.last!)), let semi = names[String(note.dropLast())] else { return 440 }
    return 440 * pow(2, Double(semi + (octave - 4) * 12) / 12)
}

// MARK: - The show's parts (sound)

/// A felt-and-heard thump: a fast pitch dive.
func thump(_ amp: Double) {
    let start = mach_absolute_time()
    var t = 0.0
    while t < 0.11 && !stopRequested {
        let f = 120 + 780 * exp(-t / 0.02)
        let seg = 1 / f
        play([(f, 1)], ms: seg * 1000, level: Float(amp * exp(-t / 0.05)))
        t += seg
        waitUntil(start + UInt64(t * ticksPerSecond))
    }
}

func heartbeat() {
    for i in 0..<2 where !interrupted() {
        // The first sound of the show: the screen cuts to full for a beat, then goes dark; the next beat only glows.
        lightCue(.screen(i == 0 ? .full(seconds: 0.6) : .flicker(peak: 0.25, seconds: 0.5)))
        lightCue(.note(seconds: 0.12, strength: 1)); thump(1); pause(0.17)
        lightCue(.note(seconds: 0.12, strength: 0.7)); thump(0.7); pause(0.75)
    }
}

func sweep(seconds: Double = 6) {
    let start = mach_absolute_time()
    var t = 0.0
    while t < seconds && !interrupted() {
        let f = 100 * pow(40, t / seconds)
        let seg = max(1, (0.02 * f).rounded()) / f
        play([(f, 1)], ms: seg * 1000, level: 1)
        lightCue(.pitch(tonePitch(f)))
        t += seg
        waitUntil(start + UInt64(t * ticksPerSecond))
    }
}

func talk(_ frames: [Frame], text: String) {
    guard !frames.isEmpty else { return }
    let total = Double(frames.count) * hop
    caption(text, seconds: total)
    let start = mach_absolute_time()
    var t = 0.0
    var syllables = SyllableFinder()
    while t < total && !interrupted() {
        let i = min(frames.count - 1, Int(t / hop))
        let f = frames[i]
        if let s = syllables.feed(f.level, frame: i) { lightCue(.syllable(s)) }
        var step = 0.005
        if f.level > 0 {
            if f.voiced {
                step = 1 / f.f0
                play(voiceTones(f), ms: step * 1000, level: f.level)
                live { $0.f0 = f.f0; $0.f1 = f.formants[0]; $0.f2 = f.formants[1] }
            } else {
                step = 0.004
                play((0..<3).map { _ in (Double.random(in: 2700...4300), 1.0) }, ms: step * 1000, level: f.level * 0.7)
            }
        }
        t += step
        waitUntil(start + UInt64(t * ticksPerSecond))
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
        if i == 0 || phraseEnds.contains(i - 1) { lightCue(.screen(.flicker(peak: 0.45, seconds: beat))) }    // a phrase starts
        lightCue(.note(seconds: sounding, strength: 1))
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
            waitUntil(start + UInt64(t * ticksPerSecond))
        }
        previous = phraseEnds.contains(i) ? nil : target
        live { $0.noteRow = -1 }
        at += length
        if t < at { t = at; waitUntil(start + UInt64(t * ticksPerSecond)) }
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
    /// True while the rapped voice sounds at `t` (the hi-hats drop out then).
    func rapIsTalking(at t: Double) -> Bool {
        guard t >= rapStart else { return false }
        let idx = Int((t - rapStart) / hop)
        return idx < rap.count && rap[idx].level > 0
    }
    var t = 0.0, next = 0, rapping = false
    var ringing: [Hit] = []
    var litBar = -1
    let start = mach_absolute_time()
    while t < end && !stopRequested {
        if (skipRequested && !rapping) || jumpToCredits { break }
        while next < hits.count, hits[next].t <= t + 0.0005 {
            let h = hits[next]
            ringing.append(h)
            let when = now()
            live { if h.kind == 0 { $0.kick = when } else if h.kind == 1 { $0.snare = when } else { $0.hat = when } }
            // Lights: the keyboard on the kick, Caps Lock on the snare and the hi-hats (not the ones the voice mutes).
            if h.kind == 0 { lightCue(.beat(h.acc)) } else if h.kind == 1 || !rapIsTalking(at: t) { lightCue(.tick) }
            next += 1
        }
        ringing.removeAll { t - $0.t > 0.2 }
        let i16 = Int(t / s16)
        // The screen: a flicker out of the dark on each bar's first beat, dark again by the next beat.
        if i16 / 16 != litBar { litBar = i16 / 16; lightCue(.screen(.flicker(peak: 0.45, seconds: 4 * s16))) }
        live { $0.step = i16 % 16; $0.bar = i16 / 16 }
        if !rapping, t >= rapStart {
            rapping = true
            enter(.rap, 6, "RAP")
            caption(rapText, seconds: Double(rap.count) * hop)
        }
        var frame: Frame?
        if t >= rapStart { let idx = Int((t - rapStart) / hop); if idx < rap.count { frame = rap[idx] } }
        let talking = (frame?.level ?? 0) > 0
        let bass = bassHz[(i16 / 16) % bassHz.count]
        var carrier = bass
        if let f = frame, talking, f.voiced { carrier = f.f0 }
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
        waitUntil(start + UInt64(t * ticksPerSecond))
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
    while now() < waitEnd && !interrupted() && !contact.down { usleep(5000) }
    guard contact.down else { live { $0.touchMissed = true }; pause(1.5); return }
    let endAt = now() + 12
    live { $0.touchSeen = true; $0.touchEnds = endAt }
    let scale = ["G5", "A5", "B5", "C6", "E6", "F6", "G6", "A6", "B6", "C7"].map(hz)
    var current = scale[4]
    var lastDown = false, downAt = 0.0, lastIdx = -1
    while now() < endAt && !interrupted() {
        let c = contact
        live { $0.touchDown = c.down; if c.down { $0.touchX = Double(c.x); $0.touchY = Double(c.y) } }
        guard c.down else { lastDown = false; usleep(3000); continue }
        let idx = min(scale.count - 1, max(0, Int((Double(c.x) * Double(scale.count)).rounded(.down))))
        // Lights: a new note (the finger comes down, or slides onto another) pulses the keyboard; Caps Lock stays on
        // while the finger holds it.
        if !lastDown || idx != lastIdx { lightCue(.note(seconds: 0.08, strength: min(1, 0.5 + Double(c.size)))) }
        else { lightCue(.held(seconds: 0.08)) }
        lastIdx = idx
        if !lastDown { downAt = now() }
        lastDown = true
        let target = scale[idx]
        current *= pow(target / current, 0.3)
        let age = now() - downAt
        let depth = 0.05 + 0.45 * Double(max(0, min(1, c.y)))
        let f = current * pow(2, depth * sin(2 * .pi * 6 * age) / 12)
        let level = min(1, max(0.5, 0.3 + Double(c.size) * 0.8))
        let seg = max(1, (0.02 * f).rounded()) / f
        let t0 = mach_absolute_time()
        play([(f, 1)], ms: seg * 1000, level: Float(level))
        live { $0.noteName = noteName(f) }
        waitUntil(t0 + UInt64(seg * ticksPerSecond))
    }
    live { $0.touchDown = false }
}

func noteName(_ f: Double) -> String {
    let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    let midi = Int((69 + 12 * log2(f / 440)).rounded())
    return names[(midi % 12 + 12) % 12] + String(midi / 12 - 1)
}

/// A sparkle to close: an arpeggio up, then the motor's purest note.
func sparkle() {
    for n in ["A5", "C6", "E6", "A6", "C7"] where !stopRequested {
        let f = hz(n)
        let seg = (0.07 * f).rounded() / f
        lightCue(.note(seconds: seg, strength: 0.9))
        play([(f, 1)], ms: seg * 1000, level: 0.9)
        let end = mach_absolute_time() + UInt64(seg * ticksPerSecond)
        waitUntil(end)
    }
    lightCue(.note(seconds: 0.45, strength: 1))
    let start = mach_absolute_time()
    var t = 0.0
    while t < 0.6 && !stopRequested {
        let seg = (0.02 * 3951).rounded() / 3951
        play([(3951, 1)], ms: seg * 1000, level: Float(exp(-t / 0.18)))
        t += seg
        waitUntil(start + UInt64(t * ticksPerSecond))
    }
}

/// Lines to try in Say anything, shown one at a time in the empty box. Tab types the one showing.
let saySuggestions = ["can you hear me?", "please stop clicking me", "this is not a speaker", "nobody believes me",
                      "i live under the glass", "hello from the trackpad"]
func saySuggestion(at t: Double) -> String { saySuggestions[Int(t / 3) % saySuggestions.count] }

/// Say anything: you type a line and the trackpad says it. Up to five lines; return on an empty line or esc
/// goes to the credits, and so do 25 seconds without typing.
func sayAnything() {
    for _ in 0..<5 where !stopRequested && !jumpToCredits {
        live { $0.inputActive = true; $0.inputText = ""; $0.inputSubmitted = false; $0.sayStatus = "typing"; $0.caption = "" }
        var lastChange = now(), lastText = ""
        while !stopRequested && !jumpToCredits {
            let st = snapshot()
            if st.inputSubmitted || st.inputDone { break }
            if st.inputText != lastText { lastText = st.inputText; lastChange = now() }
            if now() - lastChange > 25 { live { $0.inputDone = true }; break }
            usleep(20_000)
        }
        let st = snapshot()
        live { $0.inputActive = false }
        let text = st.inputText.trimmingCharacters(in: .whitespaces)
        if st.inputDone || text.isEmpty || stopRequested || jumpToCredits { break }
        live { $0.sayStatus = "preparing" }
        let frames = render(text)
        live { $0.sayStatus = "speaking"; $0.sayCount += 1 }
        talk(frames, text: text)
        pause(0.6)
    }
    live { $0.inputActive = false }
}

// MARK: - Music from a MIDI file (--music)

/// A note of the music: when (seconds), what (Hz), which MIDI channel (from 0; 9 is the drums), how loud (0…1).
struct ScoreNote { var start: Double; var end: Double; var hz: Double; var ch: Int; var gain: Double }
/// A drum hit. kind: 0 bass drum or tom, 1 snare or clap, 2 cymbal or hi-hat.
struct ScoreHit { var t: Double; var kind: Int }
/// A beat (a quarter note, from the file's tempo), and whether it starts a bar.
typealias Beat = (t: Double, downbeat: Bool)
struct Score { var notes: [ScoreNote]; var hits: [ScoreHit]; var beats: [Beat]; var end: Double; var title: String }
/// What plays, from 0 to `length` seconds.
typealias Piece = (notes: [ScoreNote], hits: [ScoreHit], beats: [Beat], length: Double)
/// --parts 3,4: the channels the motor plays, numbered from 1 as music apps show them (10 is the drums). nil: all.
var musicParts: Set<Int>?
/// --no-drums turns this off.
var scoreDrums = true

/// Reads a standard MIDI file (format 0 or 1) into notes and drum hits, through its tempo changes. Each note's
/// loudness is its velocity, squared (closer to how loud it sounds). Channel 10 is drums: kicks and toms, snares
/// and claps, cymbals and hi-hats become the three kinds of hit; other drums are left out. Nothing is stored in
/// this program: the music comes from your file.
func loadMIDI(_ path: String) -> Score {
    guard let d = FileManager.default.contents(atPath: (path as NSString).expandingTildeInPath) else {
        fail("There's no file at \(path).", headline: "nospeaker can't open that music.", code: 66)
    }
    let b = [UInt8](d)
    func bad() -> Never { fail("\(path) looks like a MIDI file but couldn't be read.", headline: "nospeaker can't play that music.", code: 65) }
    guard b.starts(with: Array("MThd".utf8)) else { fail("\(path) isn't a MIDI file (.mid).", headline: "nospeaker can't play that music.", code: 65) }
    func u16(_ o: Int) -> Int { o + 2 <= b.count ? Int(b[o]) << 8 | Int(b[o + 1]) : 0 }
    func u32(_ o: Int) -> Int { o + 4 <= b.count ? u16(o) << 16 | u16(o + 2) : 0 }
    let tracks = u16(10), division = u16(12)
    guard division & 0x8000 == 0, division > 0 else {
        fail("This MIDI file counts time in SMPTE frames, which this doesn't read.", headline: "nospeaker can't play that music.", code: 65)
    }
    struct Ev { var tick: Int; var order: Int; var status: UInt8; var a: UInt8; var b: UInt8 }
    var events: [Ev] = [], tempos: [(tick: Int, usPerBeat: Double)] = [], title = ""
    var pos = 14 + max(0, u32(4) - 6)
    for _ in 0..<tracks {
        guard pos + 8 <= b.count, b[pos..<(pos + 4)].elementsEqual("MTrk".utf8) else { break }
        let end = min(b.count, pos + 8 + u32(pos + 4))
        var p = pos + 8, tick = 0, running: UInt8 = 0
        func vlq() -> Int { var v = 0; while p < end { let c = b[p]; p += 1; v = v << 7 | Int(c & 0x7F); if c < 0x80 { break } }; return v }
        while p < end {
            tick += vlq()
            guard p < end else { break }
            let c = b[p]
            if c == 0xFF {    // a meta event: the tempo and the title are the ones used
                guard p + 1 < end else { bad() }
                let type = b[p + 1]; p += 2
                let len = vlq()
                guard p + len <= end else { bad() }
                if type == 0x51, len == 3 { tempos.append((tick, Double(Int(b[p]) << 16 | Int(b[p + 1]) << 8 | Int(b[p + 2])))) }
                if type == 0x03, title.isEmpty { title = String(decoding: b[p..<(p + len)], as: UTF8.self) }
                p += len
            } else if c == 0xF0 || c == 0xF7 {    // system exclusive: skipped
                p += 1
                let len = vlq()    // first: vlq() moves p, so p += vlq() would rest on evaluation order
                p += len
            } else {
                if c & 0x80 != 0 { running = c; p += 1 }
                guard running != 0 else { bad() }
                let kind = running & 0xF0, two = kind != 0xC0 && kind != 0xD0
                guard p + (two ? 1 : 0) < end else { break }
                events.append(Ev(tick: tick, order: events.count, status: running, a: b[p], b: two ? b[p + 1] : 0))
                p += two ? 2 : 1
            }
        }
        pos = end
    }
    // Ticks → seconds through the tempo map (120 beats a minute until the first tempo change).
    tempos.sort { $0.tick < $1.tick }
    if tempos.first?.tick != 0 { tempos.insert((0, 500_000), at: 0) }
    var marks: [(tick: Int, sec: Double, usPerBeat: Double)] = []
    for t in tempos {
        let sec = marks.last.map { $0.sec + Double(t.tick - $0.tick) * $0.usPerBeat / 1e6 / Double(division) } ?? 0
        marks.append((t.tick, sec, t.usPerBeat))
    }
    func seconds(_ tick: Int) -> Double {
        let m = marks.last { $0.tick <= tick } ?? marks[0]
        return m.sec + Double(tick - m.tick) * m.usPerBeat / 1e6 / Double(division)
    }
    events.sort { ($0.tick, $0.order) < ($1.tick, $1.order) }
    var open: [Int: [(start: Double, vel: UInt8)]] = [:]
    var notes: [ScoreNote] = [], hits: [ScoreHit] = [], last = 0.0
    for e in events {
        let ch = Int(e.status & 0x0F), kind = e.status & 0xF0, t = seconds(e.tick)
        last = max(last, t)
        if kind == 0x90 && e.b > 0 {
            if ch == 9 {
                switch e.a {
                case 35, 36, 41, 43, 45, 47, 48, 50: hits.append(ScoreHit(t: t, kind: 0))
                case 37, 38, 39, 40: hits.append(ScoreHit(t: t, kind: 1))
                case 42, 44, 46, 49, 51, 52, 53, 55, 57, 59: hits.append(ScoreHit(t: t, kind: 2))
                default: break
                }
            } else {
                open[ch << 8 | Int(e.a), default: []].append((t, e.b))
            }
        } else if kind == 0x80 || kind == 0x90, ch != 9, var q = open[ch << 8 | Int(e.a)], !q.isEmpty {
            let n = q.removeFirst()
            open[ch << 8 | Int(e.a)] = q
            let v = Double(n.vel) / 127
            notes.append(ScoreNote(start: n.start, end: max(t, n.start + 0.01), hz: 440 * pow(2, (Double(e.a) - 69) / 12), ch: ch, gain: v * v))
        }
    }
    notes.sort { ($0.start, $0.ch) < ($1.start, $1.ch) }
    // The beats: every quarter note by the tempo map, a bar every four (the usual 4/4).
    var beats: [Beat] = []
    var beat = 0
    while seconds(beat * division) <= last {
        beats.append((seconds(beat * division), beat % 4 == 0))
        beat += 1
    }
    // The title goes to the terminal: no control characters from the file.
    title = String(String.UnicodeScalarView(title.unicodeScalars.filter { $0.value >= 32 && $0.value != 127 }))
    return Score(notes: notes, hits: hits, beats: beats, end: last, title: title)
}

/// Just one stretch of the file, from `a` to `b` seconds in its own time, with the notes already sounding at `a`.
func excerpt(_ s: Score, from a: Double, to b: Double) -> Piece {
    let notes = s.notes.filter { $0.start < b && $0.end > a + 0.001 }.map { n -> ScoreNote in
        var m = n; m.start = max(0, n.start - a); m.end = min(n.end, b) - a; return m
    }
    let hits = s.hits.filter { $0.t >= a - 0.001 && $0.t < b }.map { ScoreHit(t: $0.t - a, kind: $0.kind) }
    let beats = s.beats.filter { $0.t >= a - 0.001 && $0.t < b }.map { (t: $0.t - a, downbeat: $0.downbeat) }
    return (notes, hits, beats, b - a)
}

/// Plays a piece: the channels chosen with --parts (the drums when 10 is among them, or with no --parts), unless
/// --no-drums. It starts 50 ms from now, on the mach clock, so anything else can start on the same moment.
func perform(_ piece: Piece, fadeOut: Double = 0) {
    let start = mach_absolute_time() + UInt64(0.05 * ticksPerSecond)
    let notes = musicParts.map { p in piece.notes.filter { p.contains($0.ch + 1) } } ?? piece.notes
    let hits = scoreDrums && (musicParts?.contains(10) ?? true) ? piece.hits : []
    playScore(notes, hits: hits, beats: piece.beats, length: piece.length, fadeOut: fadeOut, at: start)
}

/// Plays a score on the motor, mixed like the beat in the show. The lowest channel is the bass, played the way the
/// beat plays its bass (every actuation restarts on the bass note's period, with two of its harmonics where the
/// motor is loud). The lead is the highest of the channels that play enough to carry a tune; the rest are quieter
/// harmony. While the lead rests, the loudest other voice takes its place, so a part without the tune isn't left
/// quiet. Each channel moves by whole octaves to 560 Hz or above, where the motor is loud and clean (chosen from
/// the notes as written), and its volume is measured against its own loudest note (a MIDI mix assumes a speaker;
/// on the motor, quiet means lost). `fadeOut`: seconds at the end over which it fades, so a stretch cut
/// mid-phrase doesn't just stop. With --lights: the keyboard on the beats, Caps Lock on the tune's notes, and the
/// screen full for the first bar's first beat, then dark with a faint flicker on each bar.
func playScore(_ notes: [ScoreNote], hits: [ScoreHit], beats: [Beat], length: Double, fadeOut: Double = 0, at start: UInt64) {
    var byCh: [Int: [Double]] = [:], loudest: [Int: Double] = [:]
    for n in notes { byCh[n.ch, default: []].append(n.hz); loudest[n.ch] = max(loudest[n.ch] ?? 0, n.gain) }
    func median(_ v: [Double]) -> Double { v.sorted()[v.count / 2] }
    // The bass first (the lowest channel, if it's low and not alone), then the lead: of the rest that play enough
    // to carry a tune, the highest (a busy accompaniment, like an arpeggio, has more notes than the tune itself).
    let lowest = byCh.min { median($0.value) < median($1.value) }
    let bassCh = byCh.count > 1 ? lowest.flatMap { median($0.value) < 200 ? $0.key : nil } : nil
    let noteCount = byCh.values.reduce(0) { $0 + $1.count }
    let tunes = byCh.filter { $0.key != bassCh && $0.value.count >= max(6, noteCount / 20) }
    let lead = (tunes.isEmpty ? byCh.filter { $0.key != bassCh } : tunes).max { median($0.value) < median($1.value) }?.key ?? 0
    var shift: [Int: Double] = [:]
    for (ch, v) in byCh where ch != bassCh {
        var s = 1.0
        while median(v) * s < 560 { s *= 2 }
        shift[ch] = s
    }
    var next = 0, nextHit = 0, nextBeat = 0, active: [ScoreNote] = [], ringing: [ScoreHit] = []
    var t = 0.0, screenSet = false
    waitUntil(start)
    while t < length && !interrupted() {
        let first = next
        while next < notes.count, notes[next].start <= t + 0.0005 { active.append(notes[next]); next += 1 }
        // A note of the tune lights Caps Lock: the lead's, or while the lead rests, the loudest other new note.
        let leadSounds = active.contains { $0.ch == lead && $0.end > t }
        if let n = notes[first..<next].filter({ $0.ch == lead || ($0.ch != bassCh && !leadSounds) }).max(by: { $0.gain < $1.gain }) {
            lightCue(.note(seconds: n.end - n.start, strength: 0.5 + 0.5 * n.gain / max(loudest[n.ch] ?? 1, 1e-6)))
        }
        while nextHit < hits.count, hits[nextHit].t <= t + 0.0005 { ringing.append(hits[nextHit]); nextHit += 1 }
        while nextBeat < beats.count, beats[nextBeat].t <= t + 0.0005 {
            let b = beats[nextBeat], beat = nextBeat + 1 < beats.count ? beats[nextBeat + 1].t - b.t : 0.5
            lightCue(.beat(b.downbeat ? 1 : 0.6))
            if b.downbeat { lightCue(.screen(screenSet ? .flicker(peak: 0.45, seconds: beat) : .full(seconds: beat))); screenSet = true }
            nextBeat += 1
        }
        active.removeAll { $0.end <= t }
        ringing.removeAll { t - $0.t > 0.2 }
        var tones: [(hz: Double, amp: Double)] = []
        var leadHz: Double?
        var bassHz: Double?
        // Who leads right now: the lead channel if it plays, else the loudest other voice that isn't the bass.
        let leadPlaying = active.contains { $0.ch == lead }
        let voice = leadPlaying ? lead : active.filter { $0.ch != bassCh }.max {
            $0.gain / (loudest[$0.ch] ?? 1) < $1.gain / (loudest[$1.ch] ?? 1)
        }?.ch
        let tuneHz = active.last { $0.ch == voice }.map { $0.hz * (shift[$0.ch] ?? 1) }
        // A tune note where the glass is weak plays alone, since the motor shares its strength among all its tones
        // and there the note needs all of it. Measured with the Mac's mic: below ~1050 Hz a note's octave above is
        // about as loud as the note, and between C#7 and D7 (2150–2290 Hz) the glass rings by itself at ~2320 Hz.
        let solo = tuneHz.map { $0 < 1050 || (2150...2290).contains($0) } ?? false
        for n in active {
            let age = t - n.start
            let env = (age < 0.008 ? age / 0.008 : 1) * (0.55 + 0.45 * exp(-age / 0.12))
            let gain = n.gain / max(loudest[n.ch] ?? n.gain, 1e-6)
            if n.ch == bassCh {
                bassHz = n.hz
                for (target, w) in [(880.0, 0.6), (1320.0, 0.4)] {
                    tones.append((max(1, (target / n.hz).rounded()) * n.hz, 0.45 * env * w * gain))
                }
            } else {
                let f = n.hz * (shift[n.ch] ?? 1)
                let main = n.ch == voice
                if main { leadHz = f }
                // A low note's octave above is as loud as the note itself (the motor's own second harmonic), so the
                // ear still hears the note, unless the accompaniment plays that octave too; then the octave wins by
                // 10 dB and the tune seems to jump up. So no accompaniment an octave above the tune.
                if !main, let lead = tuneHz, solo || abs(1200 * log2(f / (2 * lead))) < 30 { continue }
                tones.append((f, (main ? 1.0 : 0.3) * env * gain))
                // Where the glass rings by itself, a quiet octave below holds the note's pitch for the ear.
                if main, (2150...2290).contains(f) { tones.append((f / 2, 0.45 * env * gain)) }
            }
        }
        // Drums stay light and short, ticks above the tune: the motor shares one strength among all its tones, so a
        // loud, low drum pushes the tune down on every hit.
        for h in ringing {
            let age = t - h.t
            switch h.kind {
            case 0 where age < 0.06:    // bass drum or tom: a short, high pitch dive
                tones.append((420 + 680 * exp(-age / 0.012), 0.3 * exp(-age / 0.025)))
            case 1 where age < 0.09:    // snare: a short burst of high tones
                let e = 0.35 * exp(-age / 0.03)
                tones.append((Double.random(in: 1800...3800), e * 0.55))
                tones.append((Double.random(in: 1800...3800), e * 0.45))
            case 2 where age < 0.08:    // cymbal or hi-hat
                tones.append((3951, 0.25 * exp(-age / 0.03)))
            default: break
            }
        }
        tones.sort { $0.amp > $1.amp }
        let use = Array(tones.prefix(6))
        // One actuation. Every actuation starts all its tones again from zero, so its length decides which tones
        // come out whole: a period of the bass while it plays (that restart is what makes the bass heard); else a
        // whole number of the lead's cycles, so the tune never breaks off mid-wave (cut at every accompaniment note
        // instead, the tune lost its pitch). Of the lengths that do that (20–60 ms, or up to the next note), the one
        // where the other tones also come out nearest whole cycles, and near 45 ms: each restart puts faint side
        // tones 1/length away from the note, and the glass can lift one of them over the note; longer, they sit
        // closer and the pitch holds. (The driver also cuts a single actuation off after about 0.3 s.)
        let upcoming = [next < notes.count ? notes[next].start : nil, nextHit < hits.count ? hits[nextHit].t : nil]
            .compactMap { $0 }.map { $0 - t }.filter { $0 > 0 }.min()
        var step = 0.005
        if let bass = bassHz {
            step = 1 / bass
            if let dt = upcoming, dt > 0.0035, dt < step { step = dt }
        } else if let f = leadHz ?? use.first?.hz {
            var kMin = max(1, Int((0.02 * f).rounded(.up))), kMax = max(kMin, Int(0.06 * f))
            if let dt = upcoming, dt < Double(kMax) / f { kMax = max(1, Int(dt * f)); kMin = min(kMin, kMax) }
            func cost(_ k: Int) -> Double {
                let len = Double(k) / f
                var c = 0.0
                for tone in use where abs(tone.hz - f) > 0.5 {
                    let cycles = tone.hz * len
                    c += tone.amp * abs(cycles - cycles.rounded())
                }
                return c + 0.002 * abs(len - 0.045) / 0.045    // all else equal, about 45 ms
            }
            step = Double((kMin...kMax).min { cost($0) < cost($1) } ?? kMin) / f
        }
        let total = use.reduce(0) { $0 + $1.amp }
        let fade = fadeOut > 0 ? min(1, max(0, (length - t) / fadeOut)) : 1
        if total > 0.01 && fade > 0.01 { play(use, ms: step * 1000, level: Float(min(1, total) * fade)) }
        t += step
        waitUntil(start + UInt64(t * ticksPerSecond))
    }
}

// MARK: - Terminal

var savedTermios = termios()
var terminalTaken = false
/// Where the show draws. While it runs, stdout and stderr point at /dev/null, because MultitouchSupport
/// prints its own debug lines ("Recognized family…") when touch tracking starts.
var outFD = STDOUT_FILENO
var savedOut: Int32 = -1, savedErr: Int32 = -1
func silenceOthers() {
    fflush(stdout); fflush(stderr)
    savedOut = dup(STDOUT_FILENO); savedErr = dup(STDERR_FILENO)
    outFD = savedOut
    let null = open("/dev/null", O_WRONLY)
    dup2(null, STDOUT_FILENO); dup2(null, STDERR_FILENO); close(null)
}
func unsilence() {
    guard savedOut >= 0 else { return }
    fflush(stdout); fflush(stderr)
    dup2(savedOut, STDOUT_FILENO); dup2(savedErr, STDERR_FILENO)
    close(savedOut); close(savedErr)
    savedOut = -1; savedErr = -1; outFD = STDOUT_FILENO
}
func out(_ s: String) {
    let bytes = Array(s.utf8)
    let count = bytes.count
    bytes.withUnsafeBytes { buf in
        var off = 0
        while off < count {
            let n = write(outFD, buf.baseAddress! + off, count - off)
            if n <= 0 { break }
            off += n
        }
    }
}
func takeTerminal() {
    terminalTaken = true
    silenceOthers()
    tcgetattr(STDIN_FILENO, &savedTermios)
    var t = savedTermios
    t.c_lflag &= ~tcflag_t(ICANON | ECHO)
    tcsetattr(STDIN_FILENO, TCSANOW, &t)
    out("\u{1B}[?1049h\u{1B}[?25l\u{1B}[?1000h\u{1B}[?1002h\u{1B}[?1006h" + fillScreen())
}
func restoreTerminal() {
    guard terminalTaken else { return }
    terminalTaken = false
    out("\u{1B}[?1006l\u{1B}[?1002l\u{1B}[?1000l\u{1B}[0m\u{1B}[2J\u{1B}[?25h\u{1B}[?1049l")
    unsilence()
    tcsetattr(STDIN_FILENO, TCSANOW, &savedTermios)
}
/// Paints the whole terminal in the theme's background (not just the show's 80×24 block), so the show sits
/// centred on one page however big the window is.
func fillScreen() -> String {
    let size = terminalSize()
    let row = String(repeating: " ", count: size.w)
    var s = "\u{1B}[0m" + screenBackground + "\u{1B}[2J"
    for y in 0..<size.h { s += "\u{1B}[\(y + 1);1H" + row }
    return s
}

func terminalSize() -> (w: Int, h: Int) {
    var ws = winsize()
    if ioctl(outFD, TIOCGWINSZ, &ws) == 0, ws.ws_col > 0 { return (Int(ws.ws_col), Int(ws.ws_row)) }
    return (80, 24)
}

struct Cell: Equatable { var ch: Character = " "; var fg: UInt8 = 250; var bg: UInt8 = 16; var bold = false }

/// Colours are chosen as xterm 256-colour indexes but sent as exact 24-bit RGB, so a terminal's own theme
/// (light themes remap the palette) can't change them: black stays black.
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

/// Mono: black on off-white (default), or `--dark` for white on black. Greys run between the two.
func applyTheme(light: Bool) {
    lightTheme = light
    let paper = light ? (246, 245, 241) : (0, 0, 0)
    let ink = light ? (12, 12, 12) : (255, 255, 255)
    func str(_ c: (Int, Int, Int)) -> String { "\(c.0);\(c.1);\(c.2)" }
    func mix(_ u: Double) -> (Int, Int, Int) {
        (Int(Double(paper.0) + Double(ink.0 - paper.0) * u), Int(Double(paper.1) + Double(ink.1 - paper.1) * u),
         Int(Double(paper.2) + Double(ink.2 - paper.2) * u))
    }
    for n in 232...255 { rgbTable[n] = str(mix(0.05 + 0.95 * Double(n - 232) / 23)) }
    rgbTable[16] = str(paper)
    screenBackground = "\u{1B}[48;2;\(str(paper))m"
}

final class Canvas {
    let w = 80, h = 24
    var cells = [Cell](repeating: Cell(), count: 80 * 24)
    func clear() { for i in cells.indices { cells[i] = Cell() } }
    func put(_ x: Int, _ y: Int, _ ch: Character, _ fg: UInt8, bg: UInt8 = 16, bold: Bool = false) {
        guard x >= 0, y >= 0, x < w, y < h else { return }
        cells[y * w + x] = Cell(ch: ch, fg: fg, bg: bg, bold: bold)
    }
    func text(_ x: Int, _ y: Int, _ s: String, _ fg: UInt8, bg: UInt8 = 16, bold: Bool = false) {
        var i = x
        for c in s { put(i, y, c, fg, bg: bg, bold: bold); i += 1 }
    }
    func centered(_ y: Int, _ s: String, _ fg: UInt8, bold: Bool = false) { text((w - s.count) / 2, y, s, fg, bold: bold) }
    /// What the terminal is showing now, to send only the cells that changed.
    var shown: [Cell]?
    func changes(originX: Int, originY: Int) -> String {
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
        shown = cells
        return s.isEmpty ? "" : s + "\u{1B}[0m"
    }

}

// MARK: - Look
// Every screen: "a90.com presents", the slanted ASCII NO SPEAKER logo with "trackpad" under it, the current part's
// visual, a status bar (part, motor frequency, speaker state) and a scroller. Black on off-white by default.

let inkC: UInt8 = 255, bodyC: UInt8 = 251, midC: UInt8 = 247, dimC: UInt8 = 243, ruleC: UInt8 = 240, faintC: UInt8 = 236
let paperC: UInt8 = 16

func typed(_ s: String, since: Double, cps: Double, at t: Double) -> String { String(s.prefix(max(0, Int((t - since) * cps)))) }
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
func shade(_ v: Double) -> Character { ramp[max(0, min(ramp.count - 1, Int(v * Double(ramp.count - 1) + 0.5)))] }
/// "[=======>        ]" style bar, inside the given width (brackets included).
func asciiBar(_ v: Double, width: Int) -> String {
    let inner = width - 2, fill = Int(max(0, min(1, v)) * Double(inner))
    return "[" + String(repeating: "=", count: max(0, fill - 1)) + (fill > 0 ? ">" : "") + String(repeating: " ", count: inner - fill) + "]"
}

/// A silver shimmer travelling along `i` (no colour).
let silver: [UInt8] = [245, 246, 247, 248, 249, 250, 251, 252, 253, 254, 255, 255, 254, 253, 252, 251, 250, 249, 248, 247, 246]
func shimmer(_ i: Int) -> UInt8 { silver[((i % silver.count) + silver.count) % silver.count] }

let scrollText = "      ·  a90.com presents  NO SPEAKER  ·    the trackpad has no speaker. every sound you hear is its haptic motor, driven through MultitouchSupport, a private macOS framework.    range: 100 to 4000 vibrations per second.    voice: two formants, retriggered on every pitch beat.    thanks for listening.    a90.com    "

// Screen memory owned by the render thread.
var rollHistory = [Int](repeating: -1, count: 62)
var trail: [(x: Double, y: Double)] = []
func remember(_ s: LiveState, _ t: Double) {
    rollHistory.removeFirst(); rollHistory.append(s.scene == .sing && t - s.lastPlay < 0.1 ? s.noteRow : -1)
    if s.scene == .touch, s.touchDown { trail.append((s.touchX, s.touchY)); if trail.count > 14 { trail.removeFirst() } }
}

func draw(_ cv: Canvas, _ s: LiveState, _ t: Double) {
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
    case .sing: drawSing(cv, s, t)
    case .beat, .rap: drawBeat(cv, s, t)
    case .yourTurn: drawYourTurn(cv, s, t)
    case .touch: drawTouch(cv, s, t)
    case .say: drawSay(cv, s, t)
    case .outro: drawOutro(cv, s, t)
    default: break
    }

    // Status bar: the part, the motor, and the proof.
    let badge = String(format: " %02d/%02d ", s.part, partCount)
    cv.text(1, 21, badge, paperC, bg: inkC, bold: true)
    cv.text(1 + badge.count + 1, 21, s.partName, inkC, bold: true)
    let active = t - s.lastPlay < 0.08
    cv.text(24, 21, "motor", dimC)
    cv.text(30, 21, active ? String(format: "%4.0f hz", s.hz) : "idle", active ? inkC : dimC, bold: active)
    cv.text(38, 21, asciiBar(active ? s.level : 0, width: 10), bodyC)
    if let muted = s.muted {
        let chip = muted ? " SPEAKERS MUTED " : " SPEAKERS ON · MUTE "
        let blink = !muted && Int(t * 2.5) % 2 == 0
        cv.text(79 - chip.count, 21, chip, blink ? inkC : paperC, bg: blink ? faintC : inkC, bold: true)
    }
    cv.text(2, 22, "space skip · q end", faintC)
    // Scroller.
    let chars = Array(scrollText)
    for x in 0..<80 {
        let c = chars[(x + marquee) % chars.count]
        cv.put(x, 23, c, shimmer((x + marquee) / 2), bold: true)
    }
}

func drawSplash(_ cv: Canvas, _ s: LiveState, _ t: Double) {
    let x = 10, done = s.stepDone
    cv.text(x, 11, "$", midC); cv.text(x + 2, 11, typed("./nospeaker", since: s.started, cps: 30, at: t), inkC, bold: true)
    func line(_ y: Int, _ label: String, _ value: String) {
        let d = dots(label, value, width: 56)
        cv.text(x + 2, y, d, midC); cv.text(x + 2 + d.count, y, value, inkC, bold: true)
    }
    if done >= 1 { line(12, "loading the trackpad's haptics", mt != nil ? "ok" : "missing") }
    if done >= 2 { line(13, preferExternal ? "connecting to the external trackpad" : motorBuiltIn ? "connecting to the built-in trackpad" : "connecting to the trackpad", "ready") }
    if done >= 2 {
        let total = max(1, s.stepTotal - 2), voices = max(0, min(total, done - 2))
        if voices < total {
            let width = 28, fill = Int(Double(width) * Double(voices) / Double(total))
            let barText = String(repeating: "=", count: max(0, fill - 1)) + (fill > 0 ? ">" : "") + String(repeating: " ", count: width - fill)
            cv.text(x + 2, 14, "preparing the voice [\(barText)] \(voices)/\(total) " + ["|", "/", "-", "\\"][Int(t * 10) % 4], bodyC)
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
    let blink = !muted && Int(t * 2.5) % 2 == 0
    cv.text((80 - text.count) / 2, y, text, blink ? inkC : paperC, bg: blink ? faintC : inkC, bold: true)
}

let heartArt = [",d88b.d88b,", "88888888888", "`Y8888888Y'", "  `Y888Y'", "    `Y'"]
func drawHeart(_ cv: Canvas, _ s: LiveState, _ t: Double) {
    let pulse = max(0, 1 - (t - s.lastPlay) / 0.35) * s.level
    let shades: [UInt8] = [236, 238, 240, 243, 246, 249, 252, 255]
    let color = shades[min(shades.count - 1, Int(pulse * Double(shades.count - 1) + 0.5))]
    for (y, row) in heartArt.enumerated() { cv.text(34, 11 + y, row, color, bold: pulse > 0.3) }
    cv.centered(19, "waking up the motor", pulse > 0.3 ? inkC : dimC, bold: pulse > 0.3)
}

func xForHz(_ f: Double) -> Int { 3 + Int(log(max(100, min(4000, f)) / 100) / log(40) * 73) }

func drawSweep(_ cv: Canvas, _ s: LiveState, _ t: Double) {
    let f = t - s.lastPlay < 0.1 ? s.hz : 0
    drawSlant(cv, f > 0 ? String(Int(f)) + " Hz" : "100 Hz", y: 10)
    // A live wave: more cycles as the pitch climbs.
    let levels: [Character] = ["_", ".", "-", "~", "^"]
    let cycles = 1 + 22 * log(max(100, f) / 100) / log(40)
    for x in 0..<76 {
        let v = f > 0 ? sin(2 * .pi * cycles * Double(x) / 76 - t * 12) : 0
        cv.put(2 + x, 16, f > 0 ? levels[min(4, Int((v + 1) / 2 * 4.99))] : "-", f > 0 ? shimmer(x / 3 + Int(t * 10)) : faintC, bold: true)
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
    let progress = min(1, (t - s.captionStart) / max(0.2, s.captionDur) * 1.15)
    let shown = String(s.caption.prefix(Int(Double(s.caption.count) * progress)))
    // A blinking caret while it types; the closing quote once the line is done.
    let caret = progress >= 1 ? "”" : Int(t * 3) % 2 == 0 ? "█" : " "
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
    let v = value > 0 ? (value - lo) / (hi - lo) : 0
    cv.text(10, y, asciiBar(v, width: 46), bodyC)
    cv.text(57, y, value > 0 ? String(format: "%5.0f hz", value) : "    -   ", value > 0 ? inkC : dimC)
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
            for (f, a) in [(s.f1, 1.0), (s.f2, 0.8)] where f > 0 { v += a * exp(-pow(log(fx / f) / 0.12, 2)) }
            v *= s.level
        }
        let c = shade(min(1, v))
        cv.put(x, 18, c == " " ? "." : c, c == " " ? faintC : inkC)
        cv.put(x, 19, "-", faintC)
    }
    cv.text(3, 20, "100", dimC); cv.text(xForHz(1000) - 1, 20, "1k", dimC); cv.text(74, 20, "4k", dimC)
    cv.text(25, 20, "two tones, one motor, no speaker", midC)
}

func drawSing(_ cv: Canvas, _ s: LiveState, _ t: Double) {
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
    if s.noteRow >= 0 { cv.text(70, 12, String(format: "%4.0fhz", s.hz), midC) }
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

func drawTouch(_ cv: Canvas, _ s: LiveState, _ t: Double) {
    let x0 = 3, y0 = 10, w = 38, h = 11
    let edge: UInt8 = s.touchDown ? inkC : dimC
    cv.text(x0, y0, "╭" + String(repeating: "─", count: w - 2) + "╮", edge)
    for y in (y0 + 1)..<(y0 + h - 1) { cv.put(x0, y, "│", edge); cv.put(x0 + w - 1, y, "│", edge) }
    cv.text(x0, y0 + h - 1, "╰" + String(repeating: "─", count: w - 2) + "╯", edge)
    let names = ["G5", "A5", "B5", "C6", "E6", "F6", "G6", "A6", "B6", "C7"]
    for (i, n) in names.enumerated() where i % 3 == 0 { cv.text(x0 + 2 + i * 34 / names.count, y0 + h - 2, n, ruleC) }
    for (k, p) in trail.enumerated() {
        let px = x0 + 1 + Int(p.x * Double(w - 3)), py = y0 + 1 + Int((1 - p.y) * Double(h - 3))
        let isNow = k == trail.count - 1 && s.touchDown
        cv.put(px, py, isNow ? "@" : "o", isNow ? inkC : shimmer(k), bold: true)
    }
    let rx = 45
    if s.touchMissed {
        cv.text(rx, 12, "no touch, skipping", dimC)
    } else if !s.touchSeen {
        let blink = Int(t * 3) % 2 == 0
        cv.text(rx, 11, "▶ PUT A FINGER ON", blink ? inkC : midC, bold: true)
        cv.text(rx, 12, "  THE TRACKPAD", blink ? inkC : midC, bold: true)
        cv.text(rx, 14, "glide lightly, no need to click", midC)
        cv.text(rx, 16, String(format: "waiting %.0fs", max(0, s.touchWaitUntil - t)), dimC)
    } else {
        cv.text(rx, 10, "TOUCH TO PLAY", inkC, bold: true)
        cv.text(rx, 12, "slide left/right   pitch", bodyC)
        cv.text(rx, 13, "move up            vibrato", bodyC)
        cv.text(rx, 14, "glide lightly, don't click", dimC)
        let on = s.touchDown && t - s.lastPlay < 0.08
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
        let caret = Int(t * 2.5) % 2 == 0 ? "_" : " "
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
        cv.text(6, 16, "preparing the voice " + ["|", "/", "-", "\\"][Int(t * 10) % 4], midC)
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

func drawOutro(_ cv: Canvas, _ s: LiveState, _ t: Double) {
    let rows: [(String, String)] = [
        ("code · sound · design", "a90"), ("web", "a90.com"),
        ("speakers used", "0"), ("vibrations", NumberFormatter.localizedString(from: NSNumber(value: s.actuations), number: .decimal)),
        ("runtime", String(format: "%.1f s", t - s.started)),
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
            let blink = Int(t * 2) % 2 == 0
            cv.centered(19, "any other key exits", blink ? midC : dimC)
        }
    } else {
        cv.centered(19, "thanks for listening", dimC)
    }
}

var renderRunning = false
/// The scroller's position: one character per step, stepped by the frame clock so every step is even.
var marquee = 0
var lastMutePoll = -9.0
func startRenderer() {
    renderRunning = true
    let th = Thread {
        let cv = Canvas()
        var lastSize = (w: 0, h: 0)
        var frameCount = 0
        var next = now()
        while renderRunning {
            let t = now()
            frameCount += 1
            let s = snapshot()
            // Screen memory: piano roll and touch trail.
            remember(s, t)
            if t - lastMutePoll > 0.5 { lastMutePoll = t; let m = speakersMuted(); live { $0.muted = m } }
            let size = terminalSize()
            var prefix = ""
            if size != lastSize { prefix = fillScreen(); lastSize = size; cv.shown = nil }
            draw(cv, s, t)
            let frame = prefix + cv.changes(originX: max(0, (size.w - 80) / 2), originY: max(0, (size.h - 24) / 2))
            if !frame.isEmpty { out(frame) }
            // A steady frame clock: 24 fps while playing (the scroller steps every other frame, 12 chars/s),
            // 8 fps while waiting on the credits (one step a frame).
            let period = s.waitingForKey ? 0.125 : 1.0 / 24
            if s.waitingForKey || frameCount % 2 == 0 { marquee += 1 }
            next += period
            let wait = next - now()
            if wait > 0 { usleep(useconds_t(wait * 1e6)) } else { next = now() }
        }
    }
    th.qualityOfService = .userInitiated
    th.start()
}
func stopRenderer() { renderRunning = false; usleep(60_000) }

/// True when a byte is ready on stdin within `ms` milliseconds.
func waitForInput(ms: Int) -> Bool {
    var fds = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
    return poll(&fds, 1, Int32(ms)) > 0
}

func startKeys() {
    let th = Thread {
        var c: UInt8 = 0
        while !stopRequested {
            guard read(STDIN_FILENO, &c, 1) == 1 else { usleep(10_000); continue }
            // Typing a line for it to say: every key is text, except return, backspace, tab and esc.
            if snapshot().inputActive {
                if c == 27 {
                    if waitForInput(ms: 30) {   // a sequence (scroll, arrow): drop it
                        var b: UInt8 = 0, first = true
                        while waitForInput(ms: 30), read(STDIN_FILENO, &b, 1) == 1 {
                            if first { first = false; if b == UInt8(ascii: "[") || b == UInt8(ascii: "O") { continue } }
                            if (0x40...0x7E).contains(b) { break }
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
                } else if (32...126).contains(c) {
                    let ch = Character(UnicodeScalar(c))
                    live { if $0.inputText.count < 70 { $0.inputText.append(ch) } }
                }
                continue
            }
            if c == 27 {
                // Esc alone quits; Esc followed quickly by "[" or "O" is a sequence (a scroll, a click, an
                // arrow key): read it to its end and ignore it.
                guard waitForInput(ms: 30) else { requestEnd(); continue }
                var next: UInt8 = 0
                guard read(STDIN_FILENO, &next, 1) == 1 else { continue }
                if next == UInt8(ascii: "[") || next == UInt8(ascii: "O") {
                    var b: UInt8 = 0
                    while waitForInput(ms: 30), read(STDIN_FILENO, &b, 1) == 1 { if (0x40...0x7E).contains(b) { break } }
                }
                continue
            }
            // On the credits, F opens the X profile and stays put; any other key exits.
            if c == UInt8(ascii: "f") || c == UInt8(ascii: "F"), snapshot().waitingForKey {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                p.arguments = ["https://x.com/codycollier"]
                try? p.run()
                let at = now()
                live { $0.followOpenedAt = at }
                continue
            }
            keyPressed = true
            if c == UInt8(ascii: "q") || c == UInt8(ascii: "Q") { requestEnd() }
            if c == UInt8(ascii: " ") || c == UInt8(ascii: "s") { skipRequested = true }
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
    for (i, line) in phrases.enumerated() where !stopRequested {
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
        skipRequested = false
    }
    startLights()    // only with --lights

    // 2. It wakes up: a heartbeat, no words yet.
    if !stopRequested && !jumpToCredits { enter(.heart, 2, "WAKING UP"); pause(0.3); heartbeat() }
    // 3. Its first words: hello, who it is, what it knows (the reveal).
    if !stopRequested && !jumpToCredits { enter(.talk, 3, "FIRST WORDS"); say("“\(greeting)”"); pause(0.4); talk(voices[greeting]!, text: greeting); pause(0.9) }
    // 4. How: the sweep.
    if !stopRequested && !jumpToCredits { enter(.sweep, 4, "SWEEP"); say("sweep 100 Hz → 4 kHz"); pause(0.3); sweep(); pause(0.4) }
    // 5. Melody.
    if !stopRequested && !jumpToCredits { enter(.sing, 5, "MELODY"); say("♪ melody"); pause(0.4); sing(); pause(0.5) }
    // 6. Beat, then the rap over it.
    if !stopRequested && !jumpToCredits {
        enter(.beat, 6, "BEAT"); say("beat · then rap: “\(rapLine)”")
        groove(bars: 4, rapBar: 2, rap: voices[rapLine]!, rapText: rapLine); pause(0.5)
    }
    // 7. Your turn.
    if !stopRequested && !jumpToCredits { enter(.yourTurn, 7, "YOUR TURN"); say("“\(turnLine)”"); pause(0.3); talk(voices[turnLine]!, text: turnLine); pause(0.4) }
    // 8. Touch to play.
    if !stopRequested && !jumpToCredits { enter(.touch, 8, "TOUCH TO PLAY"); say("touch the trackpad: slide for pitch (12 s)"); touchToPlay() }
    // 9. Say anything (only with the screen: it needs typing).
    if !stopRequested && !jumpToCredits && visuals {
        enter(.say, 9, "SAY ANYTHING")
        lightCue(.screen(.rest))    // the screen comes back up: you need to see what you type
        sayAnything()
    }
    // 10. Outro.
    if !stopRequested {
        jumpToCredits = false
        inCredits = true
        enter(.outro, 10, "OUTRO")
        talk(voices[byeLine] ?? render(byeLine), text: byeLine)
        live { $0.scene = .outro }
        sparkle()
        stopLights()    // the screen eases back to its own brightness, and every light goes back as it was
        if visuals {
            keyPressed = false
            live { $0.waitingForKey = true }
            while !keyPressed && !stopRequested { usleep(20_000) }
        } else {
            pause(1.0)
        }
    }

    let s = snapshot()
    stopLights()
    if visuals { stopRenderer(); restoreTerminal() }
    signOff(seconds: Int(now() - s.started), actuations: s.actuations)
}

func signOff(seconds: Int, actuations: Int) {
    // The sign-off: the logo stays in their terminal as a souvenir, with what to run next.
    // Plain bold and dim only, so it reads in any terminal theme.
    let esc = "\u{1B}["
    let vibrations = NumberFormatter.localizedString(from: NSNumber(value: actuations), number: .decimal)
    var me = CommandLine.arguments[0].contains("/") ? CommandLine.arguments[0] : "nospeaker"
    let home = NSHomeDirectory()
    if me.hasPrefix(home + "/") { me = "~" + me.dropFirst(home.count) }
    print("")
    let lockup = logoLockup()
    for (i, line) in lockup.enumerated() { print("  " + (i < asciiLogo.count ? "\(esc)1m" : "\(esc)2m") + line + "\(esc)0m") }
    print("")
    print("  \(esc)1m\(seconds / 60):" + String(format: "%02d", seconds % 60) + "\(esc)0m  ·  \(esc)1m\(vibrations)\(esc)0m vibrations  ·  \(esc)1m0\(esc)0m speakers used")
    print("  more        \(esc)1mx.com/codycollier\(esc)0m")
    print("  play again  \(esc)2m\(me)\(esc)0m")
    print("  say a line  \(esc)2m\(me) \"hello there\"\(esc)0m")
    print("")
}

// MARK: - Main

var args = Array(CommandLine.arguments.dropFirst())
/// The value after `flag` (and removes both), or nil if the flag isn't there. A flag with no value is a mistake.
func option(_ flag: String, example: String) -> String? {
    guard let i = args.firstIndex(of: flag) else { return nil }
    guard i + 1 < args.count, !args[i + 1].hasPrefix("-") else { usageError("\(flag) needs a value, like: \(flag) \(example)") }
    let v = args[i + 1]; args.removeSubrange(i...(i + 1)); return v
}
func flag(_ f: String) -> Bool { if let i = args.firstIndex(of: f) { args.remove(at: i); return true }; return false }

if flag("--help") || flag("-h") {
    print("""
    NO SPEAKER · a90.com presents
    Your MacBook's trackpad has no speaker. This makes it talk anyway, through its haptic motor.

      nospeaker                         the show (space skips a part, q goes to the end)
      nospeaker "any words"             just say something
      nospeaker --sweep                 a rising tone, 100 Hz to 4 kHz
      --voice Daniel                    any voice from `say -v '?'`
      --dark                            white on black instead of black on white
      --plain                           no visuals
      --external                        play through an external Magic Trackpad
      --lights                          the keyboard backlight, the Caps Lock light and the screen play along
      --music song.mid                  play your own MIDI file
        --parts 3,4                       only these channels (it lists the file's channels when it starts)
        --only 6-31.5                     only this stretch, in seconds
        --no-drums                        without the drums

    Mute your Mac: it still talks. Put it on a table, and keep your hands off the trackpad until it asks.
    a90.com · x.com/codycollier
    """)
    exit(0)
}

voiceName = option("--voice", example: "Daniel")
if let v = voiceName, !voiceExists(v) {
    fail("There's no voice called \"\(v)\" on this Mac.\nList the voices you have with: say -v '?'", headline: "nospeaker can't use that voice.", code: 64)
}
applyTheme(light: !flag("--dark"))
let plain = flag("--plain")
let wantsSweep = flag("--sweep")
preferExternal = flag("--external")
let wantsLights = flag("--lights")
/// --music song.mid: your own MIDI file, played on the trackpad.
let musicPath = option("--music", example: "song.mid")
musicParts = option("--parts", example: "3,4").map { s in
    let p = s.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    guard !p.isEmpty, p.allSatisfy({ (1...16).contains($0) }) else { usageError("--parts takes channel numbers 1 to 16, like: --parts 3,4") }
    return Set(p)
}
/// --only 6-31.5: just this stretch of the music, in seconds.
let musicOnly: (Double, Double)? = option("--only", example: "6-31.5").map { s in
    let p = s.split(separator: "-").compactMap { Double($0) }
    guard p.count == 2, p[1] > p[0] else { usageError("--only takes two times in seconds, like: --only 6-31.5") }
    return (p[0], p[1])
}
scoreDrums = !flag("--no-drums")
if let unknown = args.first(where: { $0.hasPrefix("-") }) { usageError("\"\(unknown)\" isn't an option.") }
if musicPath == nil && (musicParts != nil || musicOnly != nil || !scoreDrums) { usageError("--parts, --only and --no-drums go with --music.") }
if musicPath != nil && (wantsSweep || !args.isEmpty) { usageError("--music plays on its own, without words or --sweep.") }
// The music is read before the motor opens, so a file it can't play stops here.
let music = musicPath.map { path -> (name: String, piece: Piece) in
    let score = loadMIDI(path)
    let channels = Set(score.notes.map { $0.ch + 1 }).union(score.hits.isEmpty ? [] : [10]).sorted()
    func list(_ c: [Int]) -> String { c.map(String.init).joined(separator: ", ") }
    guard !channels.isEmpty else { fail("\(path) has no notes.", headline: "nospeaker can't play that music.", code: 65) }
    let playing = musicParts.map { p in channels.filter(p.contains) } ?? channels
    if playing.isEmpty { usageError("--parts: this file plays on channels \(list(channels)).") }
    var name = (score.title.isEmpty ? (path as NSString).lastPathComponent : score.title) + ": channels \(list(playing))"
    if playing != channels { name += " (the file has \(list(channels)))" }
    guard let only = musicOnly else { return (name + String(format: ", %.1f s", score.end), (score.notes, score.hits, score.beats, score.end)) }
    return (name + String(format: ", %.1f–%.1f s", only.0, only.1), excerpt(score, from: only.0, to: only.1))
}

signal(SIGINT) { _ in requestEnd() }
signal(SIGTERM) { _ in stopRequested = true }
atexit { restoreTerminal() }
if wantsLights {
    // The lights are borrowed, so every way out puts them back. The terminal window closing ends it like Ctrl-C
    // twice; atexit runs the restore (last in, first out: before the terminal's). A crash skips atexit, and the
    // screen may be dark just then: put the lights back on the way down, then crash as before.
    signal(SIGHUP) { _ in stopRequested = true }
    atexit { stopLights() }
    for sig in [SIGTRAP, SIGSEGV, SIGBUS, SIGILL, SIGABRT, SIGFPE] {
        signal(sig) { sig in
            if lightsRunning {
                lightsRunning = false
                backlight?.restore(); capsLight?.restore(); screenLight?.restore()
            }
            signal(sig, SIG_DFL); raise(sig)
        }
    }
}

motor = openMotor()
motorPointer = Unmanaged.passUnretained(motor! as AnyObject).toOpaque()

// The lights are extra: whichever can't be reached, it says so and plays without it.
if wantsLights {
    func note(_ s: String) { FileHandle.standardError.write(("  nospeaker: " + s + "\n").data(using: .utf8)!) }
    backlight = KeyboardBacklight()
    if backlight == nil { note("no keyboard backlight it can control here, so it plays without it.") }
    capsLight = CapsLight()
    if capsLight == nil {
        note("couldn't set the Caps Lock light, so it plays without it. If macOS is refusing it, add the app you ran")
        note("this from (Terminal, iTerm…) in System Settings > Privacy & Security > Input Monitoring, then reopen it.")
    }
    // The screen only in the show: on its own, a line or the sweep is over before the screen could set a scene.
    if !wantsSweep && args.isEmpty {
        screenLight = ScreenLight()
        if screenLight == nil { note("can't set the screen's brightness here, so the screen stays as it is.") }
    }
}

if let music {
    pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0)
    print("playing \(music.name)")
    startLights()    // only with --lights
    perform(music.piece, fadeOut: musicOnly == nil ? 0 : 0.6)    // a stretch cut mid-phrase fades out
    stopLights()
} else if wantsSweep || !args.isEmpty {
    pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0)
    startLights()    // only with --lights
    if wantsSweep { print("sweeping 100 Hz → 4 kHz…"); sweep(seconds: 5) }
    if !args.isEmpty {
        let text = args.joined(separator: " ")
        let frames = render(text)
        print("trackpad: “\(text)”")
        talk(frames, text: text)
    }
    stopLights()
} else {
    let interactive = isatty(STDOUT_FILENO) == 1 && isatty(STDIN_FILENO) == 1
    // Too small a window: say so, and start by itself as soon as it's big enough.
    if !plain && interactive {
        var size = terminalSize()
        if size.w < 80 || size.h < 24 {
            print("\n  nospeaker needs a slightly bigger window: at least 80 × 24.")
            print("  Drag the window's corner to make it bigger, and it starts by itself.  (ctrl-c to stop)\n")
            while (size.w < 80 || size.h < 24) && !stopRequested && !jumpToCredits {
                usleep(200_000)
                size = terminalSize()
            }
            if stopRequested || jumpToCredits { exit(0) }
        }
    }
    let size = terminalSize()
    let visuals = !plain && interactive && size.w >= 80 && size.h >= 24
    show(visuals: visuals)
}
usleep(120_000)
if let motor { _ = actuatorClose?(motor) }
