//
//  NoSpeakerCore.swift
//  NoSpeaker
//
//  Created for NoSpeaker GUI & CLI integration.
//  Directly interfaces with macOS MultitouchSupport to drive the trackpad haptic motor
//  as an acoustic transducer, speech synthesizer, and musical instrument.
//

import Foundation
import AVFoundation
import CoreAudio
import Darwin
import IOKit
import Combine

// MARK: - MultitouchSupport Private Framework Types & Bindings

public typealias CreateList = @convention(c) () -> Unmanaged<CFArray>?
public typealias GetID = @convention(c) (UnsafeMutableRawPointer, UnsafeMutablePointer<UInt64>) -> Int32
public typealias IsBuiltIn = @convention(c) (UnsafeMutableRawPointer) -> Bool
public typealias ActuatorCreate = @convention(c) (UInt64) -> Unmanaged<CFTypeRef>?
public typealias ActuatorOpen = @convention(c) (CFTypeRef) -> Int32
public typealias ActuatorClose = @convention(c) (CFTypeRef) -> Int32
public typealias ActuationCreate = @convention(c) (CFDictionary, Int32) -> UnsafeMutableRawPointer?
public typealias ActuationPlay = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer, UInt32, Float, Float) -> Int32
public typealias FrameCallback = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32
public typealias RegisterCallback = @convention(c) (UnsafeMutableRawPointer, FrameCallback) -> Void
public typealias DeviceStart = @convention(c) (UnsafeMutableRawPointer, Int32) -> Void
public typealias DeviceStop = @convention(c) (UnsafeMutableRawPointer) -> Void

public final class MultitouchBindings {
    public static let shared = MultitouchBindings()

    public let mtHandle: UnsafeMutableRawPointer?
    public let createList: CreateList?
    public let getID: GetID?
    public let isBuiltIn: IsBuiltIn?
    public let actuatorCreate: ActuatorCreate?
    public let actuatorOpen: ActuatorOpen?
    public let actuatorClose: ActuatorClose?
    public let actuationCreate: ActuationCreate?
    public let actuationPlay: ActuationPlay?
    public let registerCallback: RegisterCallback?
    public let unregisterCallback: RegisterCallback?
    public let deviceStart: DeviceStart?
    public let deviceStop: DeviceStop?

    private init() {
        let handle = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW)
        self.mtHandle = handle

        func sym<T>(_ name: String, _: T.Type) -> T? {
            guard let handle, let p = dlsym(handle, name) else { return nil }
            return unsafeBitCast(p, to: T.self)
        }

        self.createList = sym("MTDeviceCreateList", CreateList.self)
        self.getID = sym("MTDeviceGetDeviceID", GetID.self)
        self.isBuiltIn = sym("MTDeviceIsBuiltIn", IsBuiltIn.self)
        self.actuatorCreate = sym("MTActuatorCreateFromDeviceID", ActuatorCreate.self)
        self.actuatorOpen = sym("MTActuatorOpen", ActuatorOpen.self)
        self.actuatorClose = sym("MTActuatorClose", ActuatorClose.self)
        self.actuationCreate = sym("MTActuationCreateFromDictionary", ActuationCreate.self)
        self.actuationPlay = sym("MTActuationActuate", ActuationPlay.self)
        self.registerCallback = sym("MTRegisterContactFrameCallback", RegisterCallback.self)
        self.unregisterCallback = sym("MTUnregisterContactFrameCallback", RegisterCallback.self)
        self.deviceStart = sym("MTDeviceStart", DeviceStart.self)
        self.deviceStop = sym("MTDeviceStop", DeviceStop.self)
    }

    public var isAvailable: Bool {
        return createList != nil && getID != nil && actuatorCreate != nil &&
               actuatorOpen != nil && actuationCreate != nil && actuationPlay != nil
    }
}

// MARK: - Contact State

public struct TouchContact: Equatable {
    public var down: Bool = false
    public var x: Float = 0.5
    public var y: Float = 0.5
    public var size: Float = 0.0

    public init(down: Bool = false, x: Float = 0.5, y: Float = 0.5, size: Float = 0.0) {
        self.down = down
        self.x = x
        self.y = y
        self.size = size
    }
}

private var gTouchLock = os_unfair_lock()
private var gCurrentContact = TouchContact()

public func getGlobalContact() -> TouchContact {
    os_unfair_lock_lock(&gTouchLock)
    defer { os_unfair_lock_unlock(&gTouchLock) }
    return gCurrentContact
}

public func setGlobalContact(_ c: TouchContact) {
    os_unfair_lock_lock(&gTouchLock)
    gCurrentContact = c
    os_unfair_lock_unlock(&gTouchLock)
}

public let globalTouchCallback: FrameCallback = { _, data, count, _, _ in
    var best = TouchContact()
    if let data, count > 0 {
        for i in 0..<Int(count) {
            let rec = data.advanced(by: i * 96)
            let state = rec.load(fromByteOffset: 20, as: Int32.self)
            guard (3...5).contains(state) else { continue }
            best = TouchContact(
                down: true,
                x: rec.load(fromByteOffset: 32, as: Float.self),
                y: rec.load(fromByteOffset: 36, as: Float.self),
                size: rec.load(fromByteOffset: 48, as: Float.self)
            )
        }
    }
    setGlobalContact(best)
    return 0
}

// MARK: - Speech Analysis & Acoustic Modeling

