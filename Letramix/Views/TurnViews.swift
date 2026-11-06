import SwiftUI

/// The words saved during this turn, with a running total.
struct TurnWords: View {
    @EnvironmentObject var model: GameModel
    @Binding var entry: String
    var editable = true

    var body: some View {
        if let game = model.game {
            Card {
                HStack {
                    Text(model.text("Tämän vuoron sanat", "Words this turn")).font(.headline)
                    Spacer()
                    Text(model.text("\(game.pending.count) sanaa · \(game.pendingPoints) p", "\(game.pending.count) words · \(game.pendingPoints) p"))
                        .font(.subheadline.bold()).foregroundStyle(Theme.purple)
                }
                if game.pending.isEmpty {
                    Text(model.text("Ei vielä sanoja.", "No words yet.")).font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(game.pending.reversed()) { word in WordRow(word: word, onRemove: editable ? { model.remove(word) } : nil) }
            }
        }
    }
}

struct WordRow: View {
    @EnvironmentObject var model: GameModel
    let word: PlayedWord
    var onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                TileWord(word: word.tiles, size: 22)
                HStack(spacing: 4) {
                    if word.tiles.contains(jokerSymbol) { Text("= \(word.word.uppercased())").bold() }
                    if let base = word.base { Text("← \(base)") }
                    Text(word.kind.label(model))
                    if word.fromCamera { Image(systemName: "camera.fill") }
                }
                .font(.caption2).foregroundStyle(word.kind == .house ? Theme.orange : .secondary)
            }
            Spacer()
            Text("+\(word.points)").font(.headline.monospacedDigit()).foregroundStyle(Theme.green)
            if let onRemove {
                Button(role: .destructive, action: onRemove) { Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.gray.opacity(0.6)) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(model.text("Poista", "Remove"))
            }
        }
    }
}

/// Type a word (or fix a camera read). Handles jokers and house words.
struct WordEntry: View {
    @EnvironmentObject var model: GameModel
    @Binding var text: String
    @FocusState private var focused: Bool
    var title: String?

    init(text: Binding<String>, title: String? = nil) { _text = text; self.title = title }

    private var accepts: Bool { model.game?.acceptsWords ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title ?? model.text("Kirjoita tai korjaa sana", "Type or fix a word")).font(.headline)
            HStack(spacing: 8) {
                TextField(model.text("esim. KALA tai K◇LA", "e.g. CAT or C◇T"), text: $text)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit(submit)
                Button { text.append(jokerSymbol) } label: { Text("◇").font(.title3.bold()).frame(width: 40, height: 36) }
                    .buttonStyle(.bordered)
                    .accessibilityLabel(model.text("Lisää jokeri", "Insert joker"))
                Button(action: submit) { Text("+\(TileRules.points(WordText.normalize(text)))").bold().frame(minWidth: 44, minHeight: 36) }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSubmit)
            }
            status
        }
        .disabled(!accepts)
        .opacity(accepts ? 1 : 0.5)
    }

    private var check: WordCheck? { text.isEmpty ? nil : model.check(text) }
    private var canSubmit: Bool { if case .valid = check { return true }; return false }

    private func submit() {
        guard canSubmit else { return }
        if case .saved = model.add(text) { text = "" }
    }

    @ViewBuilder private var status: some View {
        switch check {
        case .none:
            if !accepts { Text(model.text("Paina Aloita, niin voit tallentaa sanoja.", "Press Start to save words.")).font(.caption).foregroundStyle(.secondary) }
        case .tooShort?:
            Text(model.text("Vähintään 2 kirjainta.", "At least 2 letters.")).font(.caption).foregroundStyle(.secondary)
        case .alreadyPlayed(let word)?:
            Text(model.text("\(word.uppercased()) on jo pelattu tässä pelissä.", "\(word.uppercased()) was already played this game.")).font(.caption).foregroundStyle(.secondary)
        case .valid(let match)?:
            Text(match.kind == .inflected
                 ? model.text("✓ Taivutusmuoto sanasta \(match.base?.uppercased() ?? "")", "✓ Form of \(match.base?.uppercased() ?? "")")
                 : model.text("✓ Sana löytyy", "✓ Word found"))
                .font(.caption.bold()).foregroundStyle(Theme.green)
        case .choose(let options)?:
            Text(model.text("Mitä jokeri tarkoittaa? Valitse sana:", "What does the joker stand for? Pick one:")).font(.caption)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(options, id: \.word) { option in
                        Button(option.word.uppercased()) { if case .saved = model.add(text, chosen: option.word) { text = "" } }
                            .buttonStyle(.bordered)
                    }
                }
            }
        case .notFound?:
            Text(model.text("Ei löydy sanastosta.", "Not in the word list.")).font(.caption).foregroundStyle(Theme.orange)
            if model.game?.rules.allowHouseWords == true && !text.contains(jokerSymbol) {
                Button(model.text("Hyväksy silti – kaikki pelaajat samaa mieltä", "Accept anyway – all players agree")) {
                    if case .saved = model.add(text, house: true) { text = "" }
                }
                .font(.caption.bold())
            }
        }
    }
}

