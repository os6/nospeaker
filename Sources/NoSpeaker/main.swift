import Foundation
import Darwin

// MARK: - Main

var remainingArguments = Array(CommandLine.arguments.dropFirst())
/// The value after `flag` (and removes both), or nil if the flag isn't there. A flag with no value is a mistake.
func takeOption(_ optionName: String, example: String) -> String? {
    guard let optionIndex = remainingArguments.firstIndex(of: optionName) else { return nil }
    guard optionIndex + 1 < remainingArguments.count,
          !remainingArguments[optionIndex + 1].hasPrefix("-") else {
        usageError("\(optionName) needs a value, like: \(optionName) \(example)")
    }
    let optionValue = remainingArguments[optionIndex + 1]
    remainingArguments.removeSubrange(optionIndex...(optionIndex + 1))
    return optionValue
}

func takeFlag(_ flagName: String) -> Bool {
    guard let flagIndex = remainingArguments.firstIndex(of: flagName) else { return false }
    remainingArguments.remove(at: flagIndex)
    return true
}

if takeFlag("--help") || takeFlag("-h") {
    print("""
    NO SPEAKER · a90.com presents
    Your MacBook's trackpad has no speaker. This makes it talk anyway, through its haptic motor.

      nospeaker                         the show (space skips a part, q goes to the end)
      nospeaker "hello there"         speak English (default)
      nospeaker --lang hu "Szia!"      speak Hungarian
      nospeaker --lang en "Hello"      speak English explicitly
      nospeaker --preview --lang hu "Szia!"  hear the motor signal on speakers
      nospeaker --preview-wav sound.wav "hello"  export the simulated signal
      nospeaker --lang hu --phonemes "Hogy vagy?"  approximate Hungarian IPA
      nospeaker --sweep                 a rising tone, 100 Hz to 4 kHz
      --lang en|hu                     speech language (default: en)
      --voice Daniel                   any voice from `say -v '?'`
      --dark                            white on black instead of black on white
      --plain                           no visuals

    Mute your Mac: it still talks. Put it on a table, and keep your hands off the trackpad until it asks.
    a90.com · x.com/codycollier
    """)
    exit(0)
}

let requestedLanguage = takeOption("--lang", example: "en") ?? SpeechLanguage.defaultLanguage.rawValue
guard let chosenLanguage = SpeechLanguage(rawValue: requestedLanguage) else {
    usageError("--lang must be en or hu.")
}
speechLanguage = chosenLanguage
voiceOverrideName = takeOption("--voice", example: "Daniel")
let selectedVoice = speechLanguage.selectedVoiceName(overriding: voiceOverrideName)
if let selectedVoice, !isSystemVoiceAvailable(selectedVoice) {
    fail("There's no voice called \"\(selectedVoice)\" on this Mac.\nList the voices you have with: say -v '?'", headline: "nospeaker can't use that voice.", code: 64)
}
applyTheme(light: !takeFlag("--dark"))
let plain = takeFlag("--plain")
let wantsSweep = takeFlag("--sweep")
let wantsSpeakerPreview = takeFlag("--preview")
let previewFilePath = takeOption("--preview-wav", example: "preview.wav")
let wantsPhonemes = takeFlag("--phonemes")
if let unknown = remainingArguments.first(where: { $0.hasPrefix("-") }) { usageError("\"\(unknown)\" isn't an option.") }

signal(SIGINT) { _ in requestEnd() }
signal(SIGTERM) { _ in stopRequested = true }
atexit { restoreTerminal() }

if wantsPhonemes {
    guard speechLanguage == .hungarian, !remainingArguments.isEmpty,
          !wantsSweep, !wantsSpeakerPreview, previewFilePath == nil else {
        usageError("--phonemes requires --lang hu and text, without playback options.")
    }
    let phrase = remainingArguments.joined(separator: " ")
    print("Hungarian phoneme inventory (approximate IPA): /\(HungarianPhonology.approximateIPA(phrase))/")
    exit(0)
}

if wantsSpeakerPreview || previewFilePath != nil {
    guard !wantsSweep, !remainingArguments.isEmpty else {
        usageError("Speaker preview requires text and cannot be combined with --sweep.")
    }
    let phrase = remainingArguments.joined(separator: " ")
    let speechFrames = synthesizeSpeechFrames(phrase)
    let outputURL = previewFilePath.map { URL(fileURLWithPath: $0) } ??
        FileManager.default.temporaryDirectory
            .appendingPathComponent("nospeaker-preview-\(getpid()).wav")
    do {
        try SpeakerPreview.render(speechFrames, to: outputURL)
        if wantsSpeakerPreview {
            print("Speaker preview (no trackpad): \(phrase)")
            try SpeakerPreview.play(outputURL)
        } else {
            print("WAV preview saved: \(outputURL.path)")
        }
    } catch {
        if previewFilePath == nil { try? FileManager.default.removeItem(at: outputURL) }
        fail(error.localizedDescription, headline: "Speaker preview failed.")
    }
    if previewFilePath == nil { try? FileManager.default.removeItem(at: outputURL) }
    exit(0)
}

motor = openMotor()
motorPointer = Unmanaged.passUnretained(motor! as AnyObject).toOpaque()

if wantsSweep || !remainingArguments.isEmpty {
    pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0)
    if wantsSweep { print("sweeping 100 Hz → 4 kHz…"); playFrequencySweep(seconds: 5) }
    if !remainingArguments.isEmpty {
        let text = remainingArguments.joined(separator: " ")
        let frames = synthesizeSpeechFrames(text)
        print("trackpad: “\(text)”")
        playSpeech(frames, text: text)
    }
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
    playDemo(visuals: visuals)
}
usleep(120_000)
if let motor { _ = actuatorClose?(motor) }
