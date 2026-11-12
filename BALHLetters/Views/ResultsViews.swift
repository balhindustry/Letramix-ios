import SwiftUI

struct ResultsView: View {
    @EnvironmentObject var model: GameModel

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if let game = model.game {
                    Podium(game: game)
                    GameSummary(game: game)
                    Button { model.rematch() } label: { Label(model.text("Uusi peli samoilla pelaajilla", "Rematch"), systemImage: "arrow.counterclockwise") }
                        .buttonStyle(PrimaryButton())
                    Button(model.text("Alkuun", "Home")) { model.screen = .welcome }.buttonStyle(GhostButton())
                } else {
                    Button(model.text("Alkuun", "Home")) { model.screen = .welcome }.buttonStyle(GhostButton())
                }
            }
            .padding(20)
        }
    }
}

/// Top three on a podium; ties share a step.
struct Podium: View {
    @EnvironmentObject var model: GameModel
    let game: Game
    var body: some View {
        let standings = game.standings
        let tied = standings.filter { $0.place == 1 }.count > 1
        VStack(spacing: 12) {
            Text(tied ? model.text("Tasapeli!", "It’s a tie!") : model.text("\(standings.first?.player.name ?? "") voitti!", "\(standings.first?.player.name ?? "") wins!"))
                .font(.system(size: 32, weight: .bold)).multilineTextAlignment(.center)
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(podiumOrder(standings), id: \.id) { entry in
                    VStack(spacing: 6) {
                        Avatar(name: entry.player.name, index: entry.index, size: entry.place == 1 ? 52 : 42)
                        Text(entry.player.name).font(.caption.weight(.bold)).lineLimit(1)
                        Text("\(entry.player.points)").font(.system(.title2).weight(.bold))
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(entry.place == 1 ? Theme.gold : entry.place == 2 ? Color(.systemGray3) : Theme.coral.opacity(0.8))
                            .frame(height: entry.place == 1 ? 90 : entry.place == 2 ? 64 : 44)
                            .overlay(Text("\(entry.place)").font(.system(.title).weight(.bold)).foregroundStyle(entry.place == 3 ? Color.white : Color.black.opacity(0.75)))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.top, 10)
    }

    private func podiumOrder(_ standings: [Standing]) -> [Standing] {
        let top = Array(standings.prefix(3))
        switch top.count {
        case 3: return [top[1], top[0], top[2]]
        case 2: return [top[1], top[0]]
        default: return top
        }
    }
}

/// Standings, best word and every player's word list. Used by results and history.
struct GameSummary: View {
    @EnvironmentObject var model: GameModel
    let game: Game

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Stat(value: "\(game.turns.flatMap(\.words).count)", label: model.text("sanaa", "words"))
                Stat(value: "\(game.turns.flatMap(\.words).reduce(0) { $0 + $1.tiles.count })", label: model.text("kirjainta", "letters"))
                Stat(value: "\(game.players.reduce(0) { $0 + $1.points })", label: model.text("pistettä", "points"))
            }
            if let best = game.bestWord {
                Card {
                    SectionTitle(text: model.text("Paras sana", "Best word"), trailing: game.players.indices.contains(best.player) ? game.players[best.player].name : "")
                    HStack {
                        TileWord(word: best.word.tiles, size: 30)
                        Spacer()
                        Text("+\(best.word.points)").font(.system(.title2).weight(.bold)).foregroundStyle(Theme.green)
                    }
                }
            }
            ForEach(Array(game.players.enumerated()), id: \.element.id) { index, player in
                let words = game.words(of: index)
                Card {
                    DisclosureGroup {
                        if words.isEmpty { Text(model.text("Ei sanoja.", "No words.")).font(.caption).foregroundStyle(Theme.muted) }
                        ForEach(words) { WordRow(word: $0).padding(.top, 8) }
                    } label: {
                        HStack(spacing: 10) {
                            Avatar(name: player.name, index: index, size: 30)
                            Text(player.name).font(.headline)
                            Spacer()
                            Text(model.text("\(words.count) sanaa", "\(words.count) words")).font(.caption).foregroundStyle(Theme.muted)
                            Text("\(player.points)").font(.system(.headline).weight(.semibold))
                        }
                    }
                    .tint(Theme.muted)
                }
            }
        }
    }
}

struct Stat: View {
    let value: String
    let label: String
    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.system(.title).weight(.bold))
            Text(label.uppercased()).font(.caption2.weight(.bold)).tracking(1).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14)
        .background(Theme.surface).clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct HistoryView: View {
    @EnvironmentObject var model: GameModel
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(model.history) { game in
                        NavigationLink {
                            ScrollView { GameSummary(game: game).padding() }
                                .background(Theme.gradient.ignoresSafeArea())
                                .navigationTitle(game.startedAt.formatted(date: .abbreviated, time: .shortened))
                                                        } label: {
                            Card(padding: 14) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(game.startedAt.formatted(date: .abbreviated, time: .shortened)).font(.headline)
                                        Text(game.standings.map { "\($0.player.name) \($0.player.points)" }.joined(separator: "  ·  "))
                                            .font(.subheadline).foregroundStyle(Theme.muted).lineLimit(2)
                                        Text(model.text("\(game.turns.flatMap(\.words).count) sanaa · \(game.rules.language.uppercased())",
                                                        "\(game.turns.flatMap(\.words).count) words · \(game.rules.language.uppercased())"))
                                            .font(.caption).foregroundStyle(Theme.muted)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(Theme.muted)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(model.text("Poista", "Delete"), systemImage: "trash", role: .destructive) {
                                if let i = model.history.firstIndex(where: { $0.id == game.id }) { model.deleteHistory(at: IndexSet(integer: i)) }
                            }
                        }
                    }
                    if model.history.isEmpty { Text(model.text("Ei pelattuja pelejä.", "No games yet.")).foregroundStyle(Theme.muted).padding(.top, 40) }
                }
                .padding(18)
            }
            .background(Theme.gradient.ignoresSafeArea())
            .navigationTitle(model.text("Pelihistoria", "Game history"))
                        .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button(model.text("Alkuun", "Home"), systemImage: "chevron.left") { model.screen = .welcome } }
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
