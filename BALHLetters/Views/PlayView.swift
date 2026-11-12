import SwiftUI

struct PlayView: View {
    @EnvironmentObject var model: GameModel
    @Environment(\.scenePhase) private var scene
    @StateObject private var camera = CameraModel()
    @State private var entry = ""
    @State private var confirmEnd = false
    @State private var expanded = false

    private var cameraWanted: Bool { model.screen == .play && model.phase != .review && model.phase != .finished && scene == .active }

    var body: some View {
        if let game = model.game {
            VStack(spacing: 0) {
                topBar(game)
                ScrollView {
                    VStack(spacing: 16) {
                        if game.phase == .review {
                            ReviewPanel(entry: $entry)
                        } else {
                            cameraCard(game)
                            TurnWords(entry: $entry)
                            detected(game)
                            Card { WordEntry(text: $entry) }
                        }
                        Scoreboard()
                        Text(model.text("Aseta sanat pöydälle vaaka- tai pystysuoraan, myös sivuttain käännettynä. ◇ korvaa yhden kirjaimen (0 p). Sama sana pisteytetään kerran pelissä.",
                                        "Lay words on the table horizontally or vertically, rotated boards work too. ◇ replaces one letter (0 p). Each word scores once per game."))
                            .font(.caption).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 18).padding(.bottom, 110)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .safeAreaInset(edge: .bottom) { if game.phase != .review { controls(game) } }
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
            VStack { Button(model.text("Alkuun", "Home")) { model.screen = .welcome } }
        }
    }

    private func syncCamera() {
        if cameraWanted { camera.start(language: model.game?.rules.language ?? model.language) } else { camera.stop() }
    }

    // MARK: Top bar

    private func topBar(_ game: Game) -> some View {
        HStack(spacing: 12) {
            Avatar(name: game.currentPlayer?.name ?? "", index: game.current, size: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(game.currentPlayer?.name ?? "").font(.system(.title3).weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
                Text(game.rules.rounds > 0
                     ? model.text("Kierros \(game.round)/\(game.rules.rounds)", "Round \(game.round)/\(game.rules.rounds)")
                     : model.text("Kierros \(game.round)", "Round \(game.round)"))
                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
            }
            Spacer()
            if game.phase != .review {
                TimerRing(remaining: game.remaining, total: game.rules.turnSeconds, running: game.phase == .running, size: 58)
            }
            Menu {
                Button(model.text("Alkuun (peli tallessa)", "Home (game is saved)"), systemImage: "house") { model.leaveToHome() }
                Button(model.text("Lopeta peli", "End game"), systemImage: "flag.checkered", role: .destructive) { confirmEnd = true }
            } label: {
                Image(systemName: "ellipsis.circle").font(.title2)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
    }

    // MARK: Camera

    private func cameraCard(_ game: Game) -> some View {
        ZStack {
            CameraPreview(session: camera.session).overlay { WordOverlay(words: camera.words) }
            VStack {
                HStack {
                    Label(model.text("\(camera.words.filter(\.isStable).count) sanaa näkyvissä", "\(camera.words.filter(\.isStable).count) words in view"), systemImage: "viewfinder")
                        .font(.caption.weight(.bold)).padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.black.opacity(0.45)).clipShape(Capsule())
                    Spacer()
                    if camera.torchAvailable {
                        Button { camera.toggleTorch() } label: {
                            Image(systemName: camera.torchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                                .font(.subheadline.bold()).frame(width: 34, height: 34).background(.black.opacity(0.45)).clipShape(Circle())
                        }
                    }
                }
                Spacer()
            }.padding(10)
            if game.phase != .running && !camera.permissionDenied {
                VStack(spacing: 6) {
                    Image(systemName: game.phase == .ready ? "play.circle.fill" : "pause.circle.fill").font(.system(size: 44))
                    Text(game.phase == .ready ? model.text("Paina Aloita – kello käynnistyy", "Press Start – the clock begins") : model.text("Tauko", "Paused"))
                        .font(.headline)
                }
                .padding(18).background(.black.opacity(0.55)).clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            if camera.permissionDenied {
                VStack(spacing: 10) {
                    Image(systemName: "camera.fill").font(.largeTitle)
                    Text(model.text("Salli kamera iPhonen asetuksista. Sanat voi myös kirjoittaa käsin.", "Allow the camera in iPhone Settings. You can also type words."))
                        .multilineTextAlignment(.center).font(.subheadline)
                    Button(model.text("Avaa asetukset", "Open Settings")) {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }.buttonStyle(.borderedProminent)
                }
                .padding().background(.black.opacity(0.6)).clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous)).padding()
            }
            if let toast = model.toast {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                        Text(toast.tiles).font(.system(.headline).weight(.semibold)).tracking(1)
                        Text("+\(toast.points)").font(.headline.bold())
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Theme.green).foregroundStyle(Theme.ink).clipShape(Capsule())
                    .padding(.bottom, 12)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(height: expanded ? 460 : 330)
        .background(.black)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            Button { withAnimation(.spring(duration: 0.3)) { expanded.toggle() } } label: {
                Image(systemName: expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .font(.caption.bold()).frame(width: 32, height: 32).background(.black.opacity(0.45)).clipShape(Circle())
            }.padding(10)
        }
        .overlay(alignment: .bottomLeading) {
            if !camera.message.isEmpty { Text(camera.message).font(.caption2).padding(6).background(.black.opacity(0.5)).clipShape(Capsule()).padding(10) }
        }
        .foregroundStyle(.white)   // everything drawn over the camera image stays readable in light mode
        .animation(.spring(duration: 0.3), value: model.toast)
    }

    // MARK: Controls

    private func controls(_ game: Game) -> some View {
        HStack(spacing: 12) {
            Button { model.toggle() } label: {
                Label(game.phase == .running ? model.text("Tauko", "Pause") : game.phase == .paused ? model.text("Jatka", "Resume") : model.text("Aloita", "Start"),
                      systemImage: game.phase == .running ? "pause.fill" : "play.fill")
            }
            .buttonStyle(PrimaryButton(color: game.phase == .running ? Theme.surfaceHigh : Theme.accent, foreground: game.phase == .running ? Theme.text : Theme.ink))
            Button { model.finishTurnEarly() } label: { Label(model.text("Valmis", "Done"), systemImage: "checkmark") }
                .buttonStyle(PrimaryButton(color: Theme.green))
                .frame(maxWidth: 150)
        }
        .padding(.horizontal, 18).padding(.top, 10).padding(.bottom, 6)
        .background(.bar)
    }

    // MARK: Camera list

    @ViewBuilder private func detected(_ game: Game) -> some View {
        let unsaved = camera.words.filter { status(of: $0.word) != .saved }
        if !unsaved.isEmpty {
            Card {
                SectionTitle(text: model.text("Kamera näkee", "Camera sees"), trailing: model.text("napauta korjataksesi", "tap to fix"))
                ForEach(unsaved) { found in
                    let state = status(of: found.word)
                    Button { entry = found.word } label: {
                        HStack(spacing: 10) {
                            Image(systemName: found.direction == .vertical ? "arrow.down" : found.rotation == 0 ? "arrow.right" : "rotate.right")
                                .font(.caption.bold()).foregroundStyle(Theme.muted).frame(width: 16)
                            Text(found.word).font(.system(.title3).weight(.semibold)).tracking(1).foregroundStyle(Theme.text)
                            Text(model.text("\(found.letterCount) kirj.", "\(found.letterCount) lett.")).font(.caption).foregroundStyle(Theme.muted)
                            Spacer()
                            Text(state.label(model)).font(.caption.weight(.bold)).foregroundStyle(state.color)
                            if !found.isStable { ProgressView().controlSize(.mini).tint(Theme.muted) }
                        }
                    }
                }
            }
        } else if game.phase == .running && game.pending.isEmpty {
            Text(model.text("Osoita kameralla laattoja. Löydetyt sanat tallentuvat tähän automaattisesti.", "Point the camera at the tiles. Found words are saved here automatically."))
                .font(.footnote).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
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
        case .valid, .choose: return Theme.accent
        case .played, .tooShort: return Theme.muted
        case .notFound: return Theme.coral
        }
    }
    @MainActor func label(_ model: GameModel) -> String {
        switch self {
        case .saved: return model.text("tallennettu ✓", "saved ✓")
        case .played: return model.text("jo pelattu", "already played")
        case .valid: return model.text("löytyy", "found")
        case .choose: return model.text("valitse jokeri", "choose joker")
        case .notFound: return model.text("ei sanastossa", "not in list")
        case .tooShort: return ""
        }
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
                let suffix: String = status == .saved ? " ✓" : (status == .notFound ? " ?" : " +\(TileRules.points(found.word))")
                RoundedRectangle(cornerRadius: 6).stroke(status.color, lineWidth: found.isStable ? 3 : 1.5)
                    .frame(width: rect.width * w + 6, height: rect.height * h + 6)
                    .position(x: ox + rect.midX * w, y: oy + (1 - rect.midY) * h)
                Text(found.word + suffix)
                    .font(.caption.weight(.semibold)).padding(.horizontal, 6).padding(.vertical, 3)
                    .background(status.color).foregroundStyle(Theme.ink)
                    .clipShape(Capsule())
                    .position(x: max(44, min(geometry.size.width - 44, ox + rect.midX * w)), y: max(14, oy + (1 - rect.maxY) * h - 14))
            }
        }
        .allowsHitTesting(false)
    }
}