public struct SpeechFrame {
    public var formants: [Double] = [500, 1500, 2500]
    public var amps: [Double] = [1, 0.5, 0.25]
    public var level: Float = 0
    public var voiced: Bool = false
    public var f0: Double = 110.0

    public init(formants: [Double] = [500, 1500, 2500], amps: [Double] = [1, 0.5, 0.25], level: Float = 0, voiced: Bool = false, f0: Double = 110.0) {
        self.formants = formants
        self.amps = amps
        self.level = level
        self.voiced = voiced
        self.f0 = f0
    }
}

public struct VoiceMetadata: Identifiable, Hashable {
    public var id: String { name }
    public let name: String
    public let locale: String
    public let sample: String
}

public struct ComplexNum {
    public var re: Double
    public var im: Double

    public init(re: Double, im: Double) {
        self.re = re
        self.im = im
    }

    public static func + (l: ComplexNum, r: ComplexNum) -> ComplexNum { ComplexNum(re: l.re + r.re, im: l.im + r.im) }
    public static func - (l: ComplexNum, r: ComplexNum) -> ComplexNum { ComplexNum(re: l.re - r.re, im: l.im - r.im) }
    public static func * (l: ComplexNum, r: ComplexNum) -> ComplexNum {
        ComplexNum(re: l.re * r.re - l.im * r.im, im: l.re * r.im + l.im * r.re)
    }
    public static func / (l: ComplexNum, r: ComplexNum) -> ComplexNum {
        let d = r.re * r.re + r.im * r.im
        return ComplexNum(re: (l.re * r.re + l.im * r.im) / d, im: (l.im * r.re - l.re * r.im) / d)
    }
}

public enum SpeechAcoustics {
    public static let hop: Double = 0.010
    public static let sampleRate: Double = 16000.0

    public static func lpc(_ x: [Double], order p: Int) -> ([Double], Double) {
        var r = [Double](repeating: 0, count: p + 1)
        for k in 0...p {
            var s = 0.0
            for i in k..<x.count { s += x[i] * x[i - k] }
            r[k] = s
        }
        var a = [Double](repeating: 0, count: p + 1)
        a[0] = 1
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

    public static func roots(_ a: [Double]) -> [ComplexNum] {
        let p = a.count - 1
        var z = (0..<p).map { k -> ComplexNum in
            let ang = 2 * Double.pi * Double(k) / Double(p) + 0.4
            return ComplexNum(re: 0.9 * cos(ang), im: 0.9 * sin(ang))
        }
        func poly(_ x: ComplexNum) -> ComplexNum {
            var s = ComplexNum(re: 1, im: 0)
            for k in 1...p { s = s * x + ComplexNum(re: a[k], im: 0) }
            return s
        }
        for _ in 0..<300 {
            var moved = 0.0
            for i in 0..<p {
                var d = ComplexNum(re: 1, im: 0)
                for j in 0..<p where j != i { d = d * (z[i] - z[j]) }
                if d.re == 0 && d.im == 0 { d = ComplexNum(re: 1e-12, im: 0) }
                let step = poly(z[i]) / d
                z[i] = z[i] - step
                moved = max(moved, abs(step.re) + abs(step.im))
            }
            if moved < 1e-10 { break }
        }
        return z
    }

    public static func analyse(_ x: [Float]) -> [SpeechFrame] {
        let win = Int(0.025 * sampleRate), hopN = Int(hop * sampleRate), order = 18
        let hamming = (0..<win).map { 0.54 - 0.46 * cos(2 * .pi * Double($0) / Double(win - 1)) }
        var frames: [SpeechFrame] = [], rmsList: [Double] = []
        var prev = SpeechFrame()
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
                for k in 0..<(win - lag) {
                    s += seg[k] * seg[k + lag]
                    ea += seg[k] * seg[k]
                    eb += seg[k + lag] * seg[k + lag]
                }
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

    public static func voiceTones(_ f: SpeechFrame) -> [(hz: Double, amp: Double)] {
        let w = [f.amps[0], f.amps[1] * 1.8]
        let sum = max(w[0] + w[1], 1e-9)
        return [(f.formants[0], w[0] / sum), (f.formants[1], w[1] / sum)]
    }

    public static func renderSpeech(_ text: String, voice: String? = nil) throws -> [SpeechFrame] {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("nospeaker-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        var pArgs = ["-o", url.path, "--file-format=WAVE", "--data-format=LEF32@16000"]
        if let v = voice, !v.isEmpty {
            pArgs += ["-v", v]
        }
        pArgs.append(text)
        p.arguments = pArgs

        try p.run()
        p.waitUntilExit()

        guard p.terminationStatus == 0,
              let file = try? AVAudioFile(forReading: url),
              let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buf)) != nil,
              let ch = buf.floatChannelData?[0] else {
            throw NSError(domain: "NoSpeaker", code: 1, userInfo: [NSLocalizedDescriptionKey: "macOS speech synthesis failed for \"\(text)\"."])
        }

        var f = analyse(Array(UnsafeBufferPointer(start: ch, count: Int(buf.frameLength))))
        while let first = f.first, first.level == 0 { f.removeFirst() }
        while let last = f.last, last.level == 0 { f.removeLast() }
        return f
    }

    public static func getAvailableVoices() -> [VoiceMetadata] {
        let p = Process(), pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        p.arguments = ["-v", "?"]
        p.standardOutput = pipe
        guard (try? p.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard let output = String(data: data, encoding: .utf8) else { return [] }

        var voices: [VoiceMetadata] = []
        for line in output.split(separator: "\n") {
            let str = String(line)
            let parts = str.components(separatedBy: "#")
            let sample = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
            let prefix = parts[0].trimmingCharacters(in: .whitespaces)
            let tokens = prefix.split(whereSeparator: { $0.isWhitespace })
            if tokens.count >= 2 {
                let locale = String(tokens.last!)
                let name = tokens.dropLast().joined(separator: " ")
                voices.append(VoiceMetadata(name: name, locale: locale, sample: sample))
            }
        }
        return voices
    }
}

// MARK: - Musical & Physical Utilities

public enum MusicTheory {
    public static func hz(_ note: String) -> Double {
        let names: [String: Int] = ["C": -9, "C#": -8, "D": -7, "D#": -6, "E": -5, "F": -4, "F#": -3, "G": -2, "G#": -1, "A": 0, "A#": 1, "B": 2]
        guard let octave = Int(String(note.last!)), let semi = names[String(note.dropLast())] else { return 440 }
        return 440 * pow(2, Double(semi + (octave - 4) * 12) / 12)
    }

    public static func noteName(_ f: Double) -> String {
        guard f > 20 else { return "—" }
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let midi = Int((69 + 12 * log2(f / 440)).rounded())
        return names[(midi % 12 + 12) % 12] + String(midi / 12 - 1)
    }
}

// MARK: - Audio Hardware Helpers (Speaker Mute Detection)

public enum AudioHardware {
    public static func speakersMuted() -> Bool? {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &device) == noErr else { return nil }

        var known = false
        var muted: UInt32 = 0
        size = 4
        addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectHasProperty(device, &addr), AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &muted) == noErr {
            known = true
            if muted != 0 { return true }
        }

        for element in [kAudioObjectPropertyElementMain, 1] {
            var volume: Float32 = 1
            size = 4
            addr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: element
            )
            if AudioObjectHasProperty(device, &addr), AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &volume) == noErr {
                return volume < 0.001
            }
        }
        return known ? false : nil
    }

    public static func macModel() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var buf = [CChar](repeating: 0, count: max(1, size))
        sysctlbyname("hw.model", &buf, &size, nil, 0)
        return String(cString: buf)
    }

    public static var isLaptop: Bool {
        macModel().hasPrefix("MacBook") || IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery")) != 0
    }
}

