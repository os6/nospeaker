import Foundation

/// Public command-line language identifiers stay stable for scripts and users.
enum SpeechLanguage: String, CaseIterable {
    case english = "en"
    case hungarian = "hu"

    static let defaultLanguage: SpeechLanguage = .english

    var systemVoiceName: String {
        switch self {
        case .english: return "Daniel"
        case .hungarian: return "Tünde"
        }
    }

    var demoText: DemoText {
        switch self {
        case .english:
            return DemoText(
                introduction: "a90.com presents NO SPEAKER. Your trackpad doesn't have one. In a moment it's going to talk.",
                rhythm: "No speaker. No wires. Just a motor and a beat.",
                invitation: "Your turn. Be gentle.",
                farewell: "Okay. Back to clicking."
            )
        case .hungarian:
            return DemoText(
                introduction: "A NO SPEAKER bemutatja: a trackpad hangszóró nélkül is megszólal.",
                rhythm: "Nincs hangszóró. Nincs kábel. Csak a motor és a ritmus.",
                invitation: "Most te jössz. Finoman érints meg!",
                farewell: "Rendben. Most már újra kattinthatsz."
            )
        }
    }

    func greeting(atHour hour: Int) -> String {
        switch self {
        case .english:
            let greeting = hour < 5 ? "You're up late." : hour < 12 ? "Good morning." :
                hour < 17 ? "Good afternoon." : hour < 22 ? "Good evening." : "You're up late."
            return "\(greeting) I'm your trackpad. I don't have a speaker. I've been meaning to say something."
        case .hungarian:
            let greeting = hour < 5 ? "Még ébren vagy?" : hour < 12 ? "Jó reggelt!" :
                hour < 17 ? "Jó napot!" : hour < 22 ? "Jó estét!" : "Még ébren vagy?"
            return "\(greeting) Én vagyok a trackpaded. Nincs hangszóróm, mégis tudok beszélni."
        }
    }

    var currentGreeting: String {
        greeting(atHour: Calendar.current.component(.hour, from: Date()))
    }

    var interfaceText: LanguageInterfaceText {
        switch self {
        case .english:
            return LanguageInterfaceText(
                firstWordsTitle: "FIRST WORDS",
                invitationTitle: "YOUR TURN",
                inputTitle: "SAY ANYTHING",
                inputHeading: "▸ SAY ANYTHING",
                inputHint: "type something and press return. it'll say it."
            )
        case .hungarian:
            return LanguageInterfaceText(
                firstWordsTitle: "ELSŐ SZAVAK",
                invitationTitle: "TE JÖSSZ",
                inputTitle: "MONDJ VALAMIT",
                inputHeading: "▸ ÍRJ VALAMIT",
                inputHint: "Írj egy szöveget, majd nyomj Entert."
            )
        }
    }

    var suggestedPhrases: [String] {
        switch self {
        case .english:
            return ["can you hear me?", "please stop clicking me", "this is not a speaker",
             "nobody believes me", "i live under the glass", "hello from the trackpad"]
        case .hungarian:
            return ["Hallani engem?", "Ne kattints rám!", "Én nem vagyok hangszóró.",
             "A trackpad alatt lakom.", "Szia, hogy vagy?", "Gyönyörű idő van!"]
        }
    }
}

struct DemoText {
    let introduction: String
    let rhythm: String
    let invitation: String
    let farewell: String
}

/// English is the default. A user-supplied --voice overrides this selection.
var speechLanguage: SpeechLanguage = .defaultLanguage

struct LanguageInterfaceText {
    let firstWordsTitle: String
    let invitationTitle: String
    let inputTitle: String
    let inputHeading: String
    let inputHint: String
}
