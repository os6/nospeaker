// glassmap · what your trackpad's glass does with every note
//
// Copyright (c) 2026 Alex Samson, https://saalse.com. MIT License.
// The motor code is adapted from nospeaker by Cody Collier (MIT), https://github.com/os6/nospeaker.
//
// Plays every semitone in the motor's range through the trackpad and records it with the Mac's own microphone.
// Each note shows up as it's heard: how loud it is over the quiet room, and how much of that sound is the note
// itself. Then it draws the whole range as a chart, and lists the neighbouring notes that come out at one
// pitch, and the dead spots. Every trackpad rings in its own way. It saves all of it as the trackpad's sound
// signature, a small JSON file, so runs from different Macs can be compared.
//
//   swiftc -O tools/glassmap.swift -o tools/glassmap
//   tools/glassmap                       every semitone from 98 Hz (G2) to 3,951 Hz (B7), under a minute
//   tools/glassmap --from C6 --to E7     only these notes (names like F#5, or Hz like 1000)
//   tools/glassmap --external            measure an external Magic Trackpad
//
// Put the Mac on a table in a quiet room, hands off the trackpad, nothing else playing. macOS asks once to let
// your terminal app use the microphone. The motor is never driven past its normal maximum, as in nospeaker.
//
// A laptop microphone in a room can't tune a note to the cent, so glassmap doesn't try: it compares each note
// with its neighbour, and says when the two sound the same.

import AVFoundation
import Accelerate
import CoreAudio
import Darwin
import Foundation

func fail(_ message: String, headline: String = "glassmap can't measure on this Mac.", code: Int32 = 1) -> Never {
    let body = message.split(separator: "\n", omittingEmptySubsequences: false).map { "  " + $0 }.joined(separator: "\n")
    FileHandle.standardError.write(("\n  " + headline + "\n\n" + body + "\n\n").data(using: .utf8)!)
    exit(code)
}
func usageError(_ message: String) -> Never {
    fail(message + "\nSee glassmap --help for the options.", headline: "glassmap didn't understand that.", code: 64)
}

// MARK: - Notes

let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
func noteName(_ k: Int) -> String { names[k % 12] + String(k / 12 - 1) }
func hz(_ k: Int) -> Double { 440 * pow(2, Double(k - 69) / 12) }
let lowest = 43, highest = 107     // G2 (98 Hz) to B7 (3,951 Hz): the motor's range, as in nospeaker

/// A note as MIDI number, from a name ("C7", "F#5", "Bb4") or a frequency in Hz ("1000").
func parseNote(_ s: String) -> Int? {
    if let f = Double(s), f > 0 { return Int((69 + 12 * log2(f / 440)).rounded()) }
    let flats = ["Db": "C#", "Eb": "D#", "Gb": "F#", "Ab": "G#", "Bb": "A#"]
    let up = s.prefix(1).uppercased() + s.dropFirst()
    guard let digit = up.firstIndex(where: { $0.isNumber || $0 == "-" }), let octave = Int(up[digit...]) else { return nil }
    let pitch = String(up[..<digit])
    guard let semi = names.firstIndex(of: flats[pitch] ?? pitch) else { return nil }
    return (octave + 1) * 12 + semi
}

// MARK: - Options

let help = """
glassmap: plays every semitone through the trackpad and measures it with the Mac's microphone.

  glassmap                      every semitone from 98 Hz (G2) to 3,951 Hz (B7)
  glassmap --from C6 --to E7    only these notes (names like F#5, or Hz like 1000)
  glassmap --external           measure an external Magic Trackpad instead of the built-in one

Put the Mac on a table in a quiet room, hands off the trackpad, nothing else playing.
"""
var first = lowest, last = highest, preferExternal = false
var argv = CommandLine.arguments.dropFirst()
while let a = argv.popFirst() {
    switch a {
    case "-h", "--help": print(help); exit(0)
    case "--external": preferExternal = true
    case "--from", "--to":
        guard let v = argv.popFirst() else { usageError("\(a) needs a note, like C6 or 1000.") }
        guard let k = parseNote(v) else { usageError("\(v) isn't a note. Use a name like C6 or F#5, or Hz like 1000.") }
        guard (lowest...highest).contains(k) else {
            usageError("\(v) is outside the motor's range, 98 Hz (G2) to 3,951 Hz (B7).")
        }
        if a == "--from" { first = k } else { last = k }
    default: usageError("Unknown option: \(a)")
    }
}
guard first <= last else { usageError("--from has to be lower than --to.") }
let keys = Array(first...last)

