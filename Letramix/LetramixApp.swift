import SwiftUI

@main struct LetramixApp: App {
    @StateObject private var model = GameModel()
    var body: some Scene {
        WindowGroup { ContentView().environmentObject(model).preferredColorScheme(.light) }
    }
}
