import Foundation
import Darwin

// MARK: - Notes

func frequencyForNote(_ note: String) -> Double {
    let names: [String: Int] = ["C": -9, "C#": -8, "D": -7, "D#": -6, "E": -5, "F": -4, "F#": -3, "G": -2, "G#": -1, "A": 0, "A#": 1, "B": 2]
    guard let octave = Int(String(note.last!)), let semi = names[String(note.dropLast())] else { return 440 }
    return 440 * pow(2, Double(semi + (octave - 4) * 12) / 12)
}