// MARK: - The haptic motor (MultitouchSupport, resolved at run time, the same calls nospeaker makes)

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
let createList = sym("MTDeviceCreateList", CreateList.self)
let getID = sym("MTDeviceGetDeviceID", GetID.self)
let isBuiltIn = sym("MTDeviceIsBuiltIn", IsBuiltIn.self)
let actuatorCreate = sym("MTActuatorCreateFromDeviceID", ActuatorCreate.self)
let actuatorOpen = sym("MTActuatorOpen", ActuatorOpen.self)
let actuatorClose = sym("MTActuatorClose", ActuatorClose.self)
let actuationCreate = sym("MTActuationCreateFromDictionary", ActuationCreate.self)
let actuationPlay = sym("MTActuationActuate", ActuationPlay.self)

var deviceList: CFArray?    // kept alive while the motor is open
func openMotor() -> CFTypeRef {
    guard let createList, let getID, let actuatorCreate, let actuatorOpen, actuationCreate != nil, actuationPlay != nil else {
        fail("This version of macOS doesn't have the trackpad functions this needs.")
    }
    guard let list = createList()?.takeRetainedValue(), CFArrayGetCount(list) > 0 else {
        fail("No trackpad was found.")
    }
    deviceList = list
    var ids: [(id: UInt64, builtIn: Bool)] = []
    for i in 0..<CFArrayGetCount(list) {
        guard let raw = CFArrayGetValueAtIndex(list, i) else { continue }
        let dev = UnsafeMutableRawPointer(mutating: raw)
        var id: UInt64 = 0
        if getID(dev, &id) == 0 { ids.append((id, isBuiltIn?(dev) ?? false)) }
    }
    let order = preferExternal ? ids.filter { !$0.builtIn } : ids.sorted { $0.builtIn && !$1.builtIn }
    for d in order {
        if let ref = actuatorCreate(d.id)?.takeRetainedValue(), actuatorOpen(ref) == 0 { return ref }
    }
    fail(preferExternal
        ? "--external was given, but no external Force Touch trackpad was found."
        : "Found a trackpad, but no haptic motor (Force Touch) to play through.")
}

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
func ticks(_ seconds: Double) -> UInt64 { UInt64(seconds * ticksPerSecond) }

/// Plays one tone at full normal strength (amplitude 1, level 1: nospeaker's maximum) for `ms`.
func play(_ f: Double, ms: Double, motor: UnsafeMutableRawPointer) {
    let shape: [String: Any] = [
        "BaseWaveform": ["Type": "Gaussian", "Amplitude": 0.0, "DurationMS": ms],
        "Tones": [["Type": "Sine", "Amplitude": 1.0, "DurationMS": ms, "DelayMS": 0.0, "FrequencykHz": f / 1000]],
    ]
    guard let act = actuationCreate!(shape as CFDictionary, 0) else { return }
    _ = actuationPlay!(act, motor, 0, 1, 0)
    Unmanaged<AnyObject>.fromOpaque(act).release()
}

/// Holds a note for `seconds` as back-to-back pieces of whole cycles, about 45 ms each: the driver cuts one long
/// actuation short after about 0.3 s, and a piece cut mid-wave clicks.
func hold(_ f: Double, seconds: Double, motor: UnsafeMutableRawPointer) {
    let start = mach_absolute_time()
    let piece = max(1, (0.045 * f).rounded()) / f
    var t = 0.0
    while t < seconds {
        play(f, ms: piece * 1000, motor: motor)
        t += piece
        waitUntil(start + ticks(t))
    }
}

// MARK: - The microphone (AVAudioEngine hands over every sample)

final class Recorder {
    let engine = AVAudioEngine()
    private(set) var rate = 0.0
    private let lock = NSLock()
    private var samples: [Float] = []
    private var anchors: [(host: UInt64, index: Int)] = []   // when each buffer's first sample was heard

