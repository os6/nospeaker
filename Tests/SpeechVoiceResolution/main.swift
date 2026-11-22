import AVFoundation
import Foundation

func fail(_ message: String, headline: String = "", code: Int32 = 1) -> Never {
    fatalError("\(headline) \(message) \(code)")
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError("FAIL: \(message)") }
}

expect(sayVoiceArgument(for: nil) == nil,
       "No English override must remain the system default")
expect(sayVoiceArgument(for: "Daniel") == "Daniel",
       "ASCII English voice selection must not be changed")

let hungarianVoices = AVSpeechSynthesisVoice.speechVoices().filter {
    $0.name == "Tünde"
}

if !hungarianVoices.isEmpty {
    let resolvedName = sayVoiceArgument(for: "Tünde")
    let lowercaseName = sayVoiceArgument(for: "tünde")
    expect(resolvedName != "Tünde", "Accented voice name must use its ASCII ID")
    expect(resolvedName == lowercaseName, "Voice names are case-insensitive")
    expect(resolvedName?.unicodeScalars.allSatisfy(\.isASCII) == true,
           "Resolved command-line voice ID must contain only ASCII")
    expect(hungarianVoices.contains { $0.identifier == resolvedName },
           "Resolved ID must correspond to the installed Hungarian voice")
}

print("PASS: Unicode voice IDs and unchanged English defaults")
