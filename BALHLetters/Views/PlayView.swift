import SwiftUI

struct PlayView: View {
    @EnvironmentObject var model: GameModel
    @Environment(\.scenePhase) private var scene
    @StateObject private var camera = CameraModel()
    @State private var entry = ""
    @State private var confirmEnd = false

    private var cameraWanted: Bool { model.screen == .play && model.phase != .review && model.phase != .finished && scene == .active }

    var body: some View {
        if let game = model.game {
            ScrollView {
                VStack(spacing: 16) {
                    header(game)
                    if game.phase == .review {
                        ReviewPanel(entry: $entry)
                    } else {
                        TimerBar(remaining: game.remaining, total: game.rules.turnSeconds, running: game.phase == .running)
                        cameraCard(game)
                        controls(game)
                        TurnWords(entry: $entry)
                        detected(game)
                        Card { WordEntry(text: $entry) }
                    }
                    Scoreboard()
                    Text(model.text("Aseta sana vaakasuoraan, kirjaimet pystyssä. ◇ korvaa yhden kirjaimen (0 p). Sama sana pisteytetään vain kerran pelissä.",
                                    "Lay words horizontally with upright letters. ◇ replaces one letter (0 p). Each word scores once per game."))
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .padding(18)
            }
            .scrollDismissesKeyboard(.interactively)
            .onAppear { syncCamera() }
            .onDisappear { camera.stop() }
            .onChange(of: cameraWanted) { _, _ in syncCamera() }
            .onChange(of: camera.words) { _, words in
                for word in words where word.isStable { model.autoCollect(word.word) }
            }
            .confirmationDialog(model.text("Lopetetaanko peli?", "End the game?"), isPresented: $confirmEnd, titleVisibility: .visible) {
                Button(model.text("Lopeta ja näytä tulokset", "End and show results"), role: .destructive) { model.endGame() }
                Button(model.text("Peruuta", "Cancel"), role: .cancel) {}
            } message: {
                Text(model.text("Tämän vuoron tallennetut sanat lasketaan mukaan.", "Words saved this turn still count."))
            }
        } else {
            VStack { Text("—"); Button(model.text("Alkuun", "Home")) { model.screen = .welcome } }
        }
    }

    private func syncCamera() {
        if cameraWanted { camera.start(language: model.game?.rules.language ?? model.language) } else { camera.stop() }
    }

    private func header(_ game: Game) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(game.currentPlayer?.name ?? "").font(.title.bold()).lineLimit(1)
                Text(game.rules.rounds > 0
                     ? model.text("Kierros \(game.round)/\(game.rules.rounds)", "Round \(game.round)/\(game.rules.rounds)")
                     : model.text("Kierros \(game.round)", "Round \(game.round)"))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Text(String(format: "%d:%02d", game.remaining / 60, game.remaining % 60))
                .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(game.remaining <= 5 && game.phase == .running ? Theme.coral : Theme.accent)
            Menu {
                Button(model.text("Alkuun (peli tallessa)", "Home (game is saved)"), systemImage: "house") { model.leaveToHome() }
                Button(model.text("Lopeta peli", "End game"), systemImage: "flag.checkered", role: .destructive) { confirmEnd = true }
            } label: {
                Image(systemName: "ellipsis.circle").font(.title2).padding(.leading, 6)
            }
        }
    }

    private func cameraCard(_ game: Game) -> some View {
        ZStack(alignment: .topTrailing) {
            CameraPreview(session: camera.session).overlay { WordOverlay(words: camera.words) }
            if camera.torchAvailable {
                Button { camera.toggleTorch() } label: {
                    Image(systemName: camera.torchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                        .padding(10).background(.ultraThinMaterial).clipShape(Circle())
                }.padding(10)
            }
            if game.phase != .running && !camera.permissionDenied {
                Text(game.phase == .ready ? model.text("Paina Aloita — kello käynnistyy", "Press Start — the clock begins") : model.text("Tauko", "Paused"))
                    .font(.headline).padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.ultraThinMaterial).clipShape(Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if camera.permissionDenied {
                VStack(spacing: 8) {
                    Text(model.text("Salli kamera iPhonen asetuksista. Voit myös kirjoittaa sanat käsin.", "Allow the camera in iPhone Settings. You can also type words."))
                        .multilineTextAlignment(.center)
                    Button(model.text("Avaa asetukset", "Open Settings")) {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                }
                .padding().background(.ultraThinMaterial).clipShape(RoundedRectangle(cornerRadius: 12))
                .frame(maxWidth: .infinity, maxHeight: .infinity).padding()
            }
            if let toast = model.toast {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("\(toast.tiles)  +\(toast.points)").bold()
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Theme.green).foregroundStyle(.white).clipShape(Capsule())
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom).padding(.bottom, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(height: 340)
        .background(.black)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .animation(.spring(duration: 0.3), value: model.toast)
        .overlay(alignment: .bottomLeading) {
            if !camera.message.isEmpty { Text(camera.message).font(.caption2).padding(6).background(.ultraThinMaterial).clipShape(Capsule()).padding(8) }
        }
    }

    private func controls(_ game: Game) -> some View {
        HStack(spacing: 12) {
            Button {
                model.toggle()
            } label: {
                Label(game.phase == .running ? model.text("Tauko", "Pause") : game.phase == .paused ? model.text("Jatka", "Resume") : model.text("Aloita", "Start"),
                      systemImage: game.phase == .running ? "pause.fill" : "play.fill")
            }
            .buttonStyle(PrimaryButton(color: game.phase == .running ? Theme.ink : Theme.accent))
            Button { model.finishTurnEarly() } label: { Label(model.text("Valmis", "Done"), systemImage: "checkmark") }
                .buttonStyle(PrimaryButton(color: Theme.green))
                .frame(maxWidth: 140)
        }
    }

    @ViewBuilder private func detected(_ game: Game) -> some View {
        let unsaved = camera.words.filter { status(of: $0.word) != .saved }
        if !unsaved.isEmpty {
            Card {
                Text(model.text("Kamera näkee", "Camera sees")).font(.headline)
                ForEach(unsaved) { found in
                    let state = status(of: found.word)
                    Button { entry = found.word } label: {
                        HStack {
                            Text(found.word).font(.title3.bold()).foregroundStyle(.primary)
                            Spacer()
                            Text(state.label(model)).font(.caption).foregroundStyle(state.color)
                            Image(systemName: "pencil").foregroundStyle(.secondary)
                        }
                    }
                }
                Text(model.text("Napauta sanaa korjataksesi tai valitaksesi jokerin.", "Tap a word to fix it or choose the joker."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        } else if game.phase == .running && game.pending.isEmpty {
            Text(model.text("Osoita kameralla selkeitä kirjaimia. Löydetyt sanat tallentuvat tähän.", "Point the camera at clear letters. Found words are saved here."))
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
    }

    func status(of tiles: String) -> WordStatus { WordStatus(tiles, model: model) }
}

/// What a detected word means right now. Used for colours and labels.
enum WordStatus: Equatable {
    case saved, played, valid, choose, notFound, tooShort
    @MainActor init(_ tiles: String, model: GameModel) {
        let display = WordText.display(tiles)
        if model.game?.pending.contains(where: { $0.tiles == display }) == true { self = .saved; return }
        switch model.check(tiles) {
        case .alreadyPlayed: self = .played
        case .valid: self = .valid
        case .choose: self = .choose
        case .notFound: self = .notFound
        case .tooShort, .none: self = .tooShort
        }
    }
    var color: Color {
        switch self {
        case .saved: return Theme.green
        case .valid: return Theme.accent
        case .played, .tooShort: return .gray
        case .choose: return Theme.accent
        case .notFound: return Theme.coral
        }
    }
    @MainActor func label(_ model: GameModel) -> String {
        switch self {
        case .saved: return model.text("tallennettu ✓", "saved ✓")
        case .played: return model.text("jo pelattu", "already played")
        case .valid: return model.text("löytyy – odottaa", "found – waiting")
        case .choose: return model.text("valitse jokeri", "choose joker")
        case .notFound: return model.text("ei sanastossa", "not in list")
        case .tooShort: return ""
        }
    }
}

struct TimerBar: View {
    let remaining: Int
    let total: Int
    let running: Bool
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.black.opacity(0.08))
                Capsule().fill(remaining <= 5 ? Theme.coral : Theme.accent)
                    .frame(width: geo.size.width * CGFloat(max(0, min(1, Double(remaining) / Double(max(total, 1))))))
                    .animation(.linear(duration: running ? 1 : 0.2), value: remaining)
            }
        }
        .frame(height: 8)
    }
}

struct WordOverlay: View {
    @EnvironmentObject var model: GameModel
    let words: [FoundWord]
    var body: some View {
        GeometryReader { geometry in
            // Preview uses aspect fill of a 9:16 portrait image.
            let k = max(geometry.size.width / 9, geometry.size.height / 16)
            let w = 9 * k, h = 16 * k
            let ox = (geometry.size.width - w) / 2, oy = (geometry.size.height - h) / 2
            ForEach(words) { found in
                let rect = found.box
                let status = WordStatus(found.word, model: model)
                RoundedRectangle(cornerRadius: 4).stroke(status.color, lineWidth: found.isStable ? 3 : 1.5)
                    .frame(width: rect.width * w, height: rect.height * h)
                    .position(x: ox + rect.midX * w, y: oy + (1 - rect.midY) * h)
                let suffix: String = status == .saved ? " ✓" : (status == .notFound ? " ?" : "")
                Text(found.word + suffix)
                    .font(.caption2.bold()).padding(4).background(.white.opacity(0.9)).foregroundStyle(status.color)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .position(x: max(40, min(geometry.size.width - 40, ox + rect.midX * w)), y: max(12, oy + (1 - rect.maxY) * h - 12))
            }
        }
        .allowsHitTesting(false)
    }
}
