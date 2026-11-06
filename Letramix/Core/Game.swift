import Foundation

struct GameRules: Codable, Hashable {
    var language = "fi"
    var turnSeconds = 60
    /// Number of rounds; 0 = play until the players end the game.
    var rounds = 3
    /// Camera words that are found in the word list are saved automatically.
    var autoCollect = true
    /// Players may accept a word that is not in the word list by hand.
    var allowHouseWords = true
}

/// One word saved during a turn.
struct PlayedWord: Codable, Identifiable, Hashable {
    var id = UUID()
    /// Resolved word, lower-case (what the joker stood for is filled in).
    let word: String
    /// Tiles as laid on the table, upper-case, ◇ for jokers.
    let tiles: String
    let points: Int
    let kind: WordKind
    var base: String?
    var fromCamera = false
}

struct Turn: Codable, Identifiable, Hashable {
    var id = UUID()
    let player: Int
    let round: Int
    var words: [PlayedWord]
    var points: Int { words.reduce(0) { $0 + $1.points } }
}

struct PlayerScore: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var points = 0
}

struct Standing: Identifiable, Hashable {
    let place: Int
    let index: Int
    let player: PlayerScore
    var id: UUID { player.id }
}

enum TurnPhase: String, Codable {
    /// Waiting for the player to press start.
    case ready
    case running
    case paused
    /// Time is up (or the player stopped): check the saved words, then confirm.
    case review
    /// Whole game over.
    case finished
}

enum WordCheck: Equatable {
    case tooShort
    case alreadyPlayed(String)
    case valid(LexiconMatch)
    /// The jokers can stand for several words; the player picks one.
    case choose([LexiconMatch])
    case notFound
}

enum CollectResult: Equatable {
    case saved(PlayedWord)
    case rejected(WordCheck)
}

/// All game rules in one value type: no UI, no timers, fully testable and Codable for saving.
struct Game: Codable, Identifiable {
    var id = UUID()
    var startedAt = Date()
    var finishedAt: Date?
    var rules: GameRules
    var players: [PlayerScore]
    var turns: [Turn] = []
    var current = 0
    var round = 1
    var phase: TurnPhase = .ready
    /// Words saved during the turn in progress.
    var pending: [PlayedWord] = []
    /// Seconds left in the turn in progress.
    var remaining: Int

    init(rules: GameRules, names: [String]) {
        self.rules = rules
        players = names.map { PlayerScore(name: $0) }
        remaining = rules.turnSeconds
    }

    var currentPlayer: PlayerScore? { players.indices.contains(current) ? players[current] : nil }
    var pendingPoints: Int { pending.reduce(0) { $0 + $1.points } }
    var isLastTurn: Bool { rules.rounds > 0 && round >= rules.rounds && current == players.count - 1 }

    /// Every word already scored in this game, plus the ones saved this turn.
    var playedWords: Set<String> {
        var set = Set(pending.map(\.word))
        for turn in turns { for word in turn.words { set.insert(word.word) } }
        return set
    }

    /// Whether a word can be saved right now (during the turn, or while reviewing it).
    var acceptsWords: Bool { phase == .running || phase == .review }

    func check(_ tiles: String, lexicon: Lexicon) -> WordCheck {
        let pattern = WordText.normalize(tiles)
        guard pattern.count >= 2 else { return .tooShort }
        let used = playedWords
        if !pattern.contains(jokerSymbol) {
            if used.contains(pattern) { return .alreadyPlayed(pattern) }
            return lexicon.lookup(pattern).map(WordCheck.valid) ?? .notFound
        }
        let options = lexicon.matches(pattern)
        let open = options.filter { !used.contains($0.word) }
        if open.isEmpty { return options.isEmpty ? .notFound : .alreadyPlayed(options[0].word) }
        return open.count == 1 ? .valid(open[0]) : .choose(open)
    }

