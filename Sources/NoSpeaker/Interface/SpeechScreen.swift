import Foundation
import Darwin

func drawCaption(_ canvas: Canvas, _ state: LiveState, _ elapsedTime: Double, y: Int) {
    let progress = min(1, (elapsedTime - state.captionStart) / max(0.2, state.captionDur) * 1.15)
    let shown = String(state.caption.prefix(Int(Double(state.caption.count) * progress)))
    // A blinking caret while it types; the closing quote once the line is done.
    let caret = progress >= 1 ? "”" : Int(elapsedTime * 3) % 2 == 0 ? "█" : " "
    var lines: [String] = [], line = ""
    for word in shown.split(separator: " ", omittingEmptySubsequences: false) {
        if line.count + word.count + 1 > 64 { lines.append(line); line = String(word) } else { line += line.isEmpty ? String(word) : " " + word }
    }
    lines.append(line + caret)
    // Quotes hug the words on both ends: “like this”.
    let shown2 = Array(lines.suffix(2))
    for (i, l) in shown2.enumerated() {
        if i == 0 && lines.count <= 2 { canvas.text(7, y, "“", midC, bold: true) }
        canvas.text(8, y + i, l, inkC, bold: true)
    }
}

func meter(_ canvas: Canvas, y: Int, label: String, value: Double, lo: Double, hi: Double) {
    canvas.text(6, y, label, inkC, bold: true)
    let v = value > 0 ? (value - lo) / (hi - lo) : 0
    canvas.text(10, y, asciiBar(v, width: 46), bodyC)
    canvas.text(57, y, value > 0 ? String(format: "%5.0f hz", value) : "    -   ", value > 0 ? inkC : dimC)
}

func drawTalk(_ canvas: Canvas, _ state: LiveState, _ elapsedTime: Double) {
    canvas.text(6, 10, "▸ SPEAKING", inkC, bold: true)
    drawCaption(canvas, state, elapsedTime, y: 11)
    let on = elapsedTime - state.lastPlay < 0.08
    meter(canvas, y: 14, label: "F0", value: on ? state.f0 : 0, lo: 60, hi: 260)
    meter(canvas, y: 15, label: "F1", value: on ? state.f1 : 0, lo: 150, hi: 1000)
    meter(canvas, y: 16, label: "F2", value: on ? state.f2 : 0, lo: 600, hi: 2800)
    // The two formants as peaks on a log frequency strip.
    for x in 3...76 {
        let fx = 100 * pow(40, Double(x - 3) / 73)
        var v = 0.0
        if on {
            for (f, a) in [(state.f1, 1.0), (state.f2, 0.8)] where f > 0 { v += a * exp(-pow(log(fx / f) / 0.12, 2)) }
            v *= state.level
        }
        let c = shade(min(1, v))
        canvas.put(x, 18, c == " " ? "." : c, c == " " ? faintC : inkC)
        canvas.put(x, 19, "-", faintC)
    }
    canvas.text(3, 20, "100", dimC); canvas.text(xForHz(1000) - 1, 20, "1k", dimC); canvas.text(74, 20, "4k", dimC)
    canvas.text(25, 20, "two tones, one motor, no speaker", midC)
}
