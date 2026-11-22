import Foundation
import Darwin

// MARK: - The show

func playDemo(visuals: Bool) {
    let say = { (s: String) in if !visuals { print(s) } }
    updateLiveState { $0.started = now() }
    if visuals { takeTerminal(); startKeys(); startRenderer() }
    pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0)

    // 1. Intro: what's about to happen, while the voice is prepared (a real loading bar).
    enter(.intro, 1, "LOADING")
    let localizedText = speechLanguage.demoText
    say(localizedText.introduction)
    let introStart = now()
    let rhythmLine = localizedText.rhythm
    let invitationLine = localizedText.invitation
    let farewellLine = localizedText.farewell
    let greeting = speechLanguage.currentGreeting
    let phrases = [greeting, rhythmLine, invitationLine, farewellLine]
    let steps = 2 + phrases.count
    func progress(_ done: Int, _ label: String) {
        updateLiveState { $0.stepDone = done; $0.stepTotal = steps }
    }
    progress(0, "opening MultitouchSupport.framework")
    pause(0.6)
    progress(1, "connecting to the trackpad")
    pause(0.5)
    var voices: [String: [SpeechFrame]] = [:]
    for (i, line) in phrases.enumerated() where !stopRequested {
        progress(2 + i, "preparing the voice \(i + 1)/\(phrases.count)")
        voices[line] = synthesizeSpeechFrames(line)
    }
    progress(steps, "ready")
    pause(max(0.6, 4.0 - (now() - introStart)))
    // The proof is the point: hold here until the speakers are muted (space starts anyway; 15 s at most).
    if visuals {
        let holdUntil = now() + 15
        while speakersMuted() == false && !interrupted() && now() < holdUntil { usleep(100_000) }
        if speakersMuted() == true { updateLiveState { $0.muted = true }; pause(1.2) }
        skipRequested = false
    }

    // 2. It wakes up: a heartbeat, no words yet.
    if !stopRequested && !jumpToCredits { enter(.heart, 2, "WAKING UP"); pause(0.3); playHeartbeat() }
    // 3. Its first words: hello, who it is, what it knows (the reveal).
    if !stopRequested && !jumpToCredits { enter(.talk, 3, speechLanguage.interfaceText.firstWordsTitle); say("“\(greeting)”"); pause(0.4); playSpeech(voices[greeting]!, text: greeting); pause(0.9) }
    // 4. How: the sweep.
    if !stopRequested && !jumpToCredits { enter(.sweep, 4, "SWEEP"); say("sweep 100 Hz → 4 kHz"); pause(0.3); playFrequencySweep(); pause(0.4) }
    // 5. Melody.
    if !stopRequested && !jumpToCredits { enter(.sing, 5, "MELODY"); say("♪ melody"); pause(0.4); playMelody(); pause(0.5) }
    // 6. Beat, then the rap over it.
    if !stopRequested && !jumpToCredits {
        enter(.beat, 6, "BEAT"); say("beat · then rap: “\(rhythmLine)”")
        playRhythm(bars: 4, rapBar: 2, rap: voices[rhythmLine]!, rapText: rhythmLine); pause(0.5)
    }
    // 7. Your turn.
    if !stopRequested && !jumpToCredits { enter(.yourTurn, 7, speechLanguage.interfaceText.invitationTitle); say("“\(invitationLine)”"); pause(0.3); playSpeech(voices[invitationLine]!, text: invitationLine); pause(0.4) }
    // 8. Touch to play.
    if !stopRequested && !jumpToCredits { enter(.touch, 8, "TOUCH TO PLAY"); say("touch the trackpad: slide for pitch (12 s)"); playTouchInstrument() }
    // 9. Say anything (only with the screen: it needs typing).
    if !stopRequested && !jumpToCredits && visuals { enter(.say, 9, speechLanguage.interfaceText.inputTitle); runInteractiveSpeech() }
    // 10. Outro.
    if !stopRequested {
        jumpToCredits = false
        inCredits = true
        enter(.outro, 10, "OUTRO")
        playSpeech(voices[farewellLine] ?? synthesizeSpeechFrames(farewellLine), text: farewellLine)
        updateLiveState { $0.scene = .outro }
        playOutroNotes()
        if visuals {
            keyPressed = false
            updateLiveState { $0.waitingForKey = true }
            while !keyPressed && !stopRequested { usleep(20_000) }
        } else {
            pause(1.0)
        }
    }

    let s = snapshotLiveState()
    if visuals { stopRenderer(); restoreTerminal() }
    signOff(seconds: Int(now() - s.started), actuations: s.actuations)
}

func signOff(seconds: Int, actuations: Int) {
    // The sign-off: the logo stays in their terminal as a souvenir, with what to run next.
    // Plain bold and dim only, so it reads in any terminal theme.
    let esc = "\u{1B}["
    let vibrations = NumberFormatter.localizedString(from: NSNumber(value: actuations), number: .decimal)
    var me = CommandLine.arguments[0].contains("/") ? CommandLine.arguments[0] : "nospeaker"
    let home = NSHomeDirectory()
    if me.hasPrefix(home + "/") { me = "~" + me.dropFirst(home.count) }
    print("")
    let lockup = logoLockup()
    for (i, line) in lockup.enumerated() { print("  " + (i < asciiLogo.count ? "\(esc)1m" : "\(esc)2m") + line + "\(esc)0m") }
    print("")
    print("  \(esc)1m\(seconds / 60):" + String(format: "%02d", seconds % 60) + "\(esc)0m  ·  \(esc)1m\(vibrations)\(esc)0m vibrations  ·  \(esc)1m0\(esc)0m speakers used")
    print("  more        \(esc)1mx.com/codycollier\(esc)0m")
    print("  play again  \(esc)2m\(me)\(esc)0m")
    print("  say a line  \(esc)2m\(me) \"hello there\"\(esc)0m")
    print("")
}
