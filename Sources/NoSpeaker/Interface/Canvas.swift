import Foundation
import Darwin

struct Cell: Equatable { var ch: Character = " "; var fg: UInt8 = 250; var bg: UInt8 = 16; var bold = false }

/// Colours are chosen as xterm 256-colour indexes but sent as exact 24-bit RGB, so a terminal's own theme
/// (light themes remap the palette) can't change them: black stays black.
var rgbTable: [String] = (0..<256).map { n -> String in
    let v: (Int, Int, Int)
    if n < 16 {
        let base = [(0, 0, 0), (128, 0, 0), (0, 128, 0), (128, 128, 0), (0, 0, 128), (128, 0, 128), (0, 128, 128), (192, 192, 192),
                    (128, 128, 128), (255, 0, 0), (0, 255, 0), (255, 255, 0), (0, 0, 255), (255, 0, 255), (0, 255, 255), (255, 255, 255)]
        v = base[n]
    } else if n >= 232 {
        let g = 8 + (n - 232) * 10
        v = (g, g, g)
    } else {
        let c = n - 16
        let f = { (x: Int) in x == 0 ? 0 : 55 + x * 40 }
        v = (f(c / 36), f((c / 6) % 6), f(c % 6))
    }
    return "\(v.0);\(v.1);\(v.2)"
}
var screenBackground = "\u{1B}[48;2;0;0;0m"
var lightTheme = false

/// Mono: black on off-white (default), or `--dark` for white on black. Greys run between the two.
func applyTheme(light: Bool) {
    lightTheme = light
    let paper = light ? (246, 245, 241) : (0, 0, 0)
    let ink = light ? (12, 12, 12) : (255, 255, 255)
    func str(_ c: (Int, Int, Int)) -> String { "\(c.0);\(c.1);\(c.2)" }
    func mix(_ u: Double) -> (Int, Int, Int) {
        (Int(Double(paper.0) + Double(ink.0 - paper.0) * u), Int(Double(paper.1) + Double(ink.1 - paper.1) * u),
         Int(Double(paper.2) + Double(ink.2 - paper.2) * u))
    }
    for n in 232...255 { rgbTable[n] = str(mix(0.05 + 0.95 * Double(n - 232) / 23)) }
    rgbTable[16] = str(paper)
    screenBackground = "\u{1B}[48;2;\(str(paper))m"
}

final class Canvas {
    let w = 80, h = 24
    var cells = [Cell](repeating: Cell(), count: 80 * 24)
    func clear() { for i in cells.indices { cells[i] = Cell() } }
    func put(_ x: Int, _ y: Int, _ ch: Character, _ fg: UInt8, bg: UInt8 = 16, bold: Bool = false) {
        guard x >= 0, y >= 0, x < w, y < h else { return }
        cells[y * w + x] = Cell(ch: ch, fg: fg, bg: bg, bold: bold)
    }
    func text(_ x: Int, _ y: Int, _ s: String, _ fg: UInt8, bg: UInt8 = 16, bold: Bool = false) {
        var i = x
        for c in s { put(i, y, c, fg, bg: bg, bold: bold); i += 1 }
    }
    func centered(_ y: Int, _ s: String, _ fg: UInt8, bold: Bool = false) { text((w - s.count) / 2, y, s, fg, bold: bold) }
    /// What the terminal is showing now, to send only the cells that changed.
    var shown: [Cell]?
    func changes(originX: Int, originY: Int) -> String {
        var s = ""
        var pen: Cell?
        var writeAt = -1
        for i in 0..<(w * h) {
            let c = cells[i]
            if let shown, shown[i] == c { continue }
            if writeAt != i { s += "\u{1B}[\(originY + i / w + 1);\(originX + i % w + 1)H" }
            if pen == nil || pen!.bold != c.bold { s += c.bold ? "\u{1B}[1m" : "\u{1B}[22m" }
            if pen == nil || pen!.fg != c.fg { s += "\u{1B}[38;2;\(rgbTable[Int(c.fg)])m" }
            if pen == nil || pen!.bg != c.bg { s += "\u{1B}[48;2;\(rgbTable[Int(c.bg)])m" }
            s.append(c.ch)
            pen = c
            writeAt = (i % w == w - 1) ? -1 : i + 1
        }
        shown = cells
        return s.isEmpty ? "" : s + "\u{1B}[0m"
    }

}
