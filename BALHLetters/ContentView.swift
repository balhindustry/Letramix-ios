import SwiftUI

struct ContentView: View {
    @EnvironmentObject var model: GameModel
    @Environment(\.scenePhase) private var scene
    private let clock = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Theme.paper.ignoresSafeArea()
            switch model.screen {
            case .welcome: WelcomeView()
            case .setup: SetupView()
            case .play: PlayView()
            case .results: ResultsView()
            case .history: HistoryView()
            }
        }
        .tint(Theme.accent)
        .animation(.easeInOut(duration: 0.2), value: model.screen)
        .onReceive(clock) { _ in model.tick() }
        .onChange(of: scene) { _, phase in if phase == .background { model.pause() } }
    }
}

struct WelcomeView: View {
    @EnvironmentObject var model: GameModel
    @State private var showingLicenses = false

    var body: some View {
        ScrollView {
            VStack(spacing: 26) {
                HStack { Spacer(); LanguagePicker() }
                Spacer(minLength: 30)
                VStack(spacing: 10) {
                    HStack(spacing: 8) { ForEach(Array("BALH".enumerated()), id: \.offset) { TileView(letter: $0.element, size: 50) } }
                    Text("LETTERS").font(.system(size: 30, weight: .black, design: .rounded)).tracking(10).foregroundStyle(Theme.accent)
                }
                Text(model.text("Sanoista syntyy peli.", "Let the words play."))
                    .font(.largeTitle.bold()).multilineTextAlignment(.center)
                Text(model.text("Muodosta sanoja laatoista. Kamera tallentaa sanat, ja vuoron lopussa jokainen oikea sana tuo pisteet.",
                                "Build words from tiles. The camera saves them, and at the end of the turn every correct word scores."))
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)

                VStack(spacing: 12) {
                    if model.hasUnfinishedGame, let game = model.game {
                        Button { model.resume() } label: {
                            VStack(spacing: 2) {
                                Text(model.text("Jatka peliä", "Continue game"))
                                Text(game.players.map { "\($0.name) \($0.points)" }.joined(separator: " · ")).font(.caption).opacity(0.85)
                            }
                        }.buttonStyle(PrimaryButton())
                    }
                    Button(model.text("Uusi peli", "New game")) { model.screen = .setup }
                        .buttonStyle(PrimaryButton(color: model.hasUnfinishedGame ? Theme.ink : Theme.accent))
                    if !model.history.isEmpty {
                        Button(model.text("Pelihistoria (\(model.history.count))", "Game history (\(model.history.count))")) { model.screen = .history }
                            .font(.headline).padding(.top, 4)
                    }
                }
                Text(model.text("1–6 pelaajaa · Suomi & englanti · ◇ = jokeri", "1–6 players · Finnish & English · ◇ = joker"))
                    .font(.footnote).foregroundStyle(.secondary)
                Button(model.text("Sanastot ja lisenssit", "Word lists & licenses")) { showingLicenses = true }.font(.footnote)
            }
            .padding(22)
        }
        .sheet(isPresented: $showingLicenses) { LicensesView() }
    }
}

struct LanguagePicker: View {
    @EnvironmentObject var model: GameModel
    var body: some View {
        Picker("Language", selection: $model.language) { Text("FI").tag("fi"); Text("EN").tag("en") }
            .pickerStyle(.segmented).frame(width: 110)
    }
}

struct LicensesView: View {
    @Environment(\.dismiss) private var dismiss
    var notices: String {
        guard let url = Bundle.main.url(forResource: "NOTICES", withExtension: "txt") else { return "License file missing" }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? "License file unreadable"
    }
    var body: some View {
        NavigationStack {
            ScrollView { Text(notices).font(.footnote).padding() }
                .navigationTitle("Licenses")
                .toolbar { Button("OK") { dismiss() } }
        }
    }
}

struct SetupView: View {
    @EnvironmentObject var model: GameModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Button(model.text("← Alkuun", "← Home")) { model.screen = .welcome }
                    Spacer()
                    LanguagePicker()
                }
                Text(model.text("Pelin asetukset", "Game settings")).font(.largeTitle.bold())

                Card {
                    Stepper(model.text("Pelaajia", "Players") + ": \(model.playerCount)", value: $model.playerCount, in: 1...6).font(.headline)
                    ForEach(0..<model.playerCount, id: \.self) { i in
                        TextField(model.text("Pelaaja", "Player") + " \(i + 1)", text: $model.names[i])
                            .textFieldStyle(.roundedBorder).submitLabel(.done)
                    }
                }

                Card {
                    Text(model.text("Aikaa per vuoro", "Time per turn")).font(.headline)
                    Picker("Time", selection: $model.rules.turnSeconds) { ForEach([30, 60, 90, 120, 180], id: \.self) { Text("\($0) s").tag($0) } }
                        .pickerStyle(.segmented)
                    Text(model.text("Kierroksia", "Rounds")).font(.headline)
                    Picker("Rounds", selection: $model.rules.rounds) {
                        ForEach([1, 2, 3, 5], id: \.self) { Text("\($0)").tag($0) }
                        Text("∞").tag(0)
                    }.pickerStyle(.segmented)
                    Text(model.rules.rounds == 0
                         ? model.text("Pelataan kunnes lopetatte.", "Play until you stop.")
                         : model.text("Jokainen pelaaja saa \(model.rules.rounds) vuoroa.", "Each player gets \(model.rules.rounds) turn(s)."))
                        .font(.caption).foregroundStyle(.secondary)
                }

                Card {
                    Toggle(isOn: $model.rules.autoCollect) {
                        VStack(alignment: .leading) {
                            Text(model.text("Tallenna kameran sanat automaattisesti", "Save camera words automatically"))
                            Text(model.text("Sanastosta löytyvä sana tallentuu, kun kamera on lukenut sen kahdesti.", "A word in the word list is saved after the camera reads it twice."))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Toggle(isOn: $model.rules.allowHouseWords) {
                        VStack(alignment: .leading) {
                            Text(model.text("Salli sanat sanaston ulkopuolelta", "Allow words outside the word list"))
                            Text(model.text("Pelaajat voivat hyväksyä sanan käsin (esim. nimet, harvinaiset muodot).", "Players can accept a word by hand (e.g. rare forms)."))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                Text(model.text("Vähintään 2 kirjainta · Pisteet laattojen mukaan · ◇ = 0 p · Sama sana vain kerran per peli",
                                "At least 2 letters · Tile values · ◇ = 0 p · Each word once per game"))
                    .font(.footnote).foregroundStyle(.secondary)
                if model.dictionaryError { Text(model.text("Sanastojen lataus epäonnistui.", "Word lists failed to load.")).foregroundStyle(.red) }
                Button(model.dictionaryReady ? model.text("Aloita peli →", "Start game →") : model.text("Ladataan sanastoja…", "Loading words…")) { model.newGame() }
                    .buttonStyle(PrimaryButton()).disabled(!model.dictionaryReady)
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
    }
}
