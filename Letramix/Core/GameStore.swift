import Foundation

/// Saves the game in progress and finished games as JSON, so nothing is lost
/// when the app is closed, killed or the phone restarts.
struct GameStore {
    let directory: URL
    var currentURL: URL { directory.appendingPathComponent("current-game.json") }
    var historyURL: URL { directory.appendingPathComponent("history.json") }
    static let historyLimit = 100

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Letramix", isDirectory: true)
        self.directory = base
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }

    private static let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }()
    private static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()

    func loadCurrent() -> Game? {
        guard let data = try? Data(contentsOf: currentURL) else { return nil }
        return try? Self.decoder.decode(Game.self, from: data)
    }

    func saveCurrent(_ game: Game?) {
        guard let game else { try? FileManager.default.removeItem(at: currentURL); return }
        if let data = try? Self.encoder.encode(game) { try? data.write(to: currentURL, options: .atomic) }
    }

    func loadHistory() -> [Game] {
        guard let data = try? Data(contentsOf: historyURL) else { return [] }
        return (try? Self.decoder.decode([Game].self, from: data)) ?? []
    }

    func saveHistory(_ games: [Game]) {
        if let data = try? Self.encoder.encode(Array(games.prefix(Self.historyLimit))) { try? data.write(to: historyURL, options: .atomic) }
    }
}
