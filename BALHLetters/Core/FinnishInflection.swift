import Foundation

/// Lightweight, offline Finnish form recogniser.
///
/// The bundled Kotus list only has base forms (KALA, TALO), so a played word such as
/// KALAT, TALOSSA, KADULLA or PUHUN would otherwise be rejected. This strips common
/// endings in layers (clitic → possessive → case → plural/past marker), repairs the
/// stem (vowel changes, -inen words, reverse consonant gradation) and accepts the word
/// when a base form exists in the word list. It is a heuristic, not a full analyser:
/// rare stem types still need the "accept anyway" house rule.
enum FinnishInflection {
    private static let clitics = ["kaan", "kään", "kin", "han", "hän", "ko", "kö", "pa", "pä"]
    private static let possessives = ["mme", "nne", "nsa", "nsä", "ni", "si"]
    private static let cases = [
        "ssa", "ssä", "sta", "stä", "lla", "llä", "lta", "ltä", "lle", "ksi", "tta", "ttä",
        "ine", "den", "tten", "en", "na", "nä", "ta", "tä", "a", "ä", "n", "t",
        // verb endings: present/past persons, infinitive marks, passive
        "mme", "tte", "vat", "vät", "taan", "tään", "daan", "dään", "ttiin",
    ]
    private static let vowels = Set("aeiouyäö")

    /// Returns the base form found in `words`, or nil.
    /// The least-stripped stem wins, and within a stem the smallest repair wins
    /// (KADULLA → katu, not the verb katua).
    static func base(of word: String, in words: Set<String>) -> String? {
        guard word.count >= 3 else { return nil }
        let ordered = stems(of: word).sorted { $0.count != $1.count ? $0.count > $1.count : $0 < $1 }
        for stem in ordered {
            for candidate in repairs(of: stem) where candidate != word && candidate.count >= 2 && words.contains(candidate) {
                // Vowel harmony: KOVÄ is not a form of KOVA. Compounds keep their own mix.
                if mixesHarmony(word) && !mixesHarmony(candidate) { continue }
                return candidate
            }
        }
        return nil
    }

    private static func mixesHarmony(_ word: String) -> Bool {
        word.contains(where: { "aou".contains($0) }) && word.contains(where: { "äöy".contains($0) })
    }

    /// Every stem reachable by stripping up to one suffix from each layer.
    static func stems(of word: String) -> Set<String> {
        var result: Set<String> = [word]
        var layer: Set<String> = [word]
        for suffixes in [clitics, possessives] {
            layer = layer.union(layer.flatMap { strip($0, suffixes) })
        }
        // Case endings, including illative (talo-on, talo-ihin, maa-han, huonee-seen).
        var cased = layer
        for form in layer {
            cased.formUnion(strip(form, cases))
            cased.formUnion(illative(form))
        }
        // Plural / past-tense marker i or j (taloissa → taloi → talo, puhui → puhu).
        var plural = cased
        for form in cased where form.count > 2 {
            if form.hasSuffix("i") || form.hasSuffix("j") { plural.insert(String(form.dropLast())) }
        }
        // Long final vowel: puhuu → puhu, huonee → huone.
        for form in plural where form.count > 2 {
            let chars = Array(form)
            if chars[chars.count - 1] == chars[chars.count - 2], vowels.contains(chars[chars.count - 1]) {
                result.insert(String(chars.dropLast()))
            }
        }
        // Finnish endings attach to vowel stems, so a stem like AIK (from "AIKN") is not a form.
        // The unstripped word itself is never a stem (nominatives are already in the list).
        return result.union(plural).filter { $0.count >= 2 && $0 != word && $0.last.map(vowels.contains) == true }
    }

    private static func strip(_ word: String, _ suffixes: [String]) -> [String] {
        suffixes.compactMap { suffix in
            word.hasSuffix(suffix) && word.count - suffix.count >= 2 ? String(word.dropLast(suffix.count)) : nil
        }
    }

    private static func illative(_ word: String) -> [String] {
        let chars = Array(word)
        guard chars.count >= 4, chars.last == "n" else { return [] }
        var out: [String] = []
        let v = chars[chars.count - 2]
        // talo-on, kala-an: doubled vowel + n
        if vowels.contains(v), chars[chars.count - 3] == v { out.append(String(chars.dropLast(2))) }
        // maa-han, talo-ihin, työ-hön: h + vowel + n
        if vowels.contains(v), chars[chars.count - 3] == "h" { out.append(String(chars.dropLast(3))) }
        // huonee-seen, vapaa-seen, plural -siin
        if word.hasSuffix("seen") || word.hasSuffix("siin") { out.append(String(word.dropLast(4))) }
        return out.filter { $0.count >= 2 }
    }

    /// Candidate base forms for a stripped stem, most likely first.
    static func repairs(of stem: String) -> [String] {
        var changed: [String] = [stem]
        let head = String(stem.dropLast())
        switch stem.last {
        case "e": changed.append(head + "i")          // kive → kivi, tuole → tuoli
        case "o": changed.append(head + "a")          // kalo(i) → kala
        case "ö": changed.append(head + "ä")
        default: break
        }
        if stem.hasSuffix("ise") { changed.append(String(stem.dropLast(3)) + "inen") }   // punaise → punainen
        if stem.hasSuffix("kse") { changed.append(String(stem.dropLast(3)) + "s") }      // vastaukse → vastaus
        if stem.hasSuffix("de") { changed.append(String(stem.dropLast(2)) + "si") }      // vede → vesi
        // Lost infinitive ending: puhu → puhua, laula → laulaa.
        let extended = ["a", "ä", "da", "dä", "ta", "tä"].map { stem + $0 }
        var out: [String] = []
        for group in [changed, extended] {
            out += group
            out += group.flatMap(strengthen)              // kadu → katu, kuka → kukka, luva → lupa
        }
        return out
    }

    private static let gradation: [(weak: String, strong: String)] = [
        ("mm", "mp"), ("nn", "nt"), ("ll", "lt"), ("rr", "rt"), ("ng", "nk"),
        ("d", "t"), ("v", "p"), ("t", "tt"), ("p", "pp"), ("k", "kk"),
    ]

    /// Applies strong grade to the last consonant cluster (only one change per word).
    private static func strengthen(_ word: String) -> [String] {
        let chars = Array(word)
        // Find the consonant cluster just before the final vowel run.
        var end = chars.count
        while end > 0, vowels.contains(chars[end - 1]) { end -= 1 }
        guard end > 0, end < chars.count else { return [] }
        var start = end
        while start > 0, !vowels.contains(chars[start - 1]) { start -= 1 }
        let head = String(chars[..<start]), cluster = String(chars[start..<end]), tail = String(chars[end...])
        var out: [String] = []
        for (weak, strong) in gradation where cluster.hasSuffix(weak) {
            out.append(head + String(cluster.dropLast(weak.count)) + strong + tail)
        }
        return out
    }
}
