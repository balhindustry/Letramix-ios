import SwiftUI

struct ResultsView: View {
    @EnvironmentObject var model: GameModel

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if let game = model.game {
                    Text("🏆").font(.system(size: 64))
                    if let winner = game.standings.first {
                        let tied = game.standings.filter { $0.place == 1 }.count > 1
                        Text(tied ? model.text("Tasapeli!", "It’s a tie!") : model.text("\(winner.player.name) voitti!", "\(winner.player.name) wins!"))
                            .font(.largeTitle.bold()).multilineTextAlignment(.center)
                    }
                    GameSummary(game: game)
                    Button(model.text("Uusi peli samoilla pelaajilla", "Rematch")) { model.rematch() }.buttonStyle(PrimaryButton())
                    Button(model.text("Alkuun", "Home")) { model.screen = .welcome }.font(.headline)
                } else {
                    Button(model.text("Alkuun", "Home")) { model.screen = .welcome }
                }
            }
            .padding(20)
        }
    }
}

/// Standings, best word and every player's word list. Used by results and history.
struct GameSummary: View {
    @EnvironmentObject var model: GameModel
    let game: Game

    var body: some View {
        VStack(spacing: 14) {
            Card {
                ForEach(game.standings) { entry in
                    HStack {
                        Text(medal(entry.place)).font(.title2).frame(width: 36)
                        Text(entry.player.name).font(.headline)
                        Spacer()
                        Text(model.text("\(game.words(of: entry.index).count) sanaa", "\(game.words(of: entry.index).count) words"))
                            .font(.caption).foregroundStyle(.secondary)
                        Text("\(entry.player.points)").font(.title3.bold().monospacedDigit()).frame(minWidth: 44, alignment: .trailing)
                    }
                }
            }
            if let best = game.bestWord {
                Card {
                    Text(model.text("Paras sana", "Best word")).font(.headline)
                    HStack {
                        TileWord(word: best.word.tiles, size: 28)
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text("+\(best.word.points)").font(.title3.bold()).foregroundStyle(Theme.green)
                            Text(game.players.indices.contains(best.player) ? game.players[best.player].name : "").font(.caption)
                        }
                    }
                }
            }
            ForEach(Array(game.players.enumerated()), id: \.element.id) { index, player in
                let words = game.words(of: index)
                Card {
                    DisclosureGroup {
                        if words.isEmpty { Text(model.text("Ei sanoja.", "No words.")).font(.caption).foregroundStyle(.secondary) }
                        ForEach(words) { WordRow(word: $0) }
                    } label: {
                        Text(model.text("\(player.name): \(words.count) sanaa", "\(player.name): \(words.count) words")).font(.headline)
                    }
                }
            }
        }
    }

    private func medal(_ place: Int) -> String { place == 1 ? "🥇" : place == 2 ? "🥈" : place == 3 ? "🥉" : "\(place)." }
}

struct HistoryView: View {
    @EnvironmentObject var model: GameModel
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.history) { game in
                    NavigationLink {
                        ScrollView { GameSummary(game: game).padding() }
                            .background(Theme.cream)
                            .navigationTitle(game.startedAt.formatted(date: .abbreviated, time: .shortened))
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(game.startedAt.formatted(date: .abbreviated, time: .shortened)).font(.headline)
                            Text(game.standings.map { "\($0.player.name) \($0.player.points)" }.joined(separator: " · "))
                                .font(.subheadline).foregroundStyle(.secondary)
                            Text(model.text("\(game.turns.flatMap(\.words).count) sanaa · \(game.rules.language.uppercased())",
                                            "\(game.turns.flatMap(\.words).count) words · \(game.rules.language.uppercased())"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { model.deleteHistory(at: $0) }
            }
            .navigationTitle(model.text("Pelihistoria", "Game history"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button(model.text("← Alkuun", "← Home")) { model.screen = .welcome } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(model.text("Tyhjennä", "Clear"), role: .destructive) { confirmClear = true }.disabled(model.history.isEmpty)
                }
            }
            .confirmationDialog(model.text("Poistetaanko koko historia?", "Delete all history?"), isPresented: $confirmClear, titleVisibility: .visible) {
                Button(model.text("Poista", "Delete"), role: .destructive) { model.clearHistory() }
            }
        }
    }
}
