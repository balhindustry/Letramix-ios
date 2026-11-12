import SwiftUI

/// The words saved during this turn, as chips, with a running total.
struct TurnWords: View {
    @EnvironmentObject var model: GameModel
    @Binding var entry: String
    var editable = true

    var body: some View {
        if let game = model.game {
            Card {
                SectionTitle(text: model.text("Tämän vuoron sanat", "Words this turn"),
                             trailing: model.text("\(game.pending.count) sanaa · \(game.pendingPoints) p", "\(game.pending.count) words · \(game.pendingPoints) p"))
                if game.pending.isEmpty {
                    Text(model.text("Ei vielä sanoja.", "No words yet.")).font(.footnote).foregroundStyle(Theme.muted)
                } else {
                    FlowLayout(spacing: 8) {
                        ForEach(game.pending.reversed()) { word in
                            WordChip(word: word, onRemove: editable ? { () -> Void in withAnimation { model.remove(word) } } : nil)
                                .onTapGesture { entry = word.tiles }
                        }
                    }
                }
            }
            .animation(.spring(duration: 0.3), value: game.pending.count)
        }
    }
}

/// Full-detail row used in review, results and history.
struct WordRow: View {
    @EnvironmentObject var model: GameModel
    let word: PlayedWord
    var onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                TileWord(word: word.tiles, size: 24)
                HStack(spacing: 6) {
                    if word.tiles.contains(jokerSymbol) { Text("= \(word.word.uppercased())").bold() }
                    if let base = word.base { Text("← \(base.uppercased())") }
                    Text(word.kind.label(model))
                    Text(model.text("\(word.tiles.count) kirjainta", "\(word.tiles.count) letters"))
                    if word.fromCamera { Image(systemName: "camera.fill") }
                }
                .font(.caption2).foregroundStyle(word.kind == .house ? Theme.coral : Theme.muted)
            }
            Spacer()
            Text("+\(word.points)").font(.system(.headline).weight(.semibold).monospacedDigit()).foregroundStyle(Theme.green)
            if let onRemove {
                Button(role: .destructive, action: onRemove) { Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(Theme.muted) }
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
            SectionTitle(text: title ?? model.text("Kirjoita tai korjaa sana", "Type or fix a word"))
            HStack(spacing: 8) {
                TextField("", text: $text, prompt: Text(model.text("esim. KALA tai K◇LA", "e.g. CAT or C◇T")).foregroundStyle(Theme.muted))
                    .darkField()
                    .font(.system(.headline))
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit(submit)
                Button { text.append(jokerSymbol) } label: {
                    Text("◇").font(.title3.bold()).frame(width: 46, height: 46).background(Theme.surfaceHigh).foregroundStyle(Theme.coral).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(model.text("Lisää jokeri", "Insert joker"))
                Button(action: submit) {
                    Text("+\(TileRules.points(WordText.normalize(text)))").font(.system(.headline).weight(.semibold))
                        .frame(minWidth: 52, minHeight: 46)
                        .background(canSubmit ? Theme.accent : Theme.surfaceHigh).foregroundStyle(canSubmit ? Theme.ink : Theme.muted)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit)
            }
            if !text.isEmpty { TileWord(word: WordText.display(text), size: 22) }
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
            if !accepts { Text(model.text("Paina Aloita, niin voit tallentaa sanoja.", "Press Start to save words.")).font(.caption).foregroundStyle(Theme.muted) }
        case .tooShort?:
            Text(model.text("Vähintään 2 kirjainta.", "At least 2 letters.")).font(.caption).foregroundStyle(Theme.muted)
        case .alreadyPlayed(let word)?:
            Text(model.text("\(word.uppercased()) on jo pelattu tässä pelissä.", "\(word.uppercased()) was already played this game.")).font(.caption).foregroundStyle(Theme.muted)
        case .valid(let match)?:
            Text(match.kind == .inflected
                 ? model.text("✓ Taivutusmuoto sanasta \(match.base?.uppercased() ?? "")", "✓ Form of \(match.base?.uppercased() ?? "")")
                 : model.text("✓ Sana löytyy", "✓ Word found"))
                .font(.caption.bold()).foregroundStyle(Theme.green)
        case .choose(let options)?:
            Text(model.text("Mitä jokeri tarkoittaa? Valitse sana:", "What does the joker stand for? Pick one:")).font(.caption).foregroundStyle(Theme.muted)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(options, id: \.word) { option in
                        Button(option.word.uppercased()) { if case .saved = model.add(text, chosen: option.word) { text = "" } }
                            .font(.subheadline.bold()).padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Theme.surfaceHigh).clipShape(Capsule()).foregroundStyle(Theme.text)
                    }
                }
            }
        case .notFound?:
            Text(model.text("Ei löydy sanastosta.", "Not in the word list.")).font(.caption).foregroundStyle(Theme.coral)
            if model.game?.rules.allowHouseWords == true && !text.contains(jokerSymbol) {
                Button(model.text("Hyväksy silti – kaikki pelaajat samaa mieltä", "Accept anyway – all players agree")) {
                    if case .saved = model.add(text, house: true) { text = "" }
                }
                .font(.caption.bold()).foregroundStyle(Theme.coral)
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
                VStack(spacing: 4) {
                    Text(game.remaining == 0 ? model.text("Aika loppui!", "Time’s up!") : model.text("Vuoro valmis", "Turn complete"))
                        .font(.system(size: 32, weight: .bold))
                    Text(model.text("\(game.currentPlayer?.name ?? "") · \(game.pending.count) sanaa · \(game.pending.reduce(0) { $0 + $1.tiles.count }) kirjainta",
                                    "\(game.currentPlayer?.name ?? "") · \(game.pending.count) words · \(game.pending.reduce(0) { $0 + $1.tiles.count }) letters"))
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.muted)
                    Text("+\(game.pendingPoints)")
                        .font(.system(size: 72, weight: .bold)).foregroundStyle(Theme.green)
                        .contentTransition(.numericText())
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)

                Card {
                    SectionTitle(text: model.text("Tarkista sanat", "Check the words"), trailing: model.text("✕ poistaa", "✕ removes"))
                    if game.pending.isEmpty { Text(model.text("Ei sanoja tällä vuorolla.", "No words this turn.")).font(.footnote).foregroundStyle(Theme.muted) }
                    ForEach(game.pending) { word in
                        WordRow(word: word) { withAnimation { model.remove(word) } }
                        if word.id != game.pending.last?.id { Divider().overlay(Theme.line) }
                    }
                }
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
                SectionTitle(text: model.text("Pisteet", "Scores"))
                ForEach(Array(game.players.enumerated()), id: \.element.id) { index, player in
                    HStack(spacing: 10) {
                        Avatar(name: player.name, index: index, size: 30)
                        Text(player.name).font(.subheadline.weight(index == game.current ? .heavy : .medium))
                        if index == game.current && game.phase != .finished {
                            Circle().fill(Theme.accent).frame(width: 6, height: 6)
                        }
                        Spacer()
                        Text(model.text("\(game.words(of: index).count) sanaa", "\(game.words(of: index).count) words")).font(.caption).foregroundStyle(Theme.muted)
                        Text("\(player.points)").font(.system(.headline).weight(.semibold).monospacedDigit()).frame(minWidth: 40, alignment: .trailing)
                    }
                }
            }
        }
    }
}
