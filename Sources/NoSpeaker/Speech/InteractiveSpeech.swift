import Foundation
import Darwin

func saySuggestion(at time: Double) -> String {
    let phrases = speechLanguage.suggestedPhrases
    return phrases[Int(time / 3) % phrases.count]
}

func runInteractiveSpeech() {
    for _ in 0..<5 where !stopRequested && !jumpToCredits {
        updateLiveState { $0.inputActive = true; $0.inputText = ""; $0.inputSubmitted = false; $0.sayStatus = "typing"; $0.caption = "" }
        var lastChange = now(), lastText = ""
        while !stopRequested && !jumpToCredits {
            let st = snapshotLiveState()
            if st.inputSubmitted || st.inputDone { break }
            if st.inputText != lastText { lastText = st.inputText; lastChange = now() }
            if now() - lastChange > 25 { updateLiveState { $0.inputDone = true }; break }
            usleep(20_000)
        }
        let st = snapshotLiveState()
        updateLiveState { $0.inputActive = false }
        let text = st.inputText.trimmingCharacters(in: .whitespaces)
        if st.inputDone || text.isEmpty || stopRequested || jumpToCredits { break }
        updateLiveState { $0.sayStatus = "preparing" }
        let frames = synthesizeSpeechFrames(text)
        updateLiveState { $0.sayStatus = "speaking"; $0.sayCount += 1 }
        playSpeech(frames, text: text)
        pause(0.6)
    }
    updateLiveState { $0.inputActive = false }
}
