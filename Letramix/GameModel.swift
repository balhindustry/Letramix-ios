import Foundation
import Combine
import AudioToolbox

struct Player: Identifiable { let id = UUID(); var name: String; var points = 0 }
@MainActor final class GameModel: ObservableObject {
    enum Screen { case welcome, settings, game }
    @Published var screen: Screen = .welcome
    @Published var language = "fi"
    @Published var playerCount = 2
    @Published var names = Array(repeating: "", count: 6)
    @Published var duration = 60
    @Published var players: [Player] = []
    @Published var current = 0
    @Published var remaining = 60
    @Published var running = false
    @Published var dictionaryReady = false
    @Published var dictionaryError = false
    @Published var used = Set<String>()
    private var dictionaries: [String: Set<String>] = [:]
    private var matchCache: [String: [String]] = [:]
    private var deadline: Date?
    init() {
        Task.detached {
            var lists: [String: Set<String>] = [:]
            for code in ["fi", "en"] {
                if let url = Bundle.main.url(forResource: code, withExtension: "txt"), let text = try? String(contentsOf: url, encoding: .utf8) {
                    lists[code] = Set(text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping.lowercased() })
                }
            }
            await self.load(lists)
        }
    }
    private func load(_ lists: [String: Set<String>]) { dictionaries = lists; dictionaryReady = lists.count == 2; dictionaryError = !dictionaryReady }
    func text(_ fi: String, _ en: String) -> String { language == "fi" ? fi : en }
    func normalized(_ word: String) -> String { word.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping.lowercased() }
    // A diamond represents exactly one letter, and always contributes zero points.
    func matches(_ pattern: String) -> [String] {
        let pattern = normalized(pattern)
        guard pattern.count >= 2 else { return [] }
        if !pattern.contains("◇") { return dictionaries[language]?.contains(pattern) == true ? [pattern] : [] }
        let key = language + ":" + pattern
        if let cached = matchCache[key] { return cached }
        let letters = Array(pattern)
        let result = (dictionaries[language] ?? []).filter { word in
            let candidate = Array(word)
            return candidate.count == letters.count && zip(letters, candidate).allSatisfy { $0.0 == "◇" || $0.0 == $0.1 }
        }.sorted()
        if matchCache.count > 200 { matchCache.removeAll() }
        matchCache[key] = result
        return result
    }
    func resolved(_ pattern: String) -> String? {
        let options = matches(pattern)
        return options.count == 1 ? options[0] : nil
    }
    func valid(_ word: String) -> Bool { !matches(word).isEmpty }
    func points(_ word: String) -> Int { TileRules.points(word) }
    func canScore(_ word: String) -> Bool {
        guard running, remaining > 0, let resolved = resolved(word) else { return false }
        return !used.contains(resolved)
    }
    func score(_ word: String) {
        tick()
        guard canScore(word), players.indices.contains(current), let resolved = resolved(word) else { return }
        players[current].points += points(word)
        used.insert(resolved)
    }
    func canScore(_ word: String, pattern: String) -> Bool {
        if pattern.isEmpty { return canScore(word) }
        return running && remaining > 0 && matches(pattern).contains(normalized(word)) && !used.contains(normalized(word))
    }
    func score(_ word: String, pattern: String) {
        if pattern.isEmpty { score(word); return }
        tick()
        guard canScore(word, pattern: pattern), players.indices.contains(current) else { return }
        players[current].points += points(pattern)
        used.insert(normalized(word))
    }
    func begin() {
        players = (0..<playerCount).map { Player(name: names[$0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? text("Pelaaja", "Player") + " \($0+1)" : names[$0]) }
        current = 0; used = []; remaining = duration; running = false; deadline = nil; screen = .game
    }
    func toggle() { guard remaining > 0 else { return }; if running { pause() } else { deadline = Date().addingTimeInterval(Double(remaining)); running = true } }
    func pause() { if let deadline, running { remaining = max(0, Int(ceil(deadline.timeIntervalSinceNow))) }; running = false; deadline = nil }
    func tick() { guard running, let deadline else { return }; remaining = max(0, Int(ceil(deadline.timeIntervalSinceNow))); if remaining == 0 { running = false; self.deadline = nil; AudioServicesPlaySystemSound(1005) } }
    func next() { guard !players.isEmpty else { return }; pause(); current = (current+1) % players.count; remaining = duration }
}
