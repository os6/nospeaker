import AVFoundation
import Foundation

/// Foundation's Process turns accented command arguments into decomposed UTF-8.
/// The macOS say command matches voice names byte-for-byte and silently uses
/// the default voice when given a decomposed name such as "Tünde".
///
/// Use the ASCII AVSpeechSynthesisVoice identifier for accented voice names,
/// preserving the original English behavior when no voice is requested.
func sayVoiceArgument(for requestedName: String?) -> String? {
    guard let requestedName else { return nil }
    if requestedName.unicodeScalars.allSatisfy(\.isASCII) {
        return requestedName
    }

    let matchingVoices = AVSpeechSynthesisVoice.speechVoices().filter {
        $0.name.caseInsensitiveCompare(requestedName) == .orderedSame &&
        $0.identifier.unicodeScalars.allSatisfy(\.isASCII)
    }
    let resolvedVoice = matchingVoices.first {
        $0.identifier.contains(".compact.")
    } ?? matchingVoices.first

    guard let resolvedVoice else {
        fail("macOS cannot resolve the Unicode voice name \"\(requestedName)\" " +
             "to a usable voice identifier.",
             headline: "nospeaker cannot use that voice.", code: 64)
    }
    return resolvedVoice.identifier
}
