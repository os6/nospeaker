import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

expect(SpeechLanguage.defaultLanguage == .english, "English must remain the default")
expect(SpeechLanguage(rawValue: "en") == .english, "English CLI identifier")
expect(SpeechLanguage(rawValue: "hu") == .hungarian, "Hungarian CLI identifier")
expect(SpeechLanguage(rawValue: "de") == nil, "Unsupported language must fail")
expect(SpeechLanguage.english.systemVoiceName == "Daniel", "English system voice")
expect(SpeechLanguage.hungarian.systemVoiceName == "Tünde", "Hungarian system voice")

let englishDemo = SpeechLanguage.english.demoText
let hungarianDemo = SpeechLanguage.hungarian.demoText
expect(englishDemo.rhythm.contains("speaker"), "English demo remains available")
expect(hungarianDemo.rhythm.contains("hangszóró"), "Hungarian demo is localized")
expect(SpeechLanguage.english.greeting(atHour: 9).hasPrefix("Good morning"), "English greeting")
expect(SpeechLanguage.hungarian.greeting(atHour: 9).hasPrefix("Jó reggelt"), "Hungarian greeting")
expect(SpeechLanguage.hungarian.greeting(atHour: 20).hasPrefix("Jó estét"), "Hungarian evening")
expect(SpeechLanguage.hungarian.suggestedPhrases.contains("Szia, hogy vagy?"), "Hungarian sample text")
expect(SpeechLanguage.english.interfaceText.inputTitle == "SAY ANYTHING", "English interface")
expect(SpeechLanguage.hungarian.interfaceText.inputTitle == "MONDJ VALAMIT", "Hungarian interface")
expect(SpeechLanguage.hungarian.suggestedPhrases.joined().contains("ő"),
       "Hungarian accented vowels are retained")
print("PASS: language selection, voices, localization and accented text")
