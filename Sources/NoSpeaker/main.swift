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
if let unknown = remainingArguments.first(where: { $0.hasPrefix("-") }) { usageError("\"\(unknown)\" isn't an option.") }

signal(SIGINT) { _ in requestEnd() }
signal(SIGTERM) { _ in stopRequested = true }
atexit { restoreTerminal() }

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