    func start() {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { fail("There's no microphone to record with.") }
        rate = format.sampleRate
        samples.reserveCapacity(Int(rate * 90))
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [self] buf, when in
            guard let ch = buf.floatChannelData?[0] else { return }
            lock.lock()
            if when.isHostTimeValid { anchors.append((when.hostTime, samples.count)) }
            samples.append(contentsOf: UnsafeBufferPointer(start: ch, count: Int(buf.frameLength)))
            lock.unlock()
        }
        do { try engine.start() } catch { fail("The microphone wouldn't start: \(error.localizedDescription)") }
    }
    func stop() { engine.stop(); engine.inputNode.removeTap(onBus: 0) }

    var count: Int { lock.lock(); defer { lock.unlock() }; return samples.count }
    /// The sample heard at a moment on the clock (mach_absolute_time).
    func index(at t: UInt64) -> Int {
        lock.lock(); defer { lock.unlock() }
        guard let a = anchors.last(where: { $0.host <= t }) ?? anchors.first else { return 0 }
        let dt = t >= a.host ? Double(t - a.host) : -Double(a.host - t)
        return a.index + Int((dt / ticksPerSecond * rate).rounded())
    }
    func recording() -> [Float] { lock.lock(); defer { lock.unlock() }; return samples }
    func slice(_ r: Range<Int>) -> [Float] {
        lock.lock(); defer { lock.unlock() }
        let a = max(0, min(r.lowerBound, samples.count)), b = max(a, min(r.upperBound, samples.count))
        return Array(samples[a..<b])
    }
}

// MARK: - Spectra

let maxLog2 = 18
let fftSetup = vDSP_create_fftsetup(vDSP_Length(maxLog2), FFTRadix(kFFTRadix2))!

struct Spectrum {
    var power: [Double]
    let binHz: Double
    /// Power between two frequencies.
    func band(_ lo: Double, _ hi: Double) -> Double {
        let a = max(1, Int((lo / binHz).rounded(.up))), b = min(power.count - 1, Int((hi / binHz).rounded(.down)))
        return a <= b ? power[a...b].reduce(0, +) : 0
    }
}

/// Power spectrum of a stretch of samples: Hann window, zero-padded to a power of two at least twice as long.
func spectrum(_ x: [Float], rate: Double) -> Spectrum {
    var log2n = 1
    while (1 << log2n) < 2 * x.count && log2n < maxLog2 { log2n += 1 }
    let n = 1 << log2n, m = min(x.count, n)
    var win = [Float](repeating: 0, count: m)
    vDSP_hann_window(&win, vDSP_Length(m), Int32(vDSP_HANN_NORM))
    var buf = [Float](repeating: 0, count: n)
    vDSP_vmul(x, 1, win, 1, &buf, 1, vDSP_Length(m))
    var re = [Float](repeating: 0, count: n / 2), im = [Float](repeating: 0, count: n / 2)
    var mags = [Float](repeating: 0, count: n / 2)
    re.withUnsafeMutableBufferPointer { rp in
        im.withUnsafeMutableBufferPointer { ip in
            var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
            buf.withUnsafeBytes { vDSP_ctoz($0.bindMemory(to: DSPComplex.self).baseAddress!, 2, &split, 1, vDSP_Length(n / 2)) }
            vDSP_fft_zrip(fftSetup, &split, 1, vDSP_Length(log2n), FFTDirection(FFT_FORWARD))
            vDSP_zvmags(&split, 1, &mags, 1, vDSP_Length(n / 2))
        }
    }
    mags[0] = 0    // DC and Nyquist share bin 0
    return Spectrum(power: mags.map { Double($0) }, binHz: rate / Double(n))
}

// MARK: - This Mac

func macModel() -> String {
    var size = 0
    sysctlbyname("hw.model", nil, &size, nil, 0)
    var buf = [CChar](repeating: 0, count: max(1, size))
    sysctlbyname("hw.model", &buf, &size, nil, 0)
    return String(cString: buf)
}
func defaultInputIsBuiltIn() -> Bool {
    var dev = AudioObjectID(0), size = UInt32(MemoryLayout<AudioObjectID>.size)
    var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                          mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &dev) == 0 else { return false }
    var transport = UInt32(0)
    size = UInt32(MemoryLayout<UInt32>.size)
    addr.mSelector = kAudioDevicePropertyTransportType
    guard AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &transport) == 0 else { return false }
    return transport == kAudioDeviceTransportTypeBuiltIn
}
let osVersion: String = {
    let v = ProcessInfo.processInfo.operatingSystemVersion
    return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
}()
let micName = AVCaptureDevice.default(for: .audio)?.localizedName ?? "microphone"


