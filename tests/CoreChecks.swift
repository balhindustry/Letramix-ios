import Foundation

// Run: swiftc BALHLetters/Core/*.swift tests/CoreChecks.swift -o /tmp/core-checks && /tmp/core-checks BALHLetters/Resources
var failures = 0
func check(_ condition: @autoclosure () -> Bool, _ label: String, line: Int = #line) {
    if !condition() { failures += 1; print("FAIL line \(line): \(label)") }
}

@main struct CoreChecks {
    static func main() {
        // Tile values
        for letter in "HUMNLOJ" { check(TileRules.points(String(letter)) == 2, "2p \(letter)") }
        for letter in "ÄVP" { check(TileRules.points(String(letter)) == 3, "3p \(letter)") }
        for letter in "GBF" { check(TileRules.points(String(letter)) == 5, "5p \(letter)") }
        check(TileRules.points("T") == 1, "T"); check(TileRules.points("Ö") == 4, "Ö"); check(TileRules.points("Å") == 7, "Å")
        check(TileRules.points("KALA") == 5, "KALA"); check(TileRules.points("K◇LA") == 4, "K◇LA")
        check(TileRules.points("◇◊♢") == 0, "jokers"); check(TileRules.points("äöå") == 14, "lower-case")

        let dir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "BALHLetters/Resources"
        func load(_ code: String) -> Lexicon {
            let text = (try? String(contentsOfFile: dir + "/\(code).txt", encoding: .utf8)) ?? ""
            return Lexicon(language: code, text: text)
        }
        let fi = load("fi"), en = load("en")
        check(fi.words.count > 90_000 && en.words.count > 70_000, "word lists loaded")

        // Finnish base and inflected forms
        for word in ["kala", "talo", "KALA", " Talo "] { check(fi.lookup(word)?.kind == .dictionary, "base \(word)") }
        let inflected = ["kalat", "kalan", "kalaa", "kalassa", "kalaan", "taloissa", "talossa", "talolle", "taloon",
                         "kadulla", "kivet", "kiven", "punaisen", "punaiset", "puhun", "puhuu", "sanoin", "laulamme",
                         "taloja", "kalojen", "talossakin", "talossani", "veden", "vastauksen", "kukan", "luvan"]
        for word in inflected { check(fi.lookup(word)?.kind == .inflected, "inflected \(word) → \(fi.lookup(word)?.base ?? "nil")") }
        check(fi.lookup("kadulla")?.base == "katu", "kadulla base \(fi.lookup("kadulla")?.base ?? "")")
        for junk in ["xqz", "kkkk", "aaaaaa", "qwerty", "zzla"] { check(fi.lookup(junk) == nil, "junk \(junk) → \(fi.lookup(junk)?.base ?? "")") }
        check(en.lookup("cats")?.kind == .dictionary, "en cats"); check(en.lookup("kalassa") == nil, "en has no fi forms")

        // Jokers
        check(fi.matches("K◇LA").contains { $0.word == "kala" }, "K◇LA → kala")
        check(fi.matches("TAL◇SSA").contains { $0.word == "talossa" }, "joker + inflection")
        check(fi.matches("◇").isEmpty, "single joker too short")

        // A full turn: save words during the minute, all of them score at the end
        var game = Game(rules: GameRules(language: "fi", turnSeconds: 60, rounds: 1), names: ["Aino", "Eero"])
        check(game.collect("kala", lexicon: fi) == .rejected(.tooShort), "no saving before start")
        game.start()
        var saved = 0
        for word in ["KALA", "TALO", "KALAT", "TALOSSA", "PUHUU", "KISSA", "KOIRA", "SANA", "VESI", "KIVI"] {
            if case .saved = game.collect(word, lexicon: fi) { saved += 1 }
        }
        check(saved == 10, "10 words saved in one turn (got \(saved))")
        check(game.collect("kala", lexicon: fi) == .rejected(.alreadyPlayed("kala")), "duplicate rejected")
        check(game.collect("xqzz", lexicon: fi) == .rejected(.notFound), "unknown rejected")
        if case .saved(let w) = game.collect("xqzz", house: true, lexicon: fi) { check(w.kind == .house, "house word") } else { check(false, "house word saved") }
        let expected = game.pending.reduce(0) { $0 + TileRules.points($1.tiles) }
        game.endTurn()
        check(game.phase == .review, "review after time-up")
        check(game.collect("ruoka", lexicon: fi) != .rejected(.tooShort), "missed word can be added in review")
        let total = game.pendingPoints
        check(total == expected + TileRules.points("RUOKA"), "points add up")
        game.confirmTurn()
        check(game.players[0].points == total && game.current == 1 && game.phase == .ready, "points awarded, next player")
        check(game.remaining == 60, "timer reset")

        // Second player: same words are gone, joker choice works
        game.start()
        check(game.collect("kala", lexicon: fi) == .rejected(.alreadyPlayed("kala")), "word used by other player")
        if case .rejected(.choose(let options)) = game.collect("K◇RA", lexicon: fi) {
            check(options.count > 1, "joker options")
            if case .saved(let w) = game.collect("K◇RA", chosen: options[0].word, lexicon: fi) {
                check(w.points == TileRules.points("K◇RA"), "joker scores 0")
            } else { check(false, "joker choice saved") }
        } else { check(false, "K◇RA ambiguous") }
        game.endTurn(); game.confirmTurn()
        check(game.phase == .finished && game.finishedAt != nil, "game ends after last round")
        check(game.standings.first?.index == 0, "winner")

        // Ending a game mid-turn keeps the words saved so far
        var early = Game(rules: GameRules(language: "fi", turnSeconds: 60, rounds: 0), names: ["A"])
        early.start(); early.collect("kala", lexicon: fi); early.pause()
        early.endTurn(); early.finish()
        check(early.players[0].points == TileRules.points("KALA") && early.phase == .finished, "end mid-turn keeps words")

        // Persistence round-trip
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("balhletters-\(UUID().uuidString)")
        let store = GameStore(directory: tmp)
        store.saveCurrent(game); store.saveHistory([game])
        check(store.loadCurrent()?.turns.count == 2, "current game restored")
        check(store.loadHistory().first?.players.map(\.points) == game.players.map(\.points), "history restored")
        store.saveCurrent(nil); check(store.loadCurrent() == nil, "current cleared")
        try? FileManager.default.removeItem(at: tmp)

        if failures > 0 { print("\(failures) check(s) failed"); exit(1) }
        print("All core checks passed")
    }
}
