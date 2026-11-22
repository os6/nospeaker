import Foundation
import Darwin

func xForHz(_ f: Double) -> Int { 3 + Int(log(max(100, min(4000, f)) / 100) / log(40) * 73) }

func drawSweep(_ canvas: Canvas, _ state: LiveState, _ elapsedTime: Double) {
    let f = elapsedTime - state.lastPlay < 0.1 ? state.hz : 0
    drawSlant(canvas, f > 0 ? String(Int(f)) + " Hz" : "100 Hz", y: 10)
    // A live wave: more cycles as the pitch climbs.
    let levels: [Character] = ["_", ".", "-", "~", "^"]
    let cycles = 1 + 22 * log(max(100, f) / 100) / log(40)
    for x in 0..<76 {
        let v = f > 0 ? sin(2 * .pi * cycles * Double(x) / 76 - elapsedTime * 12) : 0
        canvas.put(2 + x, 16, f > 0 ? levels[min(4, Int((v + 1) / 2 * 4.99))] : "-", f > 0 ? shimmer(x / 3 + Int(elapsedTime * 10)) : faintC, bold: true)
    }
    // Ruler, 100 Hz to 4 kHz (log), with a marker.
    for x in 3...76 { canvas.put(x, 18, "-", faintC) }
    for (mark, name) in [(100.0, "100"), (250, "250"), (500, "500"), (1000, "1k"), (2000, "2k"), (4000, "4k")] {
        let x = xForHz(mark)
        canvas.put(x, 18, "+", dimC)
        canvas.text(max(2, x - name.count / 2), 19, name, midC)
    }
    if f > 0 { canvas.put(xForHz(f), 17, "v", inkC, bold: true) }
}
