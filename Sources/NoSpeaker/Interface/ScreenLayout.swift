import Foundation
import Darwin

// Screen memory owned by the render thread.
var rollHistory = [Int](repeating: -1, count: 62)
var trail: [(x: Double, y: Double)] = []
func remember(_ state: LiveState, _ elapsedTime: Double) {
    rollHistory.removeFirst(); rollHistory.append(state.scene == .sing && elapsedTime - state.lastPlay < 0.1 ? state.noteRow : -1)
    if state.scene == .touch, state.touchDown { trail.append((state.touchX, state.touchY)); if trail.count > 14 { trail.removeFirst() } }
}

func drawScreen(_ canvas: Canvas, _ state: LiveState, _ elapsedTime: Double) {
    canvas.clear()
    // "a90.com presents", framed by rules.
    let presents = "a90.com presents"
    let width = logoWidth, side = (width - presents.count - 4) / 2
    let header = String(repeating: "─", count: side) + "  " + presents + "  " + String(repeating: "─", count: width - presents.count - 4 - side)
    canvas.centered(0, header, dimC)
    canvas.text((80 - header.count) / 2 + side + 2, 0, presents, bodyC, bold: true)
    drawLogo(canvas, y: 2)
    if state.scene == .intro { drawSplash(canvas, state, elapsedTime); return }


    switch state.scene {
    case .heart: drawHeart(canvas, state, elapsedTime)
    case .sweep: drawSweep(canvas, state, elapsedTime)
    case .talk: drawTalk(canvas, state, elapsedTime)
    case .sing: drawSing(canvas, state, elapsedTime)
    case .beat, .rap: drawBeat(canvas, state, elapsedTime)
    case .yourTurn: drawYourTurn(canvas, state, elapsedTime)
    case .touch: drawTouch(canvas, state, elapsedTime)
    case .say: drawSay(canvas, state, elapsedTime)
    case .outro: drawOutro(canvas, state, elapsedTime)
    default: break
    }

    // Status bar: the part, the motor, and the proof.
    let badge = String(format: " %02d/%02d ", state.part, partCount)
    canvas.text(1, 21, badge, paperC, bg: inkC, bold: true)
    canvas.text(1 + badge.count + 1, 21, state.partName, inkC, bold: true)
    let active = elapsedTime - state.lastPlay < 0.08
    canvas.text(24, 21, "motor", dimC)
    canvas.text(30, 21, active ? String(format: "%4.0f hz", state.hz) : "idle", active ? inkC : dimC, bold: active)
    canvas.text(38, 21, asciiBar(active ? state.level : 0, width: 10), bodyC)
    canvas.text(50, 21, speechLanguage.rawValue.uppercased(), inkC, bold: true)
    if let muted = state.muted {
        let chip = muted ? " SPEAKERS MUTED " : " SPEAKERS ON · MUTE "
        let blink = !muted && Int(elapsedTime * 2.5) % 2 == 0
        canvas.text(79 - chip.count, 21, chip, blink ? inkC : paperC, bg: blink ? faintC : inkC, bold: true)
    }
    canvas.text(2, 22, "space skip · q end", faintC)
    // Scroller.
    let chars = Array(scrollText)
    for x in 0..<80 {
        let c = chars[(x + marquee) % chars.count]
        canvas.put(x, 23, c, shimmer((x + marquee) / 2), bold: true)
    }
}
