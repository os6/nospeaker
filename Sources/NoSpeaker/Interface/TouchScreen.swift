import Foundation
import Darwin

func drawTouch(_ canvas: Canvas, _ state: LiveState, _ elapsedTime: Double) {
    let x0 = 3, y0 = 10, w = 38, h = 11
    let edge: UInt8 = state.touchDown ? inkC : dimC
    canvas.text(x0, y0, "╭" + String(repeating: "─", count: w - 2) + "╮", edge)
    for y in (y0 + 1)..<(y0 + h - 1) { canvas.put(x0, y, "│", edge); canvas.put(x0 + w - 1, y, "│", edge) }
    canvas.text(x0, y0 + h - 1, "╰" + String(repeating: "─", count: w - 2) + "╯", edge)
    let names = ["G5", "A5", "B5", "C6", "E6", "F6", "G6", "A6", "B6", "C7"]
    for (i, n) in names.enumerated() where i % 3 == 0 { canvas.text(x0 + 2 + i * 34 / names.count, y0 + h - 2, n, ruleC) }
    for (k, p) in trail.enumerated() {
        let px = x0 + 1 + Int(p.x * Double(w - 3)), py = y0 + 1 + Int((1 - p.y) * Double(h - 3))
        let isNow = k == trail.count - 1 && state.touchDown
        canvas.put(px, py, isNow ? "@" : "o", isNow ? inkC : shimmer(k), bold: true)
    }
    let rx = 45
    if state.touchMissed {
        canvas.text(rx, 12, "no touch, skipping", dimC)
    } else if !state.touchSeen {
        let blink = Int(elapsedTime * 3) % 2 == 0
        canvas.text(rx, 11, "▶ PUT A FINGER ON", blink ? inkC : midC, bold: true)
        canvas.text(rx, 12, "  THE TRACKPAD", blink ? inkC : midC, bold: true)
        canvas.text(rx, 14, "glide lightly, no need to click", midC)
        canvas.text(rx, 16, String(format: "waiting %.0fs", max(0, state.touchWaitUntil - elapsedTime)), dimC)
    } else {
        canvas.text(rx, 10, "TOUCH TO PLAY", inkC, bold: true)
        canvas.text(rx, 12, "slide left/right   pitch", bodyC)
        canvas.text(rx, 13, "move up            vibrato", bodyC)
        canvas.text(rx, 14, "glide lightly, don'elapsedTime click", dimC)
        let on = state.touchDown && elapsedTime - state.lastPlay < 0.08
        canvas.text(rx, 16, "note", dimC); canvas.text(rx + 6, 16, on ? state.noteName : "-", inkC, bold: true)
        canvas.text(rx + 12, 16, on ? String(format: "%4.0f hz", state.hz) : "", midC)
        canvas.text(rx, 17, asciiBar(on ? state.level : 0, width: 22), bodyC)
        let left = max(0, state.touchEnds - elapsedTime)
        canvas.text(rx, 19, asciiBar(left / 12, width: 22), inkC)
        canvas.text(rx + 22, 19, String(format: "%2.0fs", left), dimC)
    }
}
