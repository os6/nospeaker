import Foundation
import Darwin

// MARK: - Look
// Every screen: "a90.com presents", the slanted ASCII NO SPEAKER logo with "trackpad" under it, the current part's
// visual, a status bar (part, motor frequency, speaker state) and a scroller. Black on off-white by default.

let inkC: UInt8 = 255, bodyC: UInt8 = 251, midC: UInt8 = 247, dimC: UInt8 = 243, ruleC: UInt8 = 240, faintC: UInt8 = 236
let paperC: UInt8 = 16

func typed(_ sourceText: String, since: Double, cps: Double, at elapsedTime: Double) -> String {
    String(sourceText.prefix(max(0, Int((elapsedTime - since) * cps))))
}
func dots(_ label: String, _ value: String, width: Int) -> String {
    label + " " + String(repeating: ".", count: max(1, width - label.count - value.count - 2)) + " "
}

// ASCII lettering: thin slanted strokes that look right at any line spacing.
let asciiLogo = [
    "    _   __ ____      _____  ____   ______ ___     __ __  ______ ____",
    "   / | / // __ \\    / ___/ / __ \\ / ____//   |   / //_/ / ____// __ \\",
    "  /  |/ // / / /    \\__ \\ / /_/ // __/  / /| |  / ,<   / __/  / /_/ /",
    " / /|  // /_/ /    ___/ // ____// /___ / ___ | / /| | / /___ / _, _/",
    "/_/ |_/ \\____/    /____//_/    /_____//_/  |_|/_/ |_|/_____//_/ |_|",
]
let logoWidth = asciiLogo.map(\.count).max() ?? 0
let slantGlyphs: [Character: [String]] = [
    "0": ["   ____ ", "  / __ \\", " / / / /", "/ /_/ / ", "\\____/  "],
    "1": ["   ___", "  <  /", "  / / ", " / /  ", "/_/   "],
    "2": ["   ___ ", "  |__ \\", "  __/ /", " / __/ ", "/____/ "],
    "3": ["   _____", "  |__  /", "   /_ < ", " ___/ / ", "/____/  "],
    "4": ["   __ __", "  / // /", " / // /_", "/__  __/", "  /_/   "],
    "5": ["    ______", "   / ____/", "  /___ \\  ", " ____/ /  ", "/_____/   "],
    "6": ["   _____", "  / ___/", " / __ \\ ", "/ /_/ / ", "\\____/  "],
    "7": [" _____", "/__  /", "  / / ", " / /  ", "/_/   "],
    "8": ["   ____ ", "  ( __ )", " / __  |", "/ /_/ / ", "\\____/  "],
    "9": ["   ____ ", "  / __ \\", " / /_/ /", " \\__, / ", "/____/  "],
    "H": ["    __  __", "   / / / /", "  / /_/ / ", " / __  /  ", "/_/ /_/   "],
    "z": ["      ", " ____ ", "/_  / ", " / /_ ", "/___/ "],
    " ": ["   ", "   ", "   ", "   ", "   "],
]
/// The lockup: NO SPEAKER, a row of air, then a rule as wide as the logo with the description on the left and
/// "trackpad" on the right:  ─  haptic voice synthesis  ───────  trackpad  ─
let logoTag = "trackpad"
let logoTagColumn = logoWidth - 3 - logoTag.count
func logoLockup() -> [String] { asciiLogo + ["", String(repeating: " ", count: logoTagColumn) + logoTag] }
func drawLogo(_ cv: Canvas, y: Int) {
    let x0 = (80 - logoWidth) / 2
    for (i, line) in asciiLogo.enumerated() { cv.text(x0, y + i, line, inkC, bold: true) }
    let row = y + asciiLogo.count + 1
    for x in x0..<(x0 + logoWidth) { cv.put(x, row, "─", dimC) }
    cv.text(x0 + 1, row, "  haptic voice synthesis  ", midC)
    cv.text(x0 + logoTagColumn - 2, row, "  " + logoTag + "  ", inkC, bold: true)
}
func drawSlant(_ cv: Canvas, _ text: String, y: Int, color: UInt8 = inkC) {
    var rows = [String](repeating: "", count: 5)
    for ch in text { let g = slantGlyphs[ch] ?? slantGlyphs[" "]!; for r in 0..<5 { rows[r] += g[r] } }
    let w = rows.map(\.count).max() ?? 0
    for (i, line) in rows.enumerated() {
        for (j, ch) in line.enumerated() where ch != " " { cv.put((80 - w) / 2 + j, y + i, ch, color, bold: true) }
    }
}
/// Classic ASCII shading, light to dense.
let ramp: [Character] = [" ", ".", ":", "-", "=", "+", "*", "#", "%", "@"]
func shade(_ v: Double) -> Character { ramp[max(0, min(ramp.count - 1, Int(v * Double(ramp.count - 1) + 0.5)))] }
/// "[=======>        ]" style bar, inside the given width (brackets included).
func asciiBar(_ v: Double, width: Int) -> String {
    let inner = width - 2, fill = Int(max(0, min(1, v)) * Double(inner))
    return "[" + String(repeating: "=", count: max(0, fill - 1)) + (fill > 0 ? ">" : "") + String(repeating: " ", count: inner - fill) + "]"
}

/// A silver shimmer travelling along `i` (no colour).
let silver: [UInt8] = [245, 246, 247, 248, 249, 250, 251, 252, 253, 254, 255, 255, 254, 253, 252, 251, 250, 249, 248, 247, 246]
func shimmer(_ i: Int) -> UInt8 { silver[((i % silver.count) + silver.count) % silver.count] }

let scrollText = "      a90.com presents NO SPEAKER.    the trackpad has no speaker. every sound you hear is its haptic motor, driven through MultitouchSupport, a private macOS framework.    range: 100 to 4000 vibrations per second.    voice: two formants, retriggered on every pitch beat.    thanks for listening.    a90.com    "