// MARK: - Listen

func dB(_ x: Double) -> Double { 10 * log10(max(x, 1e-20)) }

struct Row {
    let key: Int
    let level: Double    // dB over the quiet room
    let clean: Double    // the note and its overtones, as a share of all the sound it added (0…1)
    let tone: Double     // dB over the room, within a semitone and a half of the note
}

/// Measures notes against the quiet room. Each note is measured from 0.15 s to 0.55 s in, past its attack.
struct Listener {
    let rate: Double, window: Int, skip: Int
    let bottom = 60.0, top: Double    // "the sound": everything from 60 Hz to 12 kHz
    let room: Spectrum, roomPower: Double

    init(rate: Double, quiet: [Float]) {
        self.rate = rate
        window = Int(0.4 * rate)
        skip = Int(0.15 * rate)
        top = min(12000, 0.45 * rate)
        // The room: the average of overlapping windows of the quiet stretch.
        var sum: [Double] = [], count = 0, binHz = 0.0
        for at in stride(from: Int(0.2 * rate), through: quiet.count - window, by: window / 2) {
            let s = spectrum(Array(quiet[at..<(at + window)]), rate: rate)
            if sum.isEmpty { sum = s.power; binHz = s.binHz } else { for j in s.power.indices { sum[j] += s.power[j] } }
            count += 1
        }
        guard count > 0 else { fail("The recording came out too short to measure.") }
        room = Spectrum(power: sum.map { $0 / Double(count) }, binHz: binHz)
        roomPower = room.band(bottom, top)
        guard roomPower > 0 else {
            fail("""
            The microphone recorded only silence. Allow your terminal app in
            System Settings > Privacy & Security > Microphone, then run it again.
            """)
        }
    }

    /// A note, from the samples of its measured stretch: its row, and what it added to the room.
    func measure(_ key: Int, _ x: [Float]) -> (Row, Spectrum) {
        let s = spectrum(x, rate: rate)
        let a = Spectrum(power: zip(s.power, room.power).map { max(0, $0 - $1) }, binHz: s.binHz)
        let f = hz(key)
        // A frequency's band: a quarter tone either side (where the next note's begins), at least what the window
        // resolves, and at most a quarter of the note, so the overtones of low notes stay apart.
        func at(_ g: Double) -> Double {
            let half = min(max(g * (pow(2, 50.0 / 1200) - 1), 6), f / 4)
            return a.band(g - half, g + half)
        }
        var overtones = 0.0
        var h = 1.0
        while h * f < top { overtones += at(h * f); h += 1 }
        let all = a.band(bottom, top)
        let near = (f * pow(2, -1.5 / 12), f * pow(2, 1.5 / 12))
        return (Row(key: key, level: dB(s.band(bottom, top)) - dB(roomPower), clean: all > 0 ? min(1, overtones / all) : 0,
                    tone: dB(s.band(near.0, near.1)) - dB(room.band(near.0, near.1))), a)
    }
}

// MARK: - Measure

let noteSeconds = 0.6, gapSeconds = 0.15, roomSeconds = 2.0

var shown = ""    // the status line under the table
func status(_ s: String) {
    shown = s
    FileHandle.standardError.write(("\r\u{1B}[K" + (s.isEmpty ? "" : "  " + s)).data(using: .utf8)!)
}
/// Prints a line above the status line.
func above(_ line: String) {
    FileHandle.standardError.write("\r\u{1B}[K".data(using: .utf8)!)
    print(line)
    fflush(stdout)
    if !shown.isEmpty { FileHandle.standardError.write(("  " + shown).data(using: .utf8)!) }
}

