import SwiftUI

/// BALH Letters palette: deep ink navy, teal accent, coral highlights, cool paper background.
enum Theme {
    static let accent = Color(red: 0.00, green: 0.55, blue: 0.56)       // primary accent: teal
    static let ink = Color(red: 0.07, green: 0.16, blue: 0.29)   // ink navy
    static let paper = Color(red: 0.94, green: 0.96, blue: 0.98)        // background
    static let tile = Color.white
    static let tileEdge = Color(red: 0.07, green: 0.16, blue: 0.29)
    static let tileInk = Color(red: 0.07, green: 0.16, blue: 0.29)
    static let green = Color(red: 0.12, green: 0.64, blue: 0.42)
    static let coral = Color(red: 0.97, green: 0.42, blue: 0.33)       // coral
}

/// A flat letter tile with its point value.
struct TileView: View {
    let letter: Character
    var size: CGFloat = 44
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Text(String(letter))
                .font(.system(size: size * 0.55, weight: .heavy, design: .rounded))
                .frame(width: size, height: size * 1.15)
                .foregroundStyle(letter == jokerSymbol ? Theme.coral : Theme.tileInk)
            Text("\(TileRules.points(String(letter)))")
                .font(.system(size: size * 0.2, weight: .bold))
                .foregroundStyle(Theme.accent)
                .padding(size * 0.07)
        }
        .background(Theme.tile)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.18))
        .overlay(RoundedRectangle(cornerRadius: size * 0.18).stroke(Theme.tileEdge, lineWidth: max(1.5, size * 0.05)))
        .shadow(color: Theme.tileEdge.opacity(0.9), radius: 0, x: 0, y: max(2, size * 0.07))
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
    var color: Color = Theme.accent
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
