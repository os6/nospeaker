import Foundation
import Darwin

func drawSing(_ canvas: Canvas, _ state: LiveState, _ elapsedTime: Double) {
    for (i, n) in rollNotes.enumerated() {
        let y = 10 + i
        canvas.text(2, y, n, state.noteRow == i ? inkC : dimC, bold: state.noteRow == i)
        for x in 6..<68 { canvas.put(x, y, "·", faintC) }
    }
    for (k, row) in rollHistory.enumerated() where row >= 0 {
        let isNow = k == rollHistory.count - 1
        canvas.put(6 + k, 10 + row, isNow ? "o" : "=", isNow ? inkC : shimmer(k / 3), bold: true)
    }
    canvas.text(70, 11, "»", inkC, bold: true)
    canvas.text(72, 11, state.noteRow >= 0 ? state.noteName : "", inkC, bold: true)
    if state.noteRow >= 0 { canvas.text(70, 12, String(format: "%4.0fhz", state.hz), midC) }
    canvas.centered(17, "an original hook in the motor'state loudest, cleanest octave", bodyC)
    canvas.centered(18, "scoops · glides · vibrato", dimC)
}

func drawBeat(_ canvas: Canvas, _ state: LiveState, _ elapsedTime: Double) {
    let pads: [(String, Double)] = [("KICK", state.kick), ("SNARE", state.snare), ("HAT", state.hat)]
    let rapping = state.scene == .rap
    let top = 10, height = 3
    for (i, p) in pads.enumerated() {
        let x0 = 4 + i * 25, w = 22
        let hot = elapsedTime - p.1 < 0.13
        for y in top..<(top + height) {
            for x in x0..<(x0 + w) {
                let edgeY = y == top || y == top + height - 1, edgeX = x == x0 || x == x0 + w - 1
                let ch: Character = edgeY && edgeX ? "+" : edgeY ? "-" : edgeX ? "|" : " "
                canvas.put(x, y, ch, hot ? paperC : ruleC, bg: hot ? inkC : paperC)
            }
        }
        canvas.text(x0 + (w - p.0.count) / 2, top + 1, p.0, hot ? paperC : bodyC, bg: hot ? inkC : paperC, bold: true)
    }
    // Step sequencer.
    let lanes = [("K", "X.........X..x.."), ("S", "....X.......X..."), ("H", "x.x.x.x.x.x.xxx.")]
    let ly = 14
    for (j, lane) in lanes.enumerated() {
        canvas.text(8, ly + j, lane.0, inkC, bold: true)
        for (i, ch) in lane.1.enumerated() {
            let x = 11 + i * 4
            let isStep = i == state.step
            let filled = ch != "."
            canvas.text(x - 1, ly + j, filled ? " x " : " . ", isStep ? paperC : filled ? inkC : dimC, bg: isStep ? (filled ? inkC : midC) : paperC, bold: filled)
        }
    }
    if rapping {
        drawCaption(canvas, state, elapsedTime, y: 18)
    } else {
        canvas.centered(19, String(format: "%.0f bpm  ·  bar %d/%d  ·  kick, snare, hats and bass from one motor", state.bpm, state.bar + 1, state.bars), midC)
    }
}

func drawYourTurn(_ canvas: Canvas, _ state: LiveState, _ elapsedTime: Double) {
    canvas.centered(11, "Y O U R   T U R N", inkC, bold: true)
    drawCaption(canvas, state, elapsedTime, y: 14)
    canvas.centered(18, "in a moment you'll play it with your finger", midC)
}
