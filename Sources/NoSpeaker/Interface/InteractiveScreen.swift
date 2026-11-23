import Foundation
import Darwin

func drawSay(_ canvas: Canvas, _ state: LiveState, _ elapsedTime: Double) {
    canvas.text(6, 10, speechLanguage.interfaceText.inputHeading, inkC, bold: true)
    canvas.text(6, 11, speechLanguage.interfaceText.inputHint, midC)
    // The input box.
    let w = 68, x0 = 6
    canvas.text(x0, 12, "+" + String(repeating: "-", count: w - 2) + "+", state.inputActive ? bodyC : ruleC)
    canvas.text(x0, 13, "|", state.inputActive ? bodyC : ruleC); canvas.text(x0 + w - 1, 13, "|", state.inputActive ? bodyC : ruleC)
    canvas.text(x0, 14, "+" + String(repeating: "-", count: w - 2) + "+", state.inputActive ? bodyC : ruleC)
    if state.inputActive {
        let caret = Int(elapsedTime * 2.5) % 2 == 0 ? "_" : " "
        let shown = String(state.inputText.suffix(w - 6))
        canvas.text(x0 + 2, 13, ">", midC)
        canvas.text(x0 + 4, 13, shown + caret, inkC, bold: true)
        if state.inputText.isEmpty {
            canvas.text(x0 + 6, 13, "try: " + saySuggestion(at: elapsedTime), dimC)
            canvas.text(x0 + w - 3 - 13, 13, "tab to use it", faintC)
        }
    }
    switch state.sayStatus {
    case "preparing":
        canvas.text(6, 16, "preparing the voice " + ["|", "/", "-", "\\"][Int(elapsedTime * 10) % 4], midC)
    case "speaking":
        drawCaption(canvas, state, elapsedTime, y: 16)
    default:
        if state.sayCount > 0 { canvas.text(6, 16, "type another one, or finish below", midC) }
    }
    let finish = "when you're done, press  ESC  to see the credits"
    canvas.text(6, 19, finish, inkC, bold: true)
    if let r = finish.range(of: " ESC ") {
        canvas.text(6 + finish.distance(from: finish.startIndex, to: r.lowerBound), 19, " ESC ", paperC, bg: inkC, bold: true)
    }
    canvas.text(6 + finish.count + 2, 19, "return to speak", dimC)
}

func drawOutro(_ canvas: Canvas, _ state: LiveState, _ elapsedTime: Double) {
    let rows: [(String, String)] = [
        ("code, sound, design", "a90"), ("web", "a90.com"),
        ("speakers used", "0"), ("vibrations", NumberFormatter.localizedString(from: NSNumber(value: state.actuations), number: .decimal)),
        ("runtime", String(format: "%.1f s", elapsedTime - state.started)),
    ]
    canvas.centered(10, "C R E D I T S", inkC, bold: true)
    for (i, r) in rows.enumerated() {
        let d = dots(r.0, r.1, width: 52)
        canvas.text(14, 12 + i, d, dimC)
        canvas.text(14 + d.count, 12 + i, r.1, inkC, bold: true)
    }
    if state.waitingForKey {
        let line = "follow @codycollier for more; press  F  to open"
        let x = (80 - line.count) / 2
        canvas.text(x, 18, line, inkC, bold: true)
        if let f = line.range(of: " F ") {
            canvas.text(x + line.distance(from: line.startIndex, to: f.lowerBound), 18, " F ", paperC, bg: inkC, bold: true)
        }
        if elapsedTime - state.followOpenedAt < 2.5 {
            canvas.centered(19, "opened x.com/codycollier in your browser", bodyC)
        } else {
            let blink = Int(elapsedTime * 2) % 2 == 0
            canvas.centered(19, "any other key exits", blink ? midC : dimC)
        }
    } else {
        canvas.centered(19, "thanks for listening", dimC)
    }
}
