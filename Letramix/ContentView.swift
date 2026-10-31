import SwiftUI
import AVFoundation

struct ContentView: View {
    @EnvironmentObject var game: GameModel
    @Environment(\.scenePhase) private var scene
    @StateObject private var camera = CameraModel()
    @State private var manual = ""
    @State private var jokerPattern = ""
    @State private var correcting = false
    @State private var showingLicenses = false
    let purple = Color(red: 0.46, green: 0.36, blue: 0.82)
    let clock = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("LETRAMIX").font(.title2.bold()); Spacer(); if game.screen != .game { Picker("Language", selection: $game.language) { Text("FI").tag("fi"); Text("EN").tag("en") }.pickerStyle(.segmented).frame(width: 120) } }
                .padding().background(.white)
            ScrollView { VStack(spacing: 22) {
                switch game.screen { case .welcome: welcome; case .settings: settings; case .game: play }
            }.padding(22) }
        }.background(Color(red: 0.97, green: 0.96, blue: 0.94)).tint(purple)
        .onReceive(clock) { _ in game.tick() }
        .onChange(of: game.screen) { _, next in if next == .game { camera.start(language: game.language) } else { camera.stop() } }
        .onChange(of: scene) { _, phase in if phase != .active { game.pause(); camera.stop() } else if game.screen == .game { camera.start(language: game.language) } }
        .sheet(isPresented: $correcting) { NavigationStack { Form { TextField(game.text("Korjaa sana", "Correct word"), text: $manual).textInputAutocapitalization(.characters).autocorrectionDisabled(); wordStatus; jokerChoices; Button(game.text("Hyväksy pisteet", "Accept points")) { game.score(manual, pattern: jokerPattern); manual = ""; jokerPattern = ""; correcting = false }.disabled(!game.canScore(manual, pattern: jokerPattern)) }.navigationTitle(game.text("Tarkista sana", "Check word")).toolbar { Button(game.text("Sulje", "Close")) { correcting = false } } } }
        .sheet(isPresented: $showingLicenses) { NavigationStack { ScrollView { Text(notices).padding() }.navigationTitle("Licenses").toolbar { Button("OK") { showingLicenses = false } } } }
    }
    var notices: String { guard let url = Bundle.main.url(forResource: "NOTICES", withExtension: "txt") else { return "License file missing" }; return (try? String(contentsOf: url, encoding: .utf8)) ?? "License file unreadable" }
    var welcome: some View {
        VStack(spacing: 30) {
            Spacer(minLength: 50)
            HStack { ForEach(Array("LETRA"), id: \.self) { c in Text(String(c)).font(.title.bold()).frame(width: 48, height: 58).background(Color(red: 0.94, green: 0.87, blue: 0.71)).clipShape(RoundedRectangle(cornerRadius: 10)) } }
            Text(game.text("Sanoista syntyy peli.", "Let the words play.")).font(.largeTitle.bold()).multilineTextAlignment(.center)
            Text(game.text("Muodosta sanoja. Kamera lukee mukana.", "Make words. Let the camera follow along.")).foregroundStyle(.secondary)
            Button(game.text("Aloita peli →", "Start game →")) { game.screen = .settings }.buttonStyle(.borderedProminent).controlSize(.large)
            Text(game.text("1–6 pelaajaa · Suomi & englanti", "1–6 players · Finnish & English")).font(.footnote).foregroundStyle(.secondary)
            Button("Sanastot / Licenses") { showingLicenses = true }.font(.footnote)
        }
    }
    var settings: some View {
        VStack(alignment: .leading, spacing: 22) {
            Button(game.text("← Aloitusnäkymä", "← Home")) { game.screen = .welcome }
            Text(game.text("Pelin asetukset", "Game settings")).font(.largeTitle.bold())
            Stepper(game.text("Pelaajia", "Players") + ": \(game.playerCount)", value: $game.playerCount, in: 1...6)
            ForEach(0..<game.playerCount, id: \.self) { i in TextField(game.text("Pelaaja", "Player") + " \(i+1)", text: $game.names[i]).textFieldStyle(.roundedBorder) }
            Text(game.text("Aikaa per vuoro", "Time per turn")).font(.headline)
            Picker("Time", selection: $game.duration) { ForEach([30,60,90,120], id: \.self) { t in Text("\(t) s").tag(t) } }.pickerStyle(.segmented)
            Text(game.text("Vähintään 2 kirjainta · Pisteet kirjainlaattojen mukaan · ◇ = 0", "At least 2 letters · Tile values · ◇ = 0")).font(.footnote)
            if game.dictionaryError { Text(game.text("Sanastojen lataus epäonnistui.", "Word lists failed to load.")).foregroundStyle(.red) }
            Button(game.dictionaryReady ? game.text("Siirry peliin →", "Go to game →") : game.text("Ladataan sanastoja…", "Loading words…")) { game.begin() }.buttonStyle(.borderedProminent).controlSize(.large).disabled(!game.dictionaryReady)
        }.padding().background(.white).clipShape(RoundedRectangle(cornerRadius: 20))
    }
    var play: some View {
        VStack(spacing: 18) {
            HStack { Text(game.players.indices.contains(game.current) ? game.players[game.current].name : "").font(.title.bold()); Spacer(); Text(String(format: "%d:%02d", game.remaining/60, game.remaining%60)).font(.largeTitle.monospacedDigit().bold()).foregroundStyle(purple) }
            ZStack {
                CameraPreview(session: camera.session).overlay { wordOverlay }
                if camera.permissionDenied { VStack { Text(game.text("Salli kamera iPhonen asetuksista.", "Allow camera in iPhone Settings.")); Button(game.text("Avaa asetukset", "Open Settings")) { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } } }.padding().background(.ultraThinMaterial) }
            }.frame(height: 360).background(.black).clipShape(RoundedRectangle(cornerRadius: 20))
            if !camera.message.isEmpty { Text(camera.message).font(.footnote).foregroundStyle(.secondary) }
            HStack { Button(game.running ? game.text("Tauko", "Pause") : game.text("Aloita / jatka", "Start / resume")) { game.toggle() }.buttonStyle(.borderedProminent).disabled(game.remaining == 0); Button(game.text("Seuraava pelaaja", "Next player")) { game.next() }.buttonStyle(.bordered) }
            if game.remaining == 0 { Text(game.text("Aika loppui!", "Time’s up!")).font(.headline) }
            Text(game.text("Tunnistetut sanat", "Recognised words")).font(.headline)
            if camera.words.isEmpty { Text(game.text("Osoita selkeitä kirjaimia. Kamera lukee jatkuvasti.", "Point at clear letters. The camera reads continuously.")).font(.footnote).foregroundStyle(.secondary) }
            ForEach(camera.words) { found in
                HStack {
                    Button { manual = found.word; jokerPattern = found.word.contains("◇") ? found.word : ""; correcting = true } label: { VStack(alignment: .leading) { Text(found.word).font(.title3.bold()); Text(game.valid(found.word) ? game.text("Sana löytyy ✓", "Word found ✓") : game.text("Tarkista sana", "Check word")).font(.caption) } }
                    Spacer()
                    Button(game.used.contains(game.normalized(found.word)) ? "✓" : "+\(game.points(found.word))") { game.score(found.word) }.buttonStyle(.borderedProminent).disabled(!game.canScore(found.word))
                }.padding().background(.white).clipShape(RoundedRectangle(cornerRadius: 14))
            }
            HStack { TextField(game.text("Kirjoita tai korjaa sana", "Type or correct a word"), text: $manual).textFieldStyle(.roundedBorder).textInputAutocapitalization(.characters).autocorrectionDisabled(); Button("+\(game.points(jokerPattern.isEmpty ? manual : jokerPattern))") { game.score(manual, pattern: jokerPattern); manual = ""; jokerPattern = "" }.disabled(!game.canScore(manual, pattern: jokerPattern)) }
            wordStatus
            jokerChoices
            ForEach(game.players) { p in HStack { Text(p.name); Spacer(); Text("\(p.points)").bold() }.padding().background(.white).clipShape(RoundedRectangle(cornerRadius: 12)) }
            Text(game.text("Järjestä sana vaakasuoraan ja kirjaimet samaan suuntaan. Tarkista tunnistus ja hyväksy pisteet. ◇ korvaa yhden kirjaimen (0 p).", "Arrange a word horizontally with upright letters. Check recognition and accept points. ◇ replaces one letter (0 points).")).font(.caption).foregroundStyle(.secondary)
            Button(game.text("Lopeta peli ja avaa asetukset", "End game and open settings")) { game.pause(); game.screen = .settings }
        }
    }
    var wordOverlay: some View {
        GeometryReader { geometry in
            let h = min(geometry.size.height, geometry.size.width * 16 / 9)
            let w = h * 9 / 16
            let ox = (geometry.size.width - w) / 2
            let oy = (geometry.size.height - h) / 2
            ForEach(camera.words) { found in
                let rect = found.box
                let color: Color = game.valid(found.word) ? purple : .orange
                RoundedRectangle(cornerRadius: 4).stroke(color, lineWidth: 2)
                    .frame(width: rect.width * w, height: rect.height * h)
                    .position(x: ox + rect.midX * w, y: oy + (1 - rect.midY) * h)
                Text(found.word + (game.valid(found.word) ? " +\(game.points(found.word))" : " ?"))
                    .font(.caption2.bold()).padding(4).background(.white.opacity(0.9)).foregroundStyle(color)
                    .position(x: max(40, min(geometry.size.width - 40, ox + rect.midX * w)), y: max(12, oy + (1 - rect.maxY) * h - 12))
            }
        }.allowsHitTesting(false)
    }
    @ViewBuilder var jokerChoices: some View {
        if manual.contains("◇") {
            Text(game.text("Valitse jokerin muodostama sana:", "Choose the word represented by the joker:"))
            ForEach(game.matches(manual), id: \.self) { option in
                Button(option.uppercased()) { jokerPattern = manual; manual = option.uppercased() }
            }
        }
    }
    @ViewBuilder var wordStatus: some View { if !manual.isEmpty { Text(game.used.contains(game.normalized(manual)) ? game.text("Sana on jo pisteytetty.", "Word already scored.") : game.valid(manual) ? game.text("Sana löytyy ✓", "Word found ✓") : game.text("Ei löydy sanalistasta.", "Not found in word list.")).font(.caption) } }
}
