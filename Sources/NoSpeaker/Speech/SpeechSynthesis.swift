import Foundation
import Darwin
import AVFoundation

// MARK: - Speech analysis

struct SpeechFrame {
    var formants: [Double] = [500, 1500, 2500]
    var amps: [Double] = [1, 0.5, 0.25]
    var level: Float = 0
    var voiced = false
    var f0 = 110.0
    var frameIntervalSeconds = hop
    // Frequency-domain output supplied by the separate Hungarian vocoder.
    var hungarianTones: [(hz: Double, amp: Double)] = []
}
let hop = 0.010
let sampleRate = 16000.0
var voiceOverrideName: String?

/// True if `say` has a voice by this name. (`say` quietly falls back to the default voice for unknown names.)
func isSystemVoiceAvailable(_ name: String) -> Bool {
    let voiceListingProcess = Process()
    let voiceListingOutput = Pipe()
    voiceListingProcess.executableURL = URL(fileURLWithPath: "/usr/bin/say")
    voiceListingProcess.arguments = ["-v", "?"]
    voiceListingProcess.standardOutput = voiceListingOutput

    guard (try? voiceListingProcess.run()) != nil else { return true }
    let availableVoices = String(
        data: voiceListingOutput.fileHandleForReading.readDataToEndOfFile(),
        encoding: .utf8
    ) ?? ""
    voiceListingProcess.waitUntilExit()
    let requestedVoice = name.lowercased()
    return availableVoices.split(separator: "\n").contains { voiceDescription in
        let normalizedDescription = voiceDescription.lowercased()
        return normalizedDescription.hasPrefix(requestedVoice + " ") ||
               normalizedDescription.hasPrefix(requestedVoice + "\t")
    }
}

func synthesizeSpeechFrames(_ text: String) -> [SpeechFrame] {
    let temporaryAudioURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("nospeaker-\(getpid()).wav")
    defer { try? FileManager.default.removeItem(at: temporaryAudioURL) }

    let synthesisProcess = Process()
    synthesisProcess.executableURL = URL(fileURLWithPath: "/usr/bin/say")
    let voiceToUse = speechLanguage.selectedVoiceName(overriding: voiceOverrideName)
    let voiceArguments = voiceToUse.map { ["-v", $0] } ?? []
    synthesisProcess.arguments = [
        "-o", temporaryAudioURL.path,
        "--file-format=WAVE", "--data-format=LEF32@16000"
    ] + voiceArguments + [text]
    do {
        try synthesisProcess.run()
    } catch {
        fail("It couldn't run macOS's voice (/usr/bin/say), which it needs to talk.")
    }
    synthesisProcess.waitUntilExit()

    guard synthesisProcess.terminationStatus == 0,
          let audioFile = try? AVAudioFile(forReading: temporaryAudioURL),
          let audioBuffer = AVAudioPCMBuffer(
            pcmFormat: audioFile.processingFormat,
            frameCapacity: AVAudioFrameCount(audioFile.length)
          ),
          (try? audioFile.read(into: audioBuffer)) != nil,
          let channelSamples = audioBuffer.floatChannelData?[0] else {
        if let voiceOverrideName {
            fail("There's no voice called \"\(voiceOverrideName)\" on this Mac.\nList the voices you have with: say -v '?'",
                 headline: "nospeaker can't use that voice.")
        }
        fail("macOS's voice (say) couldn't speak that line.",
             headline: "nospeaker couldn't prepare its voice.")
    }

    let samples = Array(UnsafeBufferPointer(start: channelSamples, count: Int(audioBuffer.frameLength)))
    var speechFrames = speechLanguage == .hungarian
        ? HungarianVocoder.encode(samples)
        : analyzeSpeechSamples(samples)
    while speechFrames.first?.level == 0 { speechFrames.removeFirst() }
    while speechFrames.last?.level == 0 { speechFrames.removeLast() }
    return speechFrames
}