func header() {
    let seconds = roomSeconds + Double(keys.count) * (noteSeconds + gapSeconds)
    print("""

      glassmap · \(macModel()) · macOS \(osVersion) · \(micName)

      \(keys.count) notes, \(noteName(first)) to \(noteName(last)), about \(Int(seconds.rounded())) seconds.
      On a table, hands off the trackpad, quiet room, nothing else playing.
    """)
    if !defaultInputIsBuiltIn() { print("  (\(micName) isn't the Mac's own microphone: the numbers describe what it hears.)") }
    if isatty(STDIN_FILENO) != 0 {
        print("  Press Return to start.", terminator: "")
        fflush(stdout)
        _ = readLine()
    }
}

/// Plays the notes and records them, and hands each note to `heard` as soon as the microphone has it.
/// Returns every sample, and where in it the quiet room and each note begin.
func measure(_ heard: @escaping (Int, Row, Spectrum) -> Void) -> (samples: [Float], rate: Double, room: Range<Int>, starts: [Int]) {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized: break
    case .notDetermined:
        let asked = DispatchSemaphore(value: 0)
        var allowed = false
        AVCaptureDevice.requestAccess(for: .audio) { allowed = $0; asked.signal() }
        asked.wait()
        if !allowed { fallthrough }
    default:
        fail("""
        macOS didn't let it use the microphone. Allow your terminal app in
        System Settings > Privacy & Security > Microphone, then run it again.
        """)
    }
    header()

    let motorRef = openMotor()
    let motor = Unmanaged.passUnretained(motorRef as AnyObject).toOpaque()
    let mic = Recorder()
    mic.start()
    usleep(500_000)    // the microphone settles

    status("listening to the quiet room…")
    let roomStart = mach_absolute_time()
    waitUntil(roomStart + ticks(roomSeconds))
    let roomEnd = mach_absolute_time()
    var listener: Listener?
    var starts: [UInt64] = [], done = 0
    // Measures every played note the microphone already has, waiting for it until `deadline` at most.
    func catchUp(by deadline: UInt64) {
        if listener == nil {
            let end = mic.index(at: roomEnd)
            guard mic.count >= end else { return }
            listener = Listener(rate: mic.rate, quiet: mic.slice(mic.index(at: roomStart)..<end))
        }
        let l = listener!
        while done < starts.count {
            let from = mic.index(at: starts[done]) + l.skip
            if mic.count < from + l.window {
                if mach_absolute_time() + ticks(0.02) < deadline { usleep(5_000); continue }
                return
            }
            let (r, a) = l.measure(keys[done], mic.slice(from..<(from + l.window)))
            heard(done, r, a)
            done += 1
        }
    }
    for (i, k) in keys.enumerated() {
        status("playing \(noteName(k))  \(Int(hz(k).rounded())) Hz   \(i + 1)/\(keys.count)")
        let start = mach_absolute_time()
        starts.append(start)
        hold(hz(k), seconds: noteSeconds, motor: motor)
        let next = start + ticks(noteSeconds + gapSeconds)
        catchUp(by: next)
        waitUntil(next)
    }
    _ = actuatorClose?(motorRef)
    status("")
    catchUp(by: mach_absolute_time() + ticks(2))
    mic.stop()
    guard done == keys.count else { fail("The recording came out shorter than the notes played. Try again.") }
    return (mic.recording(), mic.rate, mic.index(at: roomStart)..<mic.index(at: roomEnd), starts.map { mic.index(at: $0) })
}

// MARK: - Every note, as it's heard

/// How clean a note is: █ mostly the note, ▓ fair, ░ mostly buzz.
func shade(_ r: Row) -> String { r.clean >= 0.6 ? "█" : r.clean >= 0.35 ? "▓" : "░" }
let barWidth = 40    // a block per dB over the room
func bar(_ r: Row) -> String { String(repeating: shade(r), count: max(0, min(barWidth, Int(r.level.rounded())))) }
var rows: [Row] = []
var added: [Spectrum] = []    // what each note added to the room
let (samples, rate, roomRange, starts) = measure { i, r, a in
    if i == 0 {
        above("")
        above("   note     Hz  " + "loudness: █ clean  ▓ fair  ░ buzz".padding(toLength: barWidth, withPad: " ", startingAt: 0)
              + "         dB  clean")
    }
    let n = noteName(r.key)
    above("  " + String(repeating: " ", count: max(0, 5 - n.count)) + n + String(format: "  %5.0f  ", hz(r.key))
          + bar(r).padding(toLength: barWidth, withPad: " ", startingAt: 0) + String(format: "  %+6.1f dB   %3.0f%%", r.level, r.clean * 100))
    rows.append(r)
    added.append(a)
}
// MARK: - Report

