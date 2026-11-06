import Foundation

/// The joker tile. Stands for exactly one letter and is always worth 0 points.
let jokerSymbol: Character = "◇"

/// How a played word was accepted.
enum WordKind: String, Codable, Hashable, Sendable {
    /// Found as-is in the bundled word list.
    case dictionary
    /// A Finnish inflected form whose base form is in the word list (e.g. TALOSSA → talo).
    case inflected
    /// Not in the word list, but the players accepted it by hand (house rule).
    case house
}

struct LexiconMatch: Hashable, Sendable {
    let word: String
    let kind: WordKind
    /// Base form for inflected matches.
    let base: String?
}

/// Normalises any text the same way everywhere: trimmed, NFC, lower-case, joker variants unified.
enum WordText {
    static func normalize(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
            .lowercased()
        for variant in ["◊", "♢", "*", "?"] { text = text.replacingOccurrences(of: variant, with: String(jokerSymbol)) }
        return text.filter { $0.isLetter || $0 == jokerSymbol }
    }

    static func display(_ raw: String) -> String { normalize(raw).uppercased() }
}

/// A bundled word list plus the lookup rules for one language.
struct Lexicon: Sendable {
    let language: String
    let words: Set<String>
    let alphabet: [Character]

    init(language: String, words: Set<String>) {
        self.language = language
        self.words = words
        let base = Array("abcdefghijklmnopqrstuvwxyz")
        alphabet = language == "fi" ? base + Array("åäö") : base
    }

    init(language: String, text: String) {
        var set = Set<String>()
        set.reserveCapacity(110_000)
        for line in text.split(whereSeparator: \.isNewline) {
            let word = WordText.normalize(String(line))
            if word.count >= 2 { set.insert(word) }
        }
        self.init(language: language, words: set)
    }

    /// Looks up a word with no jokers. Finnish also accepts common inflected forms.
    func lookup(_ raw: String) -> LexiconMatch? {
        let word = WordText.normalize(raw)
        guard word.count >= 2, !word.contains(jokerSymbol) else { return nil }
        if words.contains(word) { return LexiconMatch(word: word, kind: .dictionary, base: nil) }
        if language == "fi", let base = FinnishInflection.base(of: word, in: words) {
            return LexiconMatch(word: word, kind: .inflected, base: base)
        }
        return nil
    }

    func contains(_ raw: String) -> Bool { lookup(raw) != nil }

    /// All real words a pattern can stand for. Each ◇ is exactly one letter.
    func matches(_ raw: String, limit: Int = 60) -> [LexiconMatch] {
        let pattern = WordText.normalize(raw)
        guard pattern.count >= 2 else { return [] }
        let jokers = pattern.filter { $0 == jokerSymbol }.count
        if jokers == 0 { return lookup(pattern).map { [$0] } ?? [] }
        var results: [LexiconMatch] = []
        if jokers <= 2 {
            // Expand jokers letter by letter: at most 29² lookups, and inflected forms work too.
            var seen = Set<String>()
            func expand(_ chars: [Character], from index: Int) {
                guard results.count < limit else { return }
                guard let next = chars[index...].firstIndex(of: jokerSymbol) else {
                    let word = String(chars)
                    if seen.insert(word).inserted, let match = lookup(word) { results.append(match) }
                    return
                }
                var copy = chars
                for letter in alphabet {
                    copy[next] = letter
                    expand(copy, from: next + 1)
                }
            }
            expand(Array(pattern), from: 0)
        } else {
            let letters = Array(pattern)
            for word in words where word.count == letters.count {
                if zip(letters, word).allSatisfy({ $0.0 == jokerSymbol || $0.0 == $0.1 }) {
                    results.append(LexiconMatch(word: word, kind: .dictionary, base: nil))
                    if results.count >= limit { break }
                }
            }
        }
        // Dictionary words first, then alphabetical.
        return results.sorted { ($0.kind == .dictionary ? 0 : 1, $0.word) < ($1.kind == .dictionary ? 0 : 1, $1.word) }
    }
}
