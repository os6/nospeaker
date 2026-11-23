import Foundation
import Darwin

func drawSplash(_ canvas: Canvas, _ state: LiveState, _ elapsedTime: Double) {
    let x = 10, done = state.stepDone
    canvas.text(x, 11, "$", midC); canvas.text(x + 2, 11, typed("./nospeaker", since: state.started, cps: 30, at: elapsedTime), inkC, bold: true)
    func line(_ y: Int, _ label: String, _ value: String) {
        let d = dots(label, value, width: 56)
        canvas.text(x + 2, y, d, midC); canvas.text(x + 2 + d.count, y, value, inkC, bold: true)
    }
    if done >= 1 { line(12, "loading trackpad haptics", mt != nil ? "ok" : "missing") }
    if done >= 2 { line(13, motorBuiltIn ? "connecting to the built-in trackpad" : "connecting to the trackpad", "ready") }
    if done >= 2 {
        let total = max(1, state.stepTotal - 2), voices = max(0, min(total, done - 2))
        if voices < total {
            let width = 28, fill = Int(Double(width) * Double(voices) / Double(total))
            let barText = String(repeating: "=", count: max(0, fill - 1)) + (fill > 0 ? ">" : "") + String(repeating: " ", count: width - fill)
            canvas.text(x + 2, 14, "preparing the voice [\(barText)] \(voices)/\(total) " + ["|", "/", "-", "\\"][Int(elapsedTime * 10) % 4], bodyC)
        } else {
            line(14, "preparing the voice", "ready")
        }
    }
    drawProof(canvas, state, elapsedTime, y: 17)
    canvas.centered(19, "keep your hands off the trackpad until the end", dimC)
    let ready = state.stepTotal > 0 && done >= state.stepTotal
    canvas.centered(22, ready && state.muted != true ? "space: start    q: end" : "space: skip    q: end", dimC)
}

/// The proof, as an inverted banner: muted, or a blinking reminder to mute.
func drawProof(_ canvas: Canvas, _ state: LiveState, _ elapsedTime: Double, y: Int) {
    guard let muted = state.muted else { return }
    let text = "   " + (muted ? "SPEAKERS MUTED: SOUND COMES FROM THE TRACKPAD" : "SPEAKERS ARE ON: MUTE YOUR MAC FIRST") + "   "
    let blink = !muted && Int(elapsedTime * 2.5) % 2 == 0
    canvas.text((80 - text.count) / 2, y, text, blink ? inkC : paperC, bg: blink ? faintC : inkC, bold: true)
}

let heartArt = [",d88b.d88b,", "88888888888", "`Y8888888Y'", "  `Y888Y'", "    `Y'"]
func drawHeart(_ canvas: Canvas, _ state: LiveState, _ elapsedTime: Double) {
    let pulse = max(0, 1 - (elapsedTime - state.lastPlay) / 0.35) * state.level
    let shades: [UInt8] = [236, 238, 240, 243, 246, 249, 252, 255]
    let color = shades[min(shades.count - 1, Int(pulse * Double(shades.count - 1) + 0.5))]
    for (y, row) in heartArt.enumerated() { canvas.text(34, 11 + y, row, color, bold: pulse > 0.3) }
    canvas.centered(19, "waking up the motor", pulse > 0.3 ? inkC : dimC, bold: pulse > 0.3)
}
