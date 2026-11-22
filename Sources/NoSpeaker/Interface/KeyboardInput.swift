import Foundation
import Darwin

/// True when a byte is ready on stdin within `ms` milliseconds.
func waitForInput(ms: Int) -> Bool {
    var fds = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
    return poll(&fds, 1, Int32(ms)) > 0
}

func startKeys() {
    let th = Thread {
        var c: UInt8 = 0
        var utf8Buffer: [UInt8] = []
        while !stopRequested {
            guard read(STDIN_FILENO, &c, 1) == 1 else { usleep(10_000); continue }
            // Typing a line for it to say: every key is text, except return, backspace, tab and esc.
            if snapshotLiveState().inputActive {
                if c == 27 {
                    if waitForInput(ms: 30) {   // a sequence (scroll, arrow): drop it
                        var b: UInt8 = 0, first = true
                        while waitForInput(ms: 30), read(STDIN_FILENO, &b, 1) == 1 {
                            if first { first = false; if b == UInt8(ascii: "[") || b == UInt8(ascii: "O") { continue } }
                            if (0x40...0x7E).contains(b) { break }
                        }
                    } else {
                        updateLiveState { $0.inputDone = true }
                    }
                } else if c == 13 || c == 10 {
                    updateLiveState { $0.inputSubmitted = true }
                } else if c == 9 {
                    let suggestion = saySuggestion(at: now())
                    updateLiveState { if $0.inputText.isEmpty { $0.inputText = suggestion } }
                } else if c == 127 || c == 8 {
                    updateLiveState { if !$0.inputText.isEmpty { $0.inputText.removeLast() } }
                } else if (32...126).contains(c) {
                    utf8Buffer.removeAll()
                    let ch = Character(UnicodeScalar(c))
                    updateLiveState { if $0.inputText.count < 70 { $0.inputText.append(ch) } }
                } else if (0xC2...0xF4).contains(c) {
                    utf8Buffer = [c]
                } else if (0x80...0xBF).contains(c), !utf8Buffer.isEmpty {
                    utf8Buffer.append(c)
                    if let scalar = String(bytes: utf8Buffer, encoding: .utf8) {
                        updateLiveState { if $0.inputText.count < 70 { $0.inputText.append(contentsOf: scalar) } }
                        utf8Buffer.removeAll()
                    } else if utf8Buffer.count >= 4 {
                        utf8Buffer.removeAll()
                    }
                }
                continue
            }
            if c == 27 {
                // Esc alone quits; Esc followed quickly by "[" or "O" is a sequence (a scroll, a click, an
                // arrow key): read it to its end and ignore it.
                guard waitForInput(ms: 30) else { requestEnd(); continue }
                var next: UInt8 = 0
                guard read(STDIN_FILENO, &next, 1) == 1 else { continue }
                if next == UInt8(ascii: "[") || next == UInt8(ascii: "O") {
                    var b: UInt8 = 0
                    while waitForInput(ms: 30), read(STDIN_FILENO, &b, 1) == 1 { if (0x40...0x7E).contains(b) { break } }
                }
                continue
            }
            // On the credits, F opens the X profile and stays put; any other key exits.
            if c == UInt8(ascii: "f") || c == UInt8(ascii: "F"), snapshotLiveState().waitingForKey {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                p.arguments = ["https://x.com/codycollier"]
                try? p.run()
                let at = now()
                updateLiveState { $0.followOpenedAt = at }
                continue
            }
            keyPressed = true
            if c == UInt8(ascii: "q") || c == UInt8(ascii: "Q") { requestEnd() }
            if c == UInt8(ascii: " ") || c == UInt8(ascii: "s") { skipRequested = true }
        }
    }
    th.start()
}
