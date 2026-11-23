import Foundation
import Darwin

// MARK: - Live state shared with the screen

enum Scene { case intro, heart, sweep, talk, sing, beat, rap, yourTurn, touch, say, outro }

struct LiveState {
    var scene: Scene = .intro
    var part = 1
    var partName = "LOADING"
    var hz = 0.0, level = 0.0, lastPlay = -9.0
    var f0 = 0.0, f1 = 0.0, f2 = 0.0
    var caption = "", captionStart = 0.0, captionDur = 1.0
    var kick = -9.0, snare = -9.0, hat = -9.0
    var step = -1, bar = 0, bars = 4, bpm = 92.0
    var noteRow = -1, noteName = ""
    var touchSeen = false, touchDown = false, touchX = 0.5, touchY = 0.5, touchEnds = 0.0, touchWaitUntil = 0.0, touchMissed = false
    var waitingForKey = false
    var followOpenedAt = -9.0
    // Say anything: what's being typed, and where it is (typing, preparing, speaking).
    var inputActive = false, inputText = "", inputSubmitted = false, inputDone = false
    var sayStatus = "typing", sayCount = 0
    var muted: Bool? = nil
    var actuations = 0
    var started = 0.0
    var stepDone = 0, stepTotal = 0
}
let liveLock = NSLock()
var liveState = LiveState()
func updateLiveState(_ update: (inout LiveState) -> Void) {
    liveLock.lock()
    defer { liveLock.unlock() }
    update(&liveState)
}
func snapshotLiveState() -> LiveState { liveLock.lock(); defer { liveLock.unlock() }; return liveState }

let partCount = 10
/// Moves the show to a new part: what the screen draws, and the part number and name in the status bar.
func enter(_ scene: Scene, _ part: Int, _ name: String) {
    skipRequested = false
    updateLiveState { $0.scene = scene; $0.part = part; $0.partName = name }
}
func caption(_ text: String, seconds: Double) { updateLiveState { $0.caption = text; $0.captionStart = now(); $0.captionDur = seconds } }
