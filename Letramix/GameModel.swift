import Foundation
import Combine
import AudioToolbox
import UIKit
import SwiftUI

/// App-side wrapper around `Game`: timer, word lists, saving, sounds and haptics.
@MainActor final class GameModel: ObservableObject {
    enum Screen { case welcome, setup, play, results, history }

    @Published var screen: Screen = .welcome
    @Published var language: String { didSet { UserDefaults.standard.set(language, forKey: "language"); rules.language = language } }
    @Published var rules = GameRules()
    @Published var playerCount = 2
    @Published var names = Array(repeating: "", count: 6)
    @Published private(set) var game: Game?
    @Published private(set) var history: [Game] = []
    @Published private(set) var dictionaryReady = false
    @Published private(set) var dictionaryError = false
    /// Last word saved, for the "+5 KALA" toast.
    @Published var toast: PlayedWord?

    private var lexicons: [String: Lexicon] = [:]
    private var deadline: Date?
    private let store = GameStore()
    private let haptic = UINotificationFeedbackGenerator()
    private let tap = UIImpactFeedbackGenerator(style: .light)

    init() {
        let saved = UserDefaults.standard.string(forKey: "language")
        language = saved ?? (Locale.preferredLanguages.first?.hasPrefix("fi") == false ? "en" : "fi")
        rules.language = language
        if let data = UserDefaults.standard.data(forKey: "rules"), let stored = try? JSONDecoder().decode(GameRules.self, from: data) {
            rules = stored; rules.language = language
        }
        if let stored = UserDefaults.standard.stringArray(forKey: "names"), stored.count == 6 { names = stored }
        let count = UserDefaults.standard.integer(forKey: "playerCount"); if (1...6).contains(count) { playerCount = count }

        history = store.loadHistory()
        if var restored = store.loadCurrent(), restored.phase != .finished {
            if restored.phase == .running { restored.phase = .paused }   // app was closed mid-turn
            game = restored
        }
        Task.detached(priority: .userInitiated) {
            var loaded: [String: Lexicon] = [:]
            for code in ["fi", "en"] {
                if let url = Bundle.main.url(forResource: code, withExtension: "txt"),
                   let text = try? String(contentsOf: url, encoding: .utf8) {
                    loaded[code] = Lexicon(language: code, text: text)
                }
            }
            await self.install(loaded)
        }
    }

    private func install(_ loaded: [String: Lexicon]) {
        lexicons = loaded
        dictionaryReady = loaded.count == 2
        dictionaryError = !dictionaryReady
    }

    // MARK: Text

    func text(_ fi: String, _ en: String) -> String { language == "fi" ? fi : en }
    var lexicon: Lexicon? { lexicons[game?.rules.language ?? language] }
    var hasUnfinishedGame: Bool { game.map { $0.phase != .finished } ?? false }

    // MARK: Game lifecycle

    func newGame() {
        let players = (0..<playerCount).map { i -> String in
            let name = names[i].trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? text("Pelaaja", "Player") + " \(i + 1)" : name
        }
        UserDefaults.standard.set(names, forKey: "names")
        UserDefaults.standard.set(playerCount, forKey: "playerCount")
        if let data = try? JSONEncoder().encode(rules) { UserDefaults.standard.set(data, forKey: "rules") }
        archiveIfNeeded()
        deadline = nil
        update(Game(rules: rules, names: players))
        screen = .play
    }

    func resume() {
        guard let game else { return }
        language = game.rules.language
        screen = game.phase == .finished ? .results : .play
    }

    func rematch() {
        guard let game else { return }
        rules = game.rules
        playerCount = game.players.count
        for (i, p) in game.players.enumerated() { names[i] = p.name }
        newGame()
    }

    /// Ends the game now (scores so far count) and shows results.
    func endGame() {
        pause()
        mutate { $0.endTurn(); $0.finish() }   // words saved this turn still count
        archiveIfNeeded()
        screen = .results
    }

    func leaveToHome() { pause(); screen = .welcome }

    private func archiveIfNeeded() {
        guard let game, game.phase == .finished, !history.contains(where: { $0.id == game.id }) else { return }
        guard !game.turns.isEmpty else { return }
        history.insert(game, at: 0)
        store.saveHistory(history)
    }

    func deleteHistory(at offsets: IndexSet) { history.remove(atOffsets: offsets); store.saveHistory(history) }
    func clearHistory() { history = []; store.saveHistory([]) }

    // MARK: Timer

    var remaining: Int { game?.remaining ?? 0 }
    var phase: TurnPhase { game?.phase ?? .ready }

    func toggle() { phase == .running ? pause() : start() }

    func start() {
        guard let game, game.phase == .ready || game.phase == .paused, game.remaining > 0 else { return }
        deadline = Date().addingTimeInterval(Double(game.remaining))
        mutate { $0.start() }
        tap.impactOccurred()
    }

    func pause() {
        guard phase == .running else { return }
        if let deadline { let left = max(0, Int(ceil(deadline.timeIntervalSinceNow))); mutate { $0.remaining = left } }
        deadline = nil
        mutate { $0.pause() }
    }

    /// Player is done before the time is up.
    func finishTurnEarly() {
        pause()
        mutate { $0.endTurn() }
    }

    func tick() {
        guard phase == .running, let deadline else { return }
        let left = max(0, Int(ceil(deadline.timeIntervalSinceNow)))
        guard left != remaining else { return }
        mutate { $0.remaining = left }
        if left == 0 {
            self.deadline = nil
            mutate { $0.endTurn() }
            AudioServicesPlaySystemSound(1005)
            haptic.notificationOccurred(.warning)
        } else if left <= 5 {
            AudioServicesPlaySystemSound(1103)
        }
    }

    func confirmTurn() {
        mutate { $0.confirmTurn() }
        if phase == .finished { archiveIfNeeded(); screen = .results; haptic.notificationOccurred(.success) }
    }

    // MARK: Words

    func check(_ tiles: String) -> WordCheck? {
        guard let game, let lexicon else { return nil }
        return game.check(tiles, lexicon: lexicon)
    }

    /// Manual entry (also used for joker choices and house words).
    @discardableResult
    func add(_ tiles: String, chosen: String? = nil, house: Bool = false) -> CollectResult? {
        guard let lexicon else { return nil }
        tick()
        var result: CollectResult?
        mutate { result = $0.collect(tiles, chosen: chosen, house: house, lexicon: lexicon) }
        if case .saved(let word) = result { celebrate(word) }
        return result
    }

    /// Camera words are saved only when they are certain: in the word list and unambiguous.
    func autoCollect(_ tiles: String) {
        guard let game, game.rules.autoCollect, game.phase == .running, let lexicon else { return }
        guard case .valid = game.check(tiles, lexicon: lexicon) else { return }
        var result: CollectResult?
        mutate { result = $0.collect(tiles, fromCamera: true, lexicon: lexicon) }
        if case .saved(let word) = result { celebrate(word) }
    }

    func remove(_ word: PlayedWord) { mutate { $0.remove(word.id) } }

    private func celebrate(_ word: PlayedWord) {
        toast = word
        haptic.notificationOccurred(.success)
        let id = word.id
        Task { try? await Task.sleep(nanoseconds: 1_600_000_000); if toast?.id == id { toast = nil } }
    }

    // MARK: Plumbing

    private func mutate(_ change: (inout Game) -> Void) {
        guard var copy = game else { return }
        change(&copy)
        update(copy)
    }

    private func update(_ next: Game) {
        game = next
        store.saveCurrent(next.phase == .finished ? nil : next)
    }
}