// One pitch: two neighbouring notes that come out the same. A room microphone can't tune a note to the cent,
// but it can tell when two notes a semitone apart sound alike: the same spectrum around them (smoothed over
// 25 Hz, because the motor restarts every piece and spreads a note into teeth about 22 Hz apart), with the same
// middle. Checked from 1 kHz up; below that the glass's broad ringing makes neighbours look alike.
func samePitch(_ i: Int) -> Bool {
    let f = hz(rows[i].key), g = hz(rows[i + 1].key)
    guard f >= 1000 else { return false }
    let p = added[i], q = added[i + 1], bin = p.binHz
    let a = Int(f * pow(2, -3.0 / 12) / bin), b = min(p.power.count, Int(g * pow(2, 3.0 / 12) / bin))
    let width = max(1, Int(25 / bin))
    func smooth(_ x: [Double]) -> [Double] {
        (a..<b).map { j in x[max(0, j - width / 2)...min(x.count - 1, j + width / 2)].reduce(0, +) }
    }
    let x = smooth(p.power), y = smooth(q.power)
    var xy = 0.0, xx = 0.0, yy = 0.0, mx = 0.0, my = 0.0
    for j in x.indices {
        xy += x[j] * y[j]; xx += x[j] * x[j]; yy += y[j] * y[j]
        mx += x[j] * Double(a + j); my += y[j] * Double(a + j)
    }
    guard xx > 0, yy > 0 else { return false }
    let alike = xy / (xx * yy).squareRoot()
    let apart = 1200 * log2((my / y.reduce(0, +)) / (mx / x.reduce(0, +)))
    return alike >= 0.9 && abs(apart) < 20
}
// Groups of neighbours that sound as one, as index ranges.
var onePitch: [ClosedRange<Int>] = []
for i in rows.indices.dropLast() where samePitch(i) {
    if let last = onePitch.last, last.upperBound == i { onePitch[onePitch.count - 1] = last.lowerBound...(i + 1) }
    else { onePitch.append(i...(i + 1)) }
}
// Dead spots: at least 10 dB quieter around the note than the two notes on each side (three, at the ends).
var dead: [(Int, Double)] = []
for i in rows.indices {
    let around = (max(0, i - 2)..<min(rows.count, i + 3)).filter { $0 != i }.map { rows[$0].tone }.sorted()
    guard around.count >= 3 else { continue }
    let median = around.count % 2 == 1 ? around[around.count / 2] : (around[around.count / 2 - 1] + around[around.count / 2]) / 2
    if rows[i].tone < median - 10 { dead.append((i, median - rows[i].tone)) }
}

// The chart: a column per semitone, as tall as it is loud, shaded by how clean it is.
let height = 12
let lo = rows.map(\.level).min()!, hi = rows.map(\.level).max()!
var lines: [String] = [""]
for level in stride(from: height, through: 1, by: -1) {
    var line = "│"
    for r in rows {
        let h = hi > lo ? 1 + Int(((r.level - lo) / (hi - lo) * Double(height - 1)).rounded()) : height
        line.append(level <= h ? Character(shade(r)) : " ")
    }
    lines.append(line)
}
lines.append("└" + String(repeating: "─", count: rows.count))
// Hz under every C, and under the last note where there is room.
var axis = [Character](repeating: " ", count: rows.count + 6)
var free = 0
func label(_ text: String, at column: Int) {
    guard column >= free, column + text.count <= axis.count else { return }
    for (j, c) in text.enumerated() { axis[column + j] = c }
    free = column + text.count + 1
}
let lastLabel = String(Int(hz(rows.last!.key).rounded()))
for (i, r) in rows.enumerated() where r.key % 12 == 0 { label(String(Int(hz(r.key).rounded())), at: i + 1) }
label(lastLabel, at: max(1, rows.count + 1 - lastLabel.count))
lines.append(String(axis))
// └┘ under notes that sound as one.
if !onePitch.isEmpty {
    var under = [Character](repeating: " ", count: rows.count + 1)
    for g in onePitch {
        under[g.lowerBound + 1] = "└"; under[g.upperBound + 1] = "┘"
        for j in (g.lowerBound + 2)..<(g.upperBound + 1) { under[j] = "─" }
    }
    lines.append(String(under))
}
lines.append("")
lines.append(String(format: "across: every semitone, in Hz · up: loudness over the room, %+.0f to %+.0f dB", lo.rounded(.down), hi.rounded(.up)))
lines.append("█ clean   ▓ fair   ░ mostly buzz" + (onePitch.isEmpty ? "" : "   └┘ one pitch"))
print(lines.map { l -> String in
    var t = l
    while t.hasSuffix(" ") { t.removeLast() }
    return t.isEmpty ? "" : "  " + t
}.joined(separator: "\n"))

