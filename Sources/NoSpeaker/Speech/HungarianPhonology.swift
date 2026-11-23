import Foundation

struct HungarianPhoneme {
    let spelling: String
    let ipa: String

    var isPalatalStop: Bool { spelling == "gy" || spelling == "ty" }
    var isSibilant: Bool {
        ["sz", "s", "zs", "z", "cs", "c", "dzs", "dz"].contains(spelling)
    }
}

/// A spelling-to-phoneme *inventory*, not a complete morphological G2P engine.
/// Tünde still performs synthesis, coarticulation and phonological assimilation.
/// Crucially, Hungarian digraphs/trigraphs are not interpreted letter by letter.
enum HungarianPhonology {
    private static let multigraphIPA: [String: String] = [
        "dzs": "d͡ʒ", "cs": "t͡ʃ", "dz": "d͡z", "gy": "ɟ",
        "ly": "j", "ny": "ɲ", "sz": "s", "ty": "c", "zs": "ʒ"
    ]
    private static let singleLetterIPA: [String: String] = [
        "a": "ɒ", "á": "aː", "b": "b", "c": "t͡s", "d": "d",
        "e": "ɛ", "é": "eː", "f": "f", "g": "ɡ", "h": "h",
        "i": "i", "í": "iː", "j": "j", "k": "k", "l": "l",
        "m": "m", "n": "n", "o": "o", "ó": "oː", "ö": "ø",
        "ő": "øː", "p": "p", "r": "r", "s": "ʃ", "t": "t",
        "u": "u", "ú": "uː", "ü": "y", "ű": "yː",
        "v": "v", "z": "z"
    ]

    /// Multi-character letters and their long orthographic forms.
    private static let clusters: [(written: String, base: String, ipa: String)] = {
        let doubled = multigraphIPA.map { spelling, ipa in
            (written: String(spelling.prefix(1)) + spelling,
             base: spelling, ipa: ipa + "ː")
        }
        let singles = multigraphIPA.map { spelling, ipa in
            (written: spelling, base: spelling, ipa: ipa)
        }
        return (doubled + singles).sorted { $0.written.count > $1.written.count }
    }()

    static func transcribe(_ text: String) -> [HungarianPhoneme] {
        let characters = Array(text.lowercased(with: Locale(identifier: "hu_HU")))
        var result: [HungarianPhoneme] = []
        var cursor = 0

        while cursor < characters.count {
            if characters[cursor].isWhitespace {
                if result.last?.spelling != " " {
                    result.append(HungarianPhoneme(spelling: " ", ipa: " "))
                }
                cursor += 1
                continue
            }

            if let cluster = clusters.first(where: { cluster in
                let letters = Array(cluster.written)
                return cursor + letters.count <= characters.count &&
                    Array(characters[cursor..<(cursor + letters.count)]) == letters
            }) {
                result.append(HungarianPhoneme(spelling: cluster.base, ipa: cluster.ipa))
                cursor += cluster.written.count
                continue
            }

            let letter = String(characters[cursor])
            if let ipa = singleLetterIPA[letter] {
                result.append(HungarianPhoneme(spelling: letter, ipa: ipa))
            } else if characters[cursor].isLetter {
                // Proper names / loan words can require lexicon or morphology.
                result.append(HungarianPhoneme(spelling: letter, ipa: "?"))
            }
            cursor += 1
        }
        return result
    }

    static func approximateIPA(_ text: String) -> String {
        transcribe(text).map(\.ipa).joined()
    }
}
