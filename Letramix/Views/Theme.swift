import SwiftUI

enum Theme {
    static let purple = Color(red: 0.46, green: 0.36, blue: 0.82)
    static let purpleDark = Color(red: 0.30, green: 0.22, blue: 0.62)
    static let cream = Color(red: 0.97, green: 0.96, blue: 0.94)
    static let tile = Color(red: 0.94, green: 0.87, blue: 0.71)
    static let tileEdge = Color(red: 0.80, green: 0.70, blue: 0.50)
    static let green = Color(red: 0.18, green: 0.62, blue: 0.38)
    static let orange = Color(red: 0.93, green: 0.52, blue: 0.16)
}

/// A wooden letter tile with its point value, like the physical game.
struct TileView: View {
    let letter: Character
    var size: CGFloat = 44
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Text(String(letter))
                .font(.system(size: size * 0.55, weight: .heavy, design: .rounded))
                .frame(width: size, height: size * 1.15)
                .foregroundStyle(letter == jokerSymbol ? Theme.purple : .black)
            Text("\(TileRules.points(String(letter)))")
                .font(.system(size: size * 0.2, weight: .bold))
                .foregroundStyle(.black.opacity(0.55))
                .padding(size * 0.07)
        }
        .background(Theme.tile)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.18))
        .overlay(RoundedRectangle(cornerRadius: size * 0.18).stroke(Theme.tileEdge, lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 1.5, y: 2)
        .accessibilityLabel(String(letter))
    }
}

struct TileWord: View {
    let word: String
    var size: CGFloat = 26
    var body: some View {
        HStack(spacing: size * 0.12) {
            ForEach(Array(word.uppercased().enumerated()), id: \.offset) { TileView(letter: $0.element, size: size) }
        }
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }
}

struct PrimaryButton: ButtonStyle {
    var color: Color = Theme.purple
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(.white)
            .background(color.opacity(configuration.isPressed ? 0.8 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

extension WordKind {
    @MainActor func label(_ model: GameModel) -> String {
        switch self {
        case .dictionary: return model.text("sanastossa", "in word list")
        case .inflected: return model.text("taivutusmuoto", "inflected form")
        case .house: return model.text("hyväksytty käsin", "accepted by hand")
        }
    }
}