// MARK: - App State Enums

public enum ActiveOperation: Equatable {
    case idle
    case show(stage: Int, name: String)
    case speaking(text: String)
    case sweep
    case melody
    case beat
    case heartbeat
    case theremin
    case singleTone(hz: Double)
    case sparkle

    public var title: String {
        switch self {
        case .idle: return "Ready"
        case .show(let stage, let name): return "The Show: Part \(stage) (\(name))"
        case .speaking: return "Speaking via Trackpad"
        case .sweep: return "Frequency Sweep"
        case .melody: return "Singing Melody"
        case .beat: return "Beat & Rap Groove"
        case .heartbeat: return "Heartbeat"
        case .theremin: return "Trackpad Instrument Active"
        case .singleTone(let hz): return "Tone: \(Int(hz)) Hz"
        case .sparkle: return "Sparkle Arpeggio"
        }
    }
}

// MARK: - Central NoSpeaker Engine (Observable)

public final class NoSpeakerEngine: ObservableObject {
    public static let shared = NoSpeakerEngine()

    // MARK: Published UI State
    @Published public var isMotorReady: Bool = false
    @Published public var deviceCount: Int = 0
    @Published public var deviceName: String = "No Trackpad"
    @Published public var isBuiltIn: Bool = true
    @Published public var preferExternal: Bool = false
    @Published public var areSpeakersMuted: Bool? = nil
    @Published public var activeOperation: ActiveOperation = .idle
    @Published public var currentHz: Double = 0.0
    @Published public var currentNoteName: String = "—"
    @Published public var currentLevel: Float = 0.0
    @Published public var currentF0: Double = 0.0
    @Published public var currentF1: Double = 0.0
    @Published public var currentF2: Double = 0.0
    @Published public var totalActuations: Int = 0
    @Published public var touchState: TouchContact = TouchContact()
    @Published public var currentCaption: String = ""
    @Published public var showStep: Int = 0
    @Published public var showTotalSteps: Int = 10
    @Published public var showProgressPercent: Double = 0.0
    @Published public var availableVoices: [VoiceMetadata] = []
    @Published public var selectedVoice: String = "Daniel"
    @Published public var errorMessage: String? = nil

    // MARK: Internal Engine State
    private let bindings = MultitouchBindings.shared
    private var motorRef: CFTypeRef?
    private var motorPointer: UnsafeMutableRawPointer?
    private var motorDeviceID: UInt64 = 0
    private var deviceListRef: CFArray?

    private var stopRequested = false
    private var skipRequested = false

    private var timebase = mach_timebase_info_data_t()
    private var ticksPerSecond: Double = 1e9
    private var t0: UInt64 = 0

    private let workQueue = DispatchQueue(label: "com.a90.nospeaker.engine", qos: .userInteractive)
    private var statusTimer: Timer?
    private var touchPollingTimer: Timer?

    public init() {
        mach_timebase_info(&timebase)
        ticksPerSecond = 1e9 * Double(timebase.denom) / Double(timebase.numer)
        t0 = mach_absolute_time()

        refreshHardware()
        loadVoices()
        startPeriodicChecks()
    }

    deinit {
        stopAll()
        closeMotor()
        statusTimer?.invalidate()
        touchPollingTimer?.invalidate()
    }

