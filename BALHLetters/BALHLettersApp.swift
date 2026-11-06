import SwiftUI

@main struct BALHLettersApp: App {
    @StateObject private var model = GameModel()
    var body: some Scene {
        WindowGroup { ContentView().environmentObject(model).preferredColorScheme(.light) }
    }
}