/// Shown when the time is up: check the saved words, add any the camera missed, then score them all.
struct ReviewPanel: View {
    @EnvironmentObject var model: GameModel
    @Binding var entry: String

    var body: some View {
        if let game = model.game {
            VStack(spacing: 16) {
                VStack(spacing: 6) {
                    Text(game.remaining == 0 ? model.text("Aika loppui!", "Time’s up!") : model.text("Vuoro valmis", "Turn complete"))
                        .font(.largeTitle.bold())
                    Text(model.text("\(game.currentPlayer?.name ?? "") sai \(game.pending.count) sanaa", "\(game.currentPlayer?.name ?? "") made \(game.pending.count) words"))
                        .font(.headline)
                    Text("+\(game.pendingPoints) p")
                        .font(.system(size: 54, weight: .heavy, design: .rounded)).foregroundStyle(Theme.green)
                        .contentTransition(.numericText())
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)

                TurnWords(entry: $entry)
                Card { WordEntry(text: $entry, title: model.text("Puuttuiko sana? Lisää se", "Missing a word? Add it")) }

                Button {
                    entry = ""
                    model.confirmTurn()
                } label: {
                    Text(game.isLastTurn
                         ? model.text("Hyväksy pisteet ja katso tulokset", "Accept points and see results")
                         : model.text("Hyväksy +\(game.pendingPoints) p · Seuraava: \(nextName(game))", "Accept +\(game.pendingPoints) p · Next: \(nextName(game))"))
                        .multilineTextAlignment(.center)
                }
                .buttonStyle(PrimaryButton(color: Theme.green))
                Text(model.text("Poista väärin tunnistetut sanat ✕-napista ennen hyväksymistä.", "Remove misread words with ✕ before accepting."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .animation(.default, value: game.pendingPoints)
        }
    }

    private func nextName(_ game: Game) -> String {
        guard !game.players.isEmpty else { return "" }
        return game.players[(game.current + 1) % game.players.count].name
    }
}

struct Scoreboard: View {
    @EnvironmentObject var model: GameModel
    var body: some View {
        if let game = model.game {
            Card {
                Text(model.text("Pisteet", "Scores")).font(.headline)
                ForEach(Array(game.players.enumerated()), id: \.element.id) { index, player in
                    HStack {
                        if index == game.current && game.phase != .finished { Image(systemName: "arrowtriangle.right.fill").font(.caption).foregroundStyle(Theme.purple) }
                        Text(player.name).fontWeight(index == game.current ? .bold : .regular)
                        Spacer()
                        Text(model.text("\(game.words(of: index).count) sanaa", "\(game.words(of: index).count) words")).font(.caption).foregroundStyle(.secondary)
                        Text("\(player.points)").font(.headline.monospacedDigit()).frame(minWidth: 40, alignment: .trailing)
                    }
                }
            }
        }
    }
}
