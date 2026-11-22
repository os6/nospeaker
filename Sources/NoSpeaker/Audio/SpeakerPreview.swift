import AVFoundation
import Foundation

/// The electronic waveform is audible on normal speakers without touching
/// MultitouchSupport. This is not a calibration of the physical motor or glass.
enum SpeakerPreview {
    static let samplingRate = 16000.0
    static let maximumDuration = 20.0
    static let safeGain = 0.22

    static func render(_ frames: [SpeechFrame], to destination: URL) throws {
        guard let firstFrame = frames.first else { throw PreviewError.invalidDuration }
        let requestedDuration = Double(frames.count) * firstFrame.frameIntervalSeconds
        guard requestedDuration > 0, requestedDuration <= maximumDuration else {
            throw PreviewError.invalidDuration
        }
        let frameCount = Int(ceil(requestedDuration * samplingRate)) + 128
        guard let audioFormat = AVAudioFormat(standardFormatWithSampleRate: samplingRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: audioFormat,
                                            frameCapacity: AVAudioFrameCount(frameCount)),
              let samples = buffer.floatChannelData?[0] else {
            throw PreviewError.audioBufferUnavailable
        }
        buffer.frameLength = AVAudioFrameCount(frameCount)
        samples.initialize(repeating: 0, count: frameCount)

        enumerateSpeechActuations(frames, realtime: false) { startTime, actuation in
            let startIndex = Int((startTime * samplingRate).rounded())
            let durationSamples = Int((actuation.durationSeconds * samplingRate).rounded())
            guard durationSamples > 0, startIndex < frameCount else { return }
            let amplitudeSum = max(0.0001, actuation.tones.reduce(0) { $0 + $1.amp })
            let outputGain = safeGain * Double(max(0, min(1, actuation.level)))

            for sampleOffset in 0..<min(durationSamples, frameCount - startIndex) {
                let localTime = Double(sampleOffset) / samplingRate
                let waveform = actuation.tones.reduce(0.0) { currentValue, tone in
                    currentValue + (tone.amp / amplitudeSum) *
                        sin(2 * .pi * tone.hz * localTime)
                }
                samples[startIndex + sampleOffset] += Float(outputGain * waveform)
            }
        }
        let audioFile = try AVAudioFile(forWriting: destination, settings: audioFormat.settings)
        try audioFile.write(from: buffer)
    }

    static func play(_ audioURL: URL) throws {
        let audioPlayer = Process()
        audioPlayer.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
        audioPlayer.arguments = [audioURL.path]
        try audioPlayer.run()
        audioPlayer.waitUntilExit()
        guard audioPlayer.terminationStatus == 0 else { throw PreviewError.playbackFailed }
    }
}

enum PreviewError: LocalizedError {
    case invalidDuration
    case audioBufferUnavailable
    case playbackFailed

    var errorDescription: String? {
        switch self {
        case .invalidDuration: "Preview text must produce 0–20 seconds of speech."
        case .audioBufferUnavailable: "Could not allocate a speaker-preview audio buffer."
        case .playbackFailed: "macOS could not play the speaker preview."
        }
    }
}