    /// Saves a word to the current turn.
    /// - Parameters:
    ///   - chosen: what the jokers stand for, when `check` returned `.choose` or the word is a house word.
    ///   - house: accept even though the word is not in the word list (only if the rules allow it).
    @discardableResult
    mutating func collect(_ tiles: String, chosen: String? = nil, house: Bool = false, fromCamera: Bool = false, lexicon: Lexicon) -> CollectResult {
        guard acceptsWords else { return .rejected(.tooShort) }
        let pattern = WordText.normalize(tiles)
        var outcome = check(pattern, lexicon: lexicon)
        if let chosen {
            let word = WordText.normalize(chosen)
            if case .choose(let options) = outcome, let pick = options.first(where: { $0.word == word }) { outcome = .valid(pick) }
            else if fits(pattern: pattern, word: word), !playedWords.contains(word), let match = lexicon.lookup(word) { outcome = .valid(match) }
            else if house, rules.allowHouseWords, fits(pattern: pattern, word: word), !playedWords.contains(word) {
                outcome = .valid(LexiconMatch(word: word, kind: .house, base: nil))
            }
        } else if house, rules.allowHouseWords, outcome == .notFound, !pattern.contains(jokerSymbol) {
            outcome = .valid(LexiconMatch(word: pattern, kind: .house, base: nil))
        }
        guard case .valid(let match) = outcome else { return .rejected(outcome) }
        let word = PlayedWord(word: match.word, tiles: pattern.uppercased(), points: TileRules.points(pattern),
                              kind: match.kind, base: match.base, fromCamera: fromCamera)
        pending.append(word)
        return .saved(word)
    }

    /// The joker pattern K◇LA fits KALA but not KAL or KOLA… only where letters match.
    func fits(pattern: String, word: String) -> Bool {
        pattern.count == word.count && zip(pattern, word).allSatisfy { $0.0 == jokerSymbol || $0.0 == $0.1 }
    }

    mutating func remove(_ id: PlayedWord.ID) { pending.removeAll { $0.id == id } }

    mutating func start() { if phase == .ready || phase == .paused, remaining > 0 { phase = .running } }
    mutating func pause() { if phase == .running { phase = .paused } }

    /// Timer ran out, or the player is done early.
    mutating func endTurn() {
        guard phase == .running || phase == .paused || phase == .ready else { return }
        phase = .review
    }

    /// Confirms the reviewed words: every saved word scores, then the next player is up.
    mutating func confirmTurn() {
        guard phase == .review, players.indices.contains(current) else { return }
        let turn = Turn(player: current, round: round, words: pending)
        players[current].points += turn.points
        turns.append(turn)
        pending = []
        if isLastTurn { finish(); return }
        current += 1
        if current >= players.count { current = 0; round += 1 }
        remaining = rules.turnSeconds
        phase = .ready
    }

    mutating func finish() {
        if phase == .review, !pending.isEmpty, players.indices.contains(current) {
            // Never lose words that were saved but not yet confirmed.
            let turn = Turn(player: current, round: round, words: pending)
            players[current].points += turn.points
            turns.append(turn)
            pending = []
        }
        phase = .finished
        finishedAt = Date()
    }

    func words(of player: Int) -> [PlayedWord] { turns.filter { $0.player == player }.flatMap(\.words) }

    /// Players ranked by points; ties share a place.
    var standings: [Standing] {
        let sorted = players.enumerated().sorted { $0.element.points != $1.element.points ? $0.element.points > $1.element.points : $0.offset < $1.offset }
        var result: [Standing] = []
        for (rank, entry) in sorted.enumerated() {
            let place = rank > 0 && entry.element.points == result[rank - 1].player.points ? result[rank - 1].place : rank + 1
            result.append(Standing(place: place, index: entry.offset, player: entry.element))
        }
        return result
    }

    var bestWord: (player: Int, word: PlayedWord)? {
        turns.flatMap { turn in turn.words.map { (turn.player, $0) } }.max { $0.1.points < $1.1.points }
    }
}
