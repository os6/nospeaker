import Foundation
import Darwin

var renderRunning = false
/// The scroller position: one character per step, stepped by the frame clock so every step is even.
var marquee = 0
var lastMutePoll = -9.0
func startRenderer() {
    renderRunning = true
    let th = Thread {
        let canvas = Canvas()
        var lastSize = (w: 0, h: 0)
        var frameCount = 0
        var next = now()
        while renderRunning {
            let elapsedTime = now()
            frameCount += 1
            let state = snapshotLiveState()
            // Screen memory: piano roll and touch trail.
            remember(state, elapsedTime)
            if elapsedTime - lastMutePoll > 0.5 { lastMutePoll = elapsedTime; let m = speakersMuted(); updateLiveState { $0.muted = m } }
            let size = terminalSize()
            var prefix = ""
            if size != lastSize { prefix = fillScreen(); lastSize = size; canvas.shown = nil }
            drawScreen(canvas, state, elapsedTime)
            let frame = prefix + canvas.changes(originX: max(0, (size.w - 80) / 2), originY: max(0, (size.h - 24) / 2))
            if !frame.isEmpty { out(frame) }
            // A steady frame clock: 24 fps while playing (the scroller steps every other frame, 12 chars/state),
            // 8 fps while waiting on the credits (one step a frame).
            let period = state.waitingForKey ? 0.125 : 1.0 / 24
            if state.waitingForKey || frameCount % 2 == 0 { marquee += 1 }
            next += period
            let wait = next - now()
            if wait > 0 { usleep(useconds_t(wait * 1e6)) } else { next = now() }
        }
    }
    th.qualityOfService = .userInitiated
    th.start()
}
func stopRenderer() { renderRunning = false; usleep(60_000) }
