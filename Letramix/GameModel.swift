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
    private var deadline: Date?
    init() {
        Task.detached {
            var lists: [String: Set<String>] = [:]
            for code in ["fi", "en"] {
                if let url = Bundle.main.url(forResource: code, withExtension: "txt"), let text = try? String(contentsOf: url, encoding: .utf8) {
                    lists[code] = Set(text.split(separator: "\n").map(String.init))
                }
            }
            await self.load(lists)
        }
    }
    private func load(_ lists: [String: Set<String>]) { dictionaries = lists; dictionaryReady = lists.count == 2; dictionaryError = !dictionaryReady }
    func text(_ fi: String, _ en: String) -> String { language == "fi" ? fi : en }
    func normalized(_ word: String) -> String { word.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping.lowercased() }
    func valid(_ word: String) -> Bool {
        let word = normalized(word)
        return word.count >= 2 && word.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzåäö").contains($0) } && dictionaries[language]?.contains(word) == true
    }
    func canScore(_ word: String) -> Bool { running && remaining > 0 && valid(word) && !used.contains(normalized(word)) }
    func score(_ word: String) { guard canScore(word), players.indices.contains(current) else { return }; let w = normalized(word); players[current].points += w.count; used.insert(w) }
    func begin() {
        players = (0..<playerCount).map { Player(name: names[$0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? text("Pelaaja", "Player") + " \($0+1)" : names[$0]) }
        current = 0; used = []; remaining = duration; running = false; deadline = nil; screen = .game
    }
    func toggle() { guard remaining > 0 else { return }; if running { pause() } else { deadline = Date().addingTimeInterval(Double(remaining)); running = true } }
    func pause() { if let deadline, running { remaining = max(0, Int(ceil(deadline.timeIntervalSinceNow))) }; running = false; deadline = nil }
    func tick() { guard running, let deadline else { return }; remaining = max(0, Int(ceil(deadline.timeIntervalSinceNow))); if remaining == 0 { running = false; self.deadline = nil; AudioServicesPlaySystemSound(1005) } }
    func next() { guard !players.isEmpty else { return }; pause(); current = (current+1) % players.count; remaining = duration }
}