/// A list after its label, wrapped to stay under 100 columns.
func entry(_ label: String, _ items: [String]) -> String {
    let pad = "  " + label.padding(toLength: 12, withPad: " ", startingAt: 0)
    var out = pad, width = pad.count
    for (j, item) in (items.isEmpty ? ["none"] : items).enumerated() {
        let text = item + (j < items.count - 1 ? "," : "")
        if width + text.count + 1 > 100 && width > pad.count {
            out += "\n" + String(repeating: " ", count: pad.count)
            width = pad.count
        } else if width > pad.count { out += " "; width += 1 }
        out += text
        width += text.count
    }
    return out
}
let oneText = onePitch.map { g in g.map { noteName(rows[$0].key) }.joined(separator: " = ") }
let deadText = dead.map { String(format: "%@ (%.0f dB under its neighbours)", noteName(rows[$0.0].key), $0.1) }
print("\n" + entry("one pitch", oneText) + "\n" + entry("dead spots", deadText))
if !onePitch.isEmpty || !dead.isEmpty { print("") }
if !onePitch.isEmpty { print("  One pitch: the motor plays both notes at the same frequency, so a tune can't tell them apart.") }
if !dead.isEmpty { print("  Dead spots barely sound.") }
if !onePitch.isEmpty || !dead.isEmpty { print("  A tune that needs one of these: move it up or down a few semitones.") }

// For every note in a one-pitch group, the others in it.
var group: [Int: [String]] = [:]
for g in onePitch { for i in g { group[i] = g.filter { $0 != i }.map { noteName(rows[$0].key) } } }

// MARK: - Sound signature

// The same results as JSON, a note per line, saved next to where it runs.
func json(_ s: String) -> String {
    String(data: try! JSONSerialization.data(withJSONObject: s, options: .fragmentsAllowed), encoding: .utf8)!
}
func list(_ items: [String]) -> String { "[" + items.map(json).joined(separator: ", ") + "]" }
let now = Date()
func stamp(_ format: String) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = format
    return f.string(from: now)
}
let notes = rows.enumerated().map { i, r -> String in
    String(format: "    {\"note\": %@, \"hz\": %.1f, \"db_over_room\": %.1f, \"clean\": %.2f",
           json(noteName(r.key)), hz(r.key), r.level, r.clean)
        + (group[i].map { ", \"same_pitch_as\": " + list($0) } ?? "") + "}"
}
let signature = """
{
  "glassmap": 1,
  "mac": \(json(macModel())),
  "macos": \(json(osVersion)),
  "mic": \(json(micName)),
  "trackpad": \(json(preferExternal ? "external" : "built-in")),
  "date": \(json(stamp("yyyy-MM-dd"))),
  "one_pitch": [\(onePitch.map { g in list(g.map { noteName(rows[$0].key) }) }.joined(separator: ", "))],
  "dead_spots": \(list(dead.map { noteName(rows[$0.0].key) })),
  "notes": [
\(notes.joined(separator: ",\n"))
  ]
}

"""
let file = "glassmap-" + macModel().replacingOccurrences(of: ",", with: "-") + "-" + stamp("yyyyMMdd-HHmm") + ".json"
if (try? signature.write(toFile: file, atomically: true, encoding: .utf8)) != nil {
    print("\n  Sound signature saved: \(file)")
} else {
    print("\n  Couldn't save the sound signature to \(file).")
}
print("  Share it: tools/README.md says where to send this output and the file.\n")