    // MARK: - Time Utilities

    public func now() -> Double {
        Double(mach_absolute_time() - t0) / ticksPerSecond
    }

    public func waitUntil(_ t: UInt64) {
        let margin = UInt64(0.0015 * ticksPerSecond)
        while !stopRequested {
            let n = mach_absolute_time()
            if n >= t { return }
            if t - n > margin {
                usleep(useconds_t(Double(t - n - margin) / ticksPerSecond * 1e6))
            }
        }
    }

    public func pause(_ seconds: Double) {
        let end = now() + seconds
        while now() < end && !stopRequested && !skipRequested {
            usleep(5000)
        }
    }

    // MARK: - Hardware Refresh & Connection

    public func refreshHardware() {
        areSpeakersMuted = AudioHardware.speakersMuted()
        openMotor()
    }

    private func loadVoices() {
        DispatchQueue.global(qos: .utility).async {
            let voices = SpeechAcoustics.getAvailableVoices()
            DispatchQueue.main.async {
                self.availableVoices = voices
                if !voices.contains(where: { $0.name.lowercased() == self.selectedVoice.lowercased() }) {
                    if let firstEn = voices.first(where: { $0.locale.starts(with: "en") }) {
                        self.selectedVoice = firstEn.name
                    } else if let first = voices.first {
                        self.selectedVoice = first.name
                    }
                }
            }
        }
    }

    private func startPeriodicChecks() {
        statusTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let muted = AudioHardware.speakersMuted()
            if self.areSpeakersMuted != muted {
                DispatchQueue.main.async { self.areSpeakersMuted = muted }
            }
        }

        touchPollingTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let c = getGlobalContact()
            if self.touchState != c {
                DispatchQueue.main.async { self.touchState = c }
            }
        }
    }

    @discardableResult
    public func openMotor() -> Bool {
        closeMotor()

        guard bindings.isAvailable else {
            DispatchQueue.main.async {
                self.isMotorReady = false
                self.errorMessage = "MultitouchSupport functions not available on this macOS version."
            }
            return false
        }

        guard let list = bindings.createList?()?.takeRetainedValue(), CFArrayGetCount(list) > 0 else {
            DispatchQueue.main.async {
                self.isMotorReady = false
                self.errorMessage = "No trackpad detected."
            }
            return false
        }

        self.deviceListRef = list
        var ids: [(id: UInt64, builtIn: Bool)] = []
        for i in 0..<CFArrayGetCount(list) {
            guard let raw = CFArrayGetValueAtIndex(list, i) else { continue }
            let dev = UnsafeMutableRawPointer(mutating: raw)
            var id: UInt64 = 0
            if bindings.getID?(dev, &id) == 0 {
                ids.append((id, bindings.isBuiltIn?(dev) ?? false))
            }
        }

        let count = ids.count

        if preferExternal {
            for d in ids where !d.builtIn {
                if let ref = bindings.actuatorCreate?(d.id)?.takeRetainedValue(), bindings.actuatorOpen?(ref) == 0 {
                    self.motorRef = ref
                    self.motorPointer = Unmanaged.passUnretained(ref as AnyObject).toOpaque()
                    self.motorDeviceID = d.id
                    DispatchQueue.main.async {
                        self.isMotorReady = true
                        self.deviceCount = count
                        self.isBuiltIn = false
                        self.deviceName = "Magic Trackpad (External)"
                        self.errorMessage = nil
                    }
                    return true
                }
            }
        }

        for d in ids.sorted(by: { $0.builtIn && !$1.builtIn }) {
            if let ref = bindings.actuatorCreate?(d.id)?.takeRetainedValue(), bindings.actuatorOpen?(ref) == 0 {
                self.motorRef = ref
                self.motorPointer = Unmanaged.passUnretained(ref as AnyObject).toOpaque()
                self.motorDeviceID = d.id
                DispatchQueue.main.async {
                    self.isMotorReady = true
                    self.deviceCount = count
                    self.isBuiltIn = d.builtIn
                    self.deviceName = d.builtIn ? "Built-in Force Touch Trackpad" : "Magic Trackpad (External)"
                    self.errorMessage = nil
                }
                return true
            }
        }

        DispatchQueue.main.async {
            self.isMotorReady = false
            self.deviceCount = count
            self.errorMessage = "Trackpad found, but without haptic motor (Force Touch)."
        }
        return false
    }

    public func closeMotor() {
        if let ref = motorRef {
            _ = bindings.actuatorClose?(ref)
            motorRef = nil
            motorPointer = nil
        }
    }

    // MARK: - Low-Level Actuation

    public func play(_ tones: [(hz: Double, amp: Double)], ms: Double, level: Float) {
        guard let motorPointer = self.motorPointer, !tones.isEmpty else { return }
        let sum = max(tones.reduce(0) { $0 + $1.amp }, 0.0001)
        let shape: [String: Any] = [
            "BaseWaveform": ["Type": "Gaussian", "Amplitude": 0.0, "DurationMS": ms],
            "Tones": tones.map { ["Type": "Sine", "Amplitude": $0.amp / sum, "DurationMS": ms, "DelayMS": 0.0, "FrequencykHz": $0.hz / 1000] }
        ]
        guard let act = bindings.actuationCreate?(shape as CFDictionary, 0) else { return }
        _ = bindings.actuationPlay?(act, motorPointer, 0, min(1, max(0, level)), 0)
        Unmanaged<AnyObject>.fromOpaque(act).release()

        let firstHz = tones[0].hz
        DispatchQueue.main.async {
            self.totalActuations += 1
            self.currentHz = firstHz
            self.currentNoteName = MusicTheory.noteName(firstHz)
            self.currentLevel = level
        }
    }

    // MARK: - Touch Tracking

    private func touchDevices() -> [UnsafeMutableRawPointer] {
        guard let deviceList = deviceListRef, let getID = bindings.getID else { return [] }
        return (0..<CFArrayGetCount(deviceList)).compactMap { i -> UnsafeMutableRawPointer? in
            guard let raw = CFArrayGetValueAtIndex(deviceList, i) else { return nil }
            let dev = UnsafeMutableRawPointer(mutating: raw)
            var id: UInt64 = 0
            return getID(dev, &id) == 0 && id == motorDeviceID ? dev : nil
        }
    }

    public func startTouch() -> Bool {
        guard let registerCallback = bindings.registerCallback, let deviceStart = bindings.deviceStart else { return false }
        let devs = touchDevices()
        for d in devs {
            registerCallback(d, globalTouchCallback)
            deviceStart(d, 0)
        }
        return !devs.isEmpty
    }

    public func stopTouch() {
        for d in touchDevices() {
            bindings.unregisterCallback?(d, globalTouchCallback)
            bindings.deviceStop?(d)
        }
        setGlobalContact(TouchContact())
        DispatchQueue.main.async {
            self.touchState = TouchContact()
        }
    }

    // MARK: - Playback Control API

    public func stopAll() {
        stopRequested = true
        skipRequested = false
        stopTouch()
        DispatchQueue.main.async {
            self.activeOperation = .idle
            self.currentLevel = 0
            self.currentCaption = ""
            self.currentF0 = 0
            self.currentF1 = 0
            self.currentF2 = 0
        }
    }

    public func skipStage() {
        skipRequested = true
    }

    // MARK: - Speech Synthesis ("Say Anything")

    public func speak(text: String, voice: String? = nil, onComplete: (() -> Void)? = nil) {
        stopRequested = false
        skipRequested = false
        let v = voice ?? selectedVoice

        workQueue.async {
            DispatchQueue.main.async {
                self.activeOperation = .speaking(text: text)
                self.currentCaption = text
            }

            do {
                let frames = try SpeechAcoustics.renderSpeech(text, voice: v)
                self.executeTalk(frames: frames, text: text)
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                }
            }

            DispatchQueue.main.async {
                self.activeOperation = .idle
                self.currentCaption = ""
                onComplete?()
            }
        }
    }

    private func executeTalk(frames: [SpeechFrame], text: String) {
        guard !frames.isEmpty else { return }
        let hop = SpeechAcoustics.hop
        let total = Double(frames.count) * hop
        let start = mach_absolute_time()
        var t = 0.0

        while t < total && !stopRequested {
            let f = frames[min(frames.count - 1, Int(t / hop))]
            var step = 0.005
            if f.level > 0 {
                if f.voiced {
                    step = 1 / f.f0
                    play(SpeechAcoustics.voiceTones(f), ms: step * 1000, level: f.level)
                    DispatchQueue.main.async {
                        self.currentF0 = f.f0
                        self.currentF1 = f.formants[0]
                        self.currentF2 = f.formants[1]
                    }
                } else {
                    step = 0.004
                    play((0..<3).map { _ in (Double.random(in: 2700...4300), 1.0) }, ms: step * 1000, level: f.level * 0.7)
                }
            }
            t += step
            waitUntil(start + UInt64(t * ticksPerSecond))
        }

        DispatchQueue.main.async {
            self.currentF0 = 0
            self.currentF1 = 0
            self.currentF2 = 0
        }
    }

    // MARK: - Frequency Sweep

    public func sweep(duration: Double = 6.0, startHz: Double = 100.0, endHz: Double = 4000.0) {
        stopRequested = false
        skipRequested = false

        workQueue.async {
            DispatchQueue.main.async {
                self.activeOperation = .sweep
                self.currentCaption = "Sweeping \(Int(startHz)) Hz → \(Int(endHz)) Hz"
            }

            let start = mach_absolute_time()
            var t = 0.0
            let ratio = endHz / startHz

            while t < duration && !self.stopRequested && !self.skipRequested {
                let f = startHz * pow(ratio, t / duration)
                let seg = max(1, (0.02 * f).rounded()) / f
                self.play([(f, 1)], ms: seg * 1000, level: 1.0)
                t += seg
                self.waitUntil(start + UInt64(t * self.ticksPerSecond))
            }

            DispatchQueue.main.async {
                self.activeOperation = .idle
                self.currentCaption = ""
            }
        }
    }

    // MARK: - Single Tone & Notes

    public func playTone(hz: Double, ms: Double = 300, level: Float = 0.9) {
        stopRequested = false
        workQueue.async {
            DispatchQueue.main.async {
                self.activeOperation = .singleTone(hz: hz)
            }
            let seg = max(1, (0.02 * hz).rounded()) / hz
            var elapsed = 0.0
            let start = mach_absolute_time()
            while elapsed < (ms / 1000.0) && !self.stopRequested {
                self.play([(hz, 1.0)], ms: seg * 1000, level: level)
                elapsed += seg
                self.waitUntil(start + UInt64(elapsed * self.ticksPerSecond))
            }
            DispatchQueue.main.async {
                if case .singleTone = self.activeOperation {
                    self.activeOperation = .idle
                }
            }
        }
    }

    public func playNote(_ noteName: String) {
        let f = MusicTheory.hz(noteName)
        playTone(hz: f, ms: 350, level: 0.95)
    }

    // MARK: - Soundboard Presets

    public func playHeartbeat() {
        stopRequested = false
        workQueue.async {
            DispatchQueue.main.async {
                self.activeOperation = .heartbeat
                self.currentCaption = "Heartbeat: Thump... Thump..."
            }
            for _ in 0..<2 where !self.stopRequested {
                self.executeThump(1.0)
                self.pause(0.17)
                self.executeThump(0.7)
                self.pause(0.75)
            }
            DispatchQueue.main.async {
                self.activeOperation = .idle
                self.currentCaption = ""
            }
        }
    }

    public func executeThump(_ amp: Double) {
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

    public func playMelody() {
        stopRequested = false
        skipRequested = false
        workQueue.async {
            DispatchQueue.main.async {
                self.activeOperation = .melody
                self.currentCaption = "Singing “The Hook” (E6, G6, A6, C7...)"
            }
            self.executeSing()
            DispatchQueue.main.async {
                self.activeOperation = .idle
                self.currentCaption = ""
            }
        }
    }

    private func executeSing() {
        let beat = 60.0 / 112
        let melody: [(String, Double)] = [
            ("E6", 0.5), ("G6", 0.5), ("A6", 1), ("G6", 0.5), ("E6", 0.5), ("C6", 1),
            ("E6", 0.5), ("G6", 0.5), ("A6", 0.5), ("C7", 0.5), ("A6", 1), ("G6", 1),
            ("E6", 0.5), ("C6", 0.5), ("A5", 1), ("C6", 0.5), ("E6", 0.5), ("A6", 2.5)
        ]
        let phraseEnds: Set<Int> = [5, 11, 17]
        var previous: Double?
        let start = mach_absolute_time()
        var t = 0.0, at = 0.0

        for (i, (name, beats)) in melody.enumerated() {
            if stopRequested || skipRequested { break }
            let target = MusicTheory.hz(name)
            let length = beats * beat
            let sounding = phraseEnds.contains(i) ? length * 0.86 : length
            let from = previous

            while t < at + sounding && !stopRequested && !skipRequested {
                let age = t - at
                var f = target
                if let from, age < 0.045 {
                    f = from * pow(target / from, age / 0.045)
                } else if from == nil, age < 0.04 {
                    f = target * pow(2, -0.6 * (1 - age / 0.04) / 12)
                }
                if age > 0.2 {
                    f *= pow(2, min(1, (age - 0.2) / 0.25) * 0.22 * sin(2 * .pi * 5.8 * age) / 12)
                }
                var level = age < 0.015 ? 0.6 + 0.4 * age / 0.015 : 1.0
                if i == melody.count - 1 {
                    level *= max(0, 1 - age / length)
                }
                let seg = max(1, ((age < 0.06 ? 0.02 : 0.045) * f).rounded()) / f
                play([(f, 1)], ms: min(seg, at + sounding - t + 0.004) * 1000, level: Float(level))
                t += seg
                waitUntil(start + UInt64(t * ticksPerSecond))
            }
            previous = phraseEnds.contains(i) ? nil : target
            at += length
            if t < at {
                t = at
                waitUntil(start + UInt64(t * ticksPerSecond))
            }
        }
    }

    public func playGroove() {
        stopRequested = false
        skipRequested = false
        workQueue.async {
            DispatchQueue.main.async {
                self.activeOperation = .beat
                self.currentCaption = "Drums + Bass Groove"
            }
            let rapText = "No speaker. No wires. Just a motor and a beat."
            let rapFrames = (try? SpeechAcoustics.renderSpeech(rapText, voice: self.selectedVoice)) ?? []
            self.executeGroove(bars: 4, rapBar: 2, rap: rapFrames, rapText: rapText)
            DispatchQueue.main.async {
                self.activeOperation = .idle
                self.currentCaption = ""
            }
        }
    }

    private func executeGroove(bars: Int, rapBar: Int, rap: [SpeechFrame], rapText: String) {
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

        let rapStart = Double(rapBar) * barLen
        let end = Double(bars) * barLen
        var t = 0.0, next = 0, rapping = false
        var ringing: [Hit] = []
        let start = mach_absolute_time()

        while t < end && !stopRequested && !skipRequested {
            while next < hits.count, hits[next].t <= t + 0.0005 {
                ringing.append(hits[next])
                next += 1
            }
            ringing.removeAll { t - $0.t > 0.2 }
            let i16 = Int(t / s16)

            if !rapping, t >= rapStart {
                rapping = true
                DispatchQueue.main.async {
                    self.currentCaption = rapText
                }
            }

            var frame: SpeechFrame?
            if t >= rapStart {
                let idx = Int((t - rapStart) / SpeechAcoustics.hop)
                if idx < rap.count { frame = rap[idx] }
            }
            let talking = (frame?.level ?? 0) > 0
            let bass = bassHz[(i16 / 16) % bassHz.count]
            var carrier = bass
            if let f = frame, talking, f.voiced { carrier = f.f0 }
            var tones: [(hz: Double, amp: Double)] = []
            var step = 1 / carrier

            if let f = frame, talking {
                if f.voiced {
                    for v in SpeechAcoustics.voiceTones(f) {
                        tones.append((v.hz, Double(f.level) * v.amp))
                    }
                    DispatchQueue.main.async {
                        self.currentF0 = f.f0
                        self.currentF1 = f.formants[0]
                        self.currentF2 = f.formants[1]
                    }
                } else {
                    step = 0.004
                    for _ in 0..<2 {
                        tones.append((Double.random(in: 2700...4300), Double(f.level) * 0.4))
                    }
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
            if total > 0.01 {
                play(use, ms: step * 1000, level: Float(min(1, total)))
            }
            t += step
            waitUntil(start + UInt64(t * ticksPerSecond))
        }

        DispatchQueue.main.async {
            self.currentF0 = 0
            self.currentF1 = 0
            self.currentF2 = 0
        }
    }

    public func playSparkle() {
        stopRequested = false
        workQueue.async {
            DispatchQueue.main.async {
                self.activeOperation = .sparkle
                self.currentCaption = "Sparkle Arpeggio"
            }
            for n in ["A5", "C6", "E6", "A6", "C7"] where !self.stopRequested {
                let f = MusicTheory.hz(n)
                let seg = (0.07 * f).rounded() / f
                self.play([(f, 1)], ms: seg * 1000, level: 0.9)
                let end = mach_absolute_time() + UInt64(seg * self.ticksPerSecond)
                self.waitUntil(end)
            }
            let start = mach_absolute_time()
            var t = 0.0
            while t < 0.6 && !self.stopRequested {
                let seg = (0.02 * 3951).rounded() / 3951
                self.play([(3951, 1)], ms: seg * 1000, level: Float(exp(-t / 0.18)))
                t += seg
                self.waitUntil(start + UInt64(t * self.ticksPerSecond))
            }
            DispatchQueue.main.async {
                self.activeOperation = .idle
                self.currentCaption = ""
            }
        }
    }

    // MARK: - Interactive Trackpad Theremin ("Touch to Play")

    public func startTheremin() {
        stopRequested = false
        skipRequested = false

        guard startTouch() else {
            DispatchQueue.main.async {
                self.errorMessage = "Could not register touch callbacks with trackpad."
            }
            return
        }

        workQueue.async {
            DispatchQueue.main.async {
                self.activeOperation = .theremin
                self.currentCaption = "Touch & slide across trackpad to play music"
            }

            let scale = ["G5", "A5", "B5", "C6", "E6", "F6", "G6", "A6", "B6", "C7"].map(MusicTheory.hz)
            var current = scale[4]
            var lastDown = false, downAt = 0.0

            while !self.stopRequested {
                let c = getGlobalContact()
                guard c.down else {
                    lastDown = false
                    usleep(5000)
                    continue
                }
                if !lastDown { downAt = self.now() }
                lastDown = true

                let idx = min(scale.count - 1, max(0, Int((Double(c.x) * Double(scale.count)).rounded(.down))))
                let target = scale[idx]
                current *= pow(target / current, 0.3)
                let age = self.now() - downAt
                let depth = 0.05 + 0.45 * Double(max(0, min(1, c.y)))
                let f = current * pow(2, depth * sin(2 * .pi * 6 * age) / 12)
                let level = min(1, max(0.5, 0.3 + Double(c.size) * 0.8))
                let seg = max(1, (0.02 * f).rounded()) / f
                let t0 = mach_absolute_time()
                self.play([(f, 1)], ms: seg * 1000, level: Float(level))
                self.waitUntil(t0 + UInt64(seg * self.ticksPerSecond))
            }

            self.stopTouch()
            DispatchQueue.main.async {
                self.activeOperation = .idle
                self.currentCaption = ""
            }
        }
    }

    public func stopTheremin() {
        stopRequested = true
        stopTouch()
    }

    // MARK: - Full Show Mode

    public func startFullShow() {
        stopRequested = false
        skipRequested = false

        workQueue.async {
            let totalStages = 10
            func updateStage(_ stage: Int, _ name: String, _ caption: String) {
                DispatchQueue.main.async {
                    self.activeOperation = .show(stage: stage, name: name)
                    self.showStep = stage
                    self.showTotalSteps = totalStages
                    self.showProgressPercent = Double(stage) / Double(totalStages)
                    self.currentCaption = caption
                }
            }

            // 1. Loading & Preparing Voice
            updateStage(1, "LOADING", "Preparing speech synthesis & trackpad connection...")
            let hour = Calendar.current.component(.hour, from: Date())
            let hello = hour < 5 ? "You're up late." : hour < 12 ? "Good morning." : hour < 17 ? "Good afternoon." : hour < 22 ? "Good evening." : "You're up late."
            let greeting = "\(hello) I'm your trackpad. I don't have a speaker. I've been meaning to say something."
            let rapLine = "No speaker. No wires. Just a motor and a beat."
            let turnLine = "Your turn. Be gentle."
            let byeLine = "Okay. Back to clicking."

            let phrases = [greeting, rapLine, turnLine, byeLine]
            var voices: [String: [SpeechFrame]] = [:]
            for (idx, line) in phrases.enumerated() {
                if self.stopRequested { return }
                updateStage(1, "LOADING", "Synthesizing voice phrase \(idx + 1)/\(phrases.count)...")
                voices[line] = (try? SpeechAcoustics.renderSpeech(line, voice: self.selectedVoice)) ?? []
            }
            self.pause(0.8)

            // 2. Heartbeat
            if !self.stopRequested {
                self.skipRequested = false
                updateStage(2, "WAKING UP", "Waking up the trackpad...")
                self.executeThump(1.0); self.pause(0.17); self.executeThump(0.7); self.pause(0.75)
                self.executeThump(1.0); self.pause(0.17); self.executeThump(0.7); self.pause(0.75)
            }

            // 3. First Words
            if !self.stopRequested {
                self.skipRequested = false
                updateStage(3, "FIRST WORDS", greeting)
                if let frames = voices[greeting] {
                    self.executeTalk(frames: frames, text: greeting)
                }
                self.pause(0.8)
            }

            // 4. Sweep
            if !self.stopRequested {
                self.skipRequested = false
                updateStage(4, "SWEEP", "Frequency sweep: 100 Hz → 4,000 Hz")
                let start = mach_absolute_time()
                var t = 0.0
                while t < 5.0 && !self.stopRequested && !self.skipRequested {
                    let f = 100 * pow(40, t / 5.0)
                    let seg = max(1, (0.02 * f).rounded()) / f
                    self.play([(f, 1)], ms: seg * 1000, level: 1.0)
                    t += seg
                    self.waitUntil(start + UInt64(t * self.ticksPerSecond))
                }
                self.pause(0.4)
            }

            // 5. Melody
            if !self.stopRequested {
                self.skipRequested = false
                updateStage(5, "MELODY", "Singing “The Hook”")
                self.executeSing()
                self.pause(0.5)
            }

            // 6. Beat & Rap
            if !self.stopRequested {
                self.skipRequested = false
                updateStage(6, "BEAT & RAP", rapLine)
                if let rapFrames = voices[rapLine] {
                    self.executeGroove(bars: 4, rapBar: 2, rap: rapFrames, rapText: rapLine)
                }
                self.pause(0.5)
            }

            // 7. Your Turn Intro
            if !self.stopRequested {
                self.skipRequested = false
                updateStage(7, "YOUR TURN", turnLine)
                if let turnFrames = voices[turnLine] {
                    self.executeTalk(frames: turnFrames, text: turnLine)
                }
                self.pause(0.4)
            }

            // 8. Touch to play (Instrument)
            if !self.stopRequested {
                self.skipRequested = false
                updateStage(8, "TOUCH TO PLAY", "Touch the trackpad! Slide finger for pitch (8 seconds)")
                _ = self.startTouch()
                let waitEnd = self.now() + 6.0
                while self.now() < waitEnd && !self.stopRequested && !self.skipRequested && !getGlobalContact().down {
                    usleep(5000)
                }
                if getGlobalContact().down {
                    let playEnd = self.now() + 8.0
                    let scale = ["G5", "A5", "B5", "C6", "E6", "F6", "G6", "A6", "B6", "C7"].map(MusicTheory.hz)
                    var current = scale[4]
                    var lastDown = false, downAt = 0.0
                    while self.now() < playEnd && !self.stopRequested && !self.skipRequested {
                        let c = getGlobalContact()
                        guard c.down else { lastDown = false; usleep(5000); continue }
                        if !lastDown { downAt = self.now() }
                        lastDown = true
                        let idx = min(scale.count - 1, max(0, Int((Double(c.x) * Double(scale.count)).rounded(.down))))
                        let target = scale[idx]
                        current *= pow(target / current, 0.3)
                        let age = self.now() - downAt
                        let depth = 0.05 + 0.45 * Double(max(0, min(1, c.y)))
                        let f = current * pow(2, depth * sin(2 * .pi * 6 * age) / 12)
                        let level = min(1, max(0.5, 0.3 + Double(c.size) * 0.8))
                        let seg = max(1, (0.02 * f).rounded()) / f
                        let t0 = mach_absolute_time()
                        self.play([(f, 1)], ms: seg * 1000, level: Float(level))
                        self.waitUntil(t0 + UInt64(seg * self.ticksPerSecond))
                    }
                }
                self.stopTouch()
            }

            // 9. Interactive Speech Preview
            if !self.stopRequested {
                self.skipRequested = false
                updateStage(9, "SAY ANYTHING", "“Can you hear me now?”")
                let sampleLine = "Can you hear me whispering through the glass?"
                if let frames = (try? SpeechAcoustics.renderSpeech(sampleLine, voice: self.selectedVoice)) {
                    self.executeTalk(frames: frames, text: sampleLine)
                }
                self.pause(0.5)
            }

            // 10. Outro
            if !self.stopRequested {
                self.skipRequested = false
                updateStage(10, "OUTRO", byeLine)
                if let byeFrames = voices[byeLine] {
                    self.executeTalk(frames: byeFrames, text: byeLine)
                }
                // Sparkle
                for n in ["A5", "C6", "E6", "A6", "C7"] where !self.stopRequested {
                    let f = MusicTheory.hz(n)
                    let seg = (0.07 * f).rounded() / f
                    self.play([(f, 1)], ms: seg * 1000, level: 0.9)
                    let end = mach_absolute_time() + UInt64(seg * self.ticksPerSecond)
                    self.waitUntil(end)
                }
                let start = mach_absolute_time()
                var t = 0.0
                while t < 0.6 && !self.stopRequested {
                    let seg = (0.02 * 3951).rounded() / 3951
                    self.play([(3951, 1)], ms: seg * 1000, level: Float(exp(-t / 0.18)))
                    t += seg
                    self.waitUntil(start + UInt64(t * self.ticksPerSecond))
                }
                self.pause(1.0)
            }

            DispatchQueue.main.async {
                self.activeOperation = .idle
                self.currentCaption = "The show has completed!"
                self.showProgressPercent = 1.0
            }
        }
    }
}
