import Foundation
import Darwin

// MARK: - Terminal

var savedTermios = termios()
var terminalTaken = false
/// Where the show draws. While it runs, stdout and stderr point at /dev/null, because MultitouchSupport
/// prints its own debug lines ("Recognized family…") when touch tracking starts.
var outFD = STDOUT_FILENO
var savedOut: Int32 = -1, savedErr: Int32 = -1
func silenceOthers() {
    fflush(stdout); fflush(stderr)
    savedOut = dup(STDOUT_FILENO); savedErr = dup(STDERR_FILENO)
    outFD = savedOut
    let null = open("/dev/null", O_WRONLY)
    dup2(null, STDOUT_FILENO); dup2(null, STDERR_FILENO); close(null)
}
func unsilence() {
    guard savedOut >= 0 else { return }
    fflush(stdout); fflush(stderr)
    dup2(savedOut, STDOUT_FILENO); dup2(savedErr, STDERR_FILENO)
    close(savedOut); close(savedErr)
    savedOut = -1; savedErr = -1; outFD = STDOUT_FILENO
}
func out(_ s: String) {
    let bytes = Array(s.utf8)
    let count = bytes.count
    bytes.withUnsafeBytes { buf in
        var off = 0
        while off < count {
            let n = write(outFD, buf.baseAddress! + off, count - off)
            if n <= 0 { break }
            off += n
        }
    }
}
func takeTerminal() {
    terminalTaken = true
    silenceOthers()
    tcgetattr(STDIN_FILENO, &savedTermios)
    var t = savedTermios
    t.c_lflag &= ~tcflag_t(ICANON | ECHO)
    tcsetattr(STDIN_FILENO, TCSANOW, &t)
    out("\u{1B}[?1049h\u{1B}[?25l\u{1B}[?1000h\u{1B}[?1002h\u{1B}[?1006h" + fillScreen())
}
func restoreTerminal() {
    guard terminalTaken else { return }
    terminalTaken = false
    out("\u{1B}[?1006l\u{1B}[?1002l\u{1B}[?1000l\u{1B}[0m\u{1B}[2J\u{1B}[?25h\u{1B}[?1049l")
    unsilence()
    tcsetattr(STDIN_FILENO, TCSANOW, &savedTermios)
}
/// Paints the whole terminal in the theme's background (not just the show's 80×24 block), so the show sits
/// centred on one page however big the window is.
func fillScreen() -> String {
    let size = terminalSize()
    let row = String(repeating: " ", count: size.w)
    var s = "\u{1B}[0m" + screenBackground + "\u{1B}[2J"
    for y in 0..<size.h { s += "\u{1B}[\(y + 1);1H" + row }
    return s
}

func terminalSize() -> (w: Int, h: Int) {
    var ws = winsize()
    if ioctl(outFD, TIOCGWINSZ, &ws) == 0, ws.ws_col > 0 { return (Int(ws.ws_col), Int(ws.ws_row)) }
    return (80, 24)
}
