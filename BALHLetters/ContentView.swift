import SwiftUI

struct ContentView: View {
    @EnvironmentObject var model: GameModel
    @Environment(\.scenePhase) private var scene
    private static let clock = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Theme.gradient.ignoresSafeArea()
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
        .onReceive(Self.clock) { _ in model.tick() }
        .onChange(of: scene) { _, phase in if phase == .background { model.pause() } }
    }
}

// MARK: - Welcome

struct WelcomeView: View {
    @EnvironmentObject var model: GameModel
    @State private var showingLicenses = false

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                HStack { Spacer(); LanguagePicker() }
                Spacer(minLength: 24)
                VStack(spacing: 14) {
                    HStack(spacing: 10) { ForEach(Array("BALH".enumerated()), id: \.offset) { TileView(letter: $0.element, size: 58) } }
                        Text("LETTERS")
                        .font(.system(size: 30, weight: .semibold)).tracking(10)
                        .foregroundStyle(Theme.accent)
                }
                Text(model.text("Laatat pöytään.\nKamera laskee.", "Tiles on the table.\nThe camera keeps score."))
                    .font(.system(size: 30, weight: .bold))
                    .multilineTextAlignment(.center)
                Text(model.text("Muodosta sanoja kirjainlaatoista. Kamera lukee ne, ja vuoron lopussa jokainen oikea sana tuo pisteet.",
                                "Build words from letter tiles. The camera reads them, and at the end of the turn every correct word scores."))
                    .foregroundStyle(Theme.muted).multilineTextAlignment(.center)

                VStack(spacing: 12) {
                    if model.hasUnfinishedGame, let game = model.game {
                        Button { model.resume() } label: {
                            VStack(spacing: 3) {
                                Label(model.text("Jatka peliä", "Continue game"), systemImage: "play.fill")
                                Text(game.players.map { "\($0.name) \($0.points)" }.joined(separator: "  ·  "))
                                    .font(.caption).opacity(0.85).lineLimit(1).truncationMode(.middle)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                        }.buttonStyle(PrimaryButton())
                    }
                    Button(model.text("Uusi peli", "New game")) { model.screen = .setup }
                        .buttonStyle(model.hasUnfinishedGame ? AnyButtonStyle(GhostButton()) : AnyButtonStyle(PrimaryButton()))
                    if !model.history.isEmpty {
                        Button { model.screen = .history } label: {
                            Label(model.text("Pelihistoria (\(model.history.count))", "Game history (\(model.history.count))"), systemImage: "clock.arrow.circlepath")
                        }.buttonStyle(GhostButton())
                    }
                }
                HStack(spacing: 14) {
                    Label(model.text("1–6 pelaajaa", "1–6 players"), systemImage: "person.2.fill")
                    Label("FI · EN", systemImage: "globe")
                    Label(model.text("◇ jokeri", "◇ joker"), systemImage: "sparkle")
                }
                .font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
                Button(model.text("Sanastot ja lisenssit", "Word lists & licenses")) { showingLicenses = true }
                    .font(.footnote).foregroundStyle(Theme.muted)
            }
            .padding(22)
        }
        .sheet(isPresented: $showingLicenses) { LicensesView() }
    }
}

/// Lets a ternary pick between two button styles.
struct AnyButtonStyle: ButtonStyle {
    private let make: (Configuration) -> AnyView
    init<S: ButtonStyle>(_ style: S) { make = { AnyView(style.makeBody(configuration: $0)) } }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}

struct LanguagePicker: View {
    @EnvironmentObject var model: GameModel
    var body: some View {
        ChipPicker(selection: $model.language, options: [("fi", "FI"), ("en", "EN")]).frame(width: 120)
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

// MARK: - Setup

struct SetupView: View {
    @EnvironmentObject var model: GameModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Button { model.screen = .welcome } label: { Label(model.text("Alkuun", "Home"), systemImage: "chevron.left") }
                    Spacer()
                    LanguagePicker()
                }
                Text(model.text("Uusi peli", "New game")).font(.system(size: 34, weight: .bold))

                Card {
                    SectionTitle(text: model.text("Pelaajat", "Players"), trailing: "\(model.playerCount)")
                    ChipPicker(selection: $model.playerCount, options: (1...6).map { ($0, "\($0)") })
                    ForEach(0..<model.playerCount, id: \.self) { i in
                        HStack(spacing: 10) {
                            Avatar(name: model.names[i].isEmpty ? "\(i + 1)" : model.names[i], index: i)
                            TextField("", text: $model.names[i], prompt: Text(model.text("Pelaaja", "Player") + " \(i + 1)").foregroundStyle(Theme.muted))
                                .darkField().submitLabel(.done)
                        }
                    }
                }

                Card {
                    SectionTitle(text: model.text("Aikaa per vuoro", "Time per turn"))
                    ChipPicker(selection: $model.rules.turnSeconds, options: [30, 60, 90, 120, 180].map { ($0, "\($0)s") })
                    SectionTitle(text: model.text("Kierroksia", "Rounds")).padding(.top, 6)
                    ChipPicker(selection: $model.rules.rounds, options: [(1, "1"), (2, "2"), (3, "3"), (5, "5"), (0, "∞")])
                    Text(model.rules.rounds == 0
                         ? model.text("Pelataan kunnes lopetatte.", "Play until you stop.")
                         : model.text("Jokainen pelaaja saa \(model.rules.rounds) vuoroa.", "Each player gets \(model.rules.rounds) turn(s)."))
                        .font(.caption).foregroundStyle(Theme.muted)
                }

                Card {
                    SectionTitle(text: model.text("Säännöt", "Rules"))
                    Toggle(isOn: $model.rules.autoCollect) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.text("Kamera tallentaa sanat itse", "Camera saves words itself")).font(.subheadline.weight(.semibold))
                            Text(model.text("Sanastosta löytyvä sana tallentuu, kun kamera on lukenut sen kahdesti.", "A word in the word list is saved after the camera reads it twice."))
                                .font(.caption).foregroundStyle(Theme.muted)
                        }
                    }
                    Divider().overlay(Theme.line)
                    Toggle(isOn: $model.rules.allowHouseWords) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.text("Salli sanat sanaston ulkopuolelta", "Allow words outside the word list")).font(.subheadline.weight(.semibold))
                            Text(model.text("Pelaajat voivat hyväksyä sanan käsin, esim. harvinaiset muodot.", "Players can accept a word by hand, e.g. rare forms."))
                                .font(.caption).foregroundStyle(Theme.muted)
                        }
                    }
                }
                .tint(Theme.accent)

                Text(model.text("Vähintään 2 kirjainta · Pisteet laattojen mukaan · ◇ = 0 p · Sama sana vain kerran per peli",
                                "At least 2 letters · Tile values · ◇ = 0 p · Each word once per game"))
                    .font(.footnote).foregroundStyle(Theme.muted)
                if model.dictionaryError { Text(model.text("Sanastojen lataus epäonnistui.", "Word lists failed to load.")).foregroundStyle(Theme.coral) }
                Button { model.newGame() } label: {
                    Label(model.dictionaryReady ? model.text("Aloita peli", "Start game") : model.text("Ladataan sanastoja…", "Loading words…"), systemImage: "play.fill")
                }
                .buttonStyle(PrimaryButton()).disabled(!model.dictionaryReady)
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
    }
}
