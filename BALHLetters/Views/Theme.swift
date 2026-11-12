import SwiftUI

/// BALH Letters design system: native iOS look. Semantic system colours, so light and dark mode both work.
enum Theme {
    static let ink = Color.white                                        // text on accent-coloured surfaces
    static let surface = Color(.secondarySystemGroupedBackground)       // cards (inset grouped style)
    static let surfaceHigh = Color(.tertiarySystemFill)                 // fields, chips
    static let line = Color(.separator)
    static let accent = Color.accentColor
    static let coral = Color(.systemRed)
    static let gold = Color(.systemYellow)
    static let green = Color(.systemGreen)
    static let text = Color.primary
    static let muted = Color.secondary
    static let tile = Color(red: 0.98, green: 0.97, blue: 0.94)
    static let tileInk = Color(red: 0.11, green: 0.11, blue: 0.12)
    static let tileEdge = Color(red: 0.80, green: 0.76, blue: 0.68)

    static let radius: CGFloat = 12
    static let gradient = Color(.systemGroupedBackground)
    static let accentGradient = Color.accentColor
}

// MARK: - Tiles

/// A letter tile with its point value, like the physical game.
struct TileView: View {
    let letter: Character
    var size: CGFloat = 44
    var highlighted = false
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Text(String(letter))
                .font(.system(size: size * 0.58, weight: .bold))
                .minimumScaleFactor(0.7).lineLimit(1)
                .frame(width: size, height: size)
                .foregroundStyle(letter == jokerSymbol ? Theme.coral : Theme.tileInk)
            if letter != jokerSymbol {
                Text("\(TileRules.points(String(letter)))")
                    .font(.system(size: size * 0.22, weight: .bold))
                    .foregroundStyle(Theme.tileInk.opacity(0.55))
                    .padding(size * 0.08)
            }
        }
        .background(highlighted ? Theme.gold : Theme.tile)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous))
        .shadow(color: Theme.tileEdge.opacity(0.9), radius: 0, y: max(2, size * 0.07))
        .shadow(color: .black.opacity(0.25), radius: 4, y: 3)
        .accessibilityLabel(String(letter))
    }
}

struct TileWord: View {
    let word: String
    var size: CGFloat = 26
    var body: some View {
        HStack(spacing: size * 0.14) {
            ForEach(Array(word.uppercased().enumerated()), id: \.offset) { TileView(letter: $0.element, size: size) }
        }
    }
}

/// Small pill: "KALA  +5", used for saved words.
struct WordChip: View {
    let word: PlayedWord
    var onRemove: (() -> Void)?
    var body: some View {
        HStack(spacing: 8) {
            Text(word.tiles).font(.system(.subheadline).weight(.semibold)).tracking(1).lineLimit(1).fixedSize()
            Text("+\(word.points)").font(.caption.bold()).foregroundStyle(Theme.green)
            if word.kind == .house { Image(systemName: "hand.raised.fill").font(.caption2).foregroundStyle(Theme.coral) }
            if let onRemove {
                Button(action: onRemove) { Image(systemName: "xmark").font(.caption2.bold()).foregroundStyle(Theme.muted) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Theme.surfaceHigh)
        .clipShape(Capsule())
        .foregroundStyle(Theme.text)
    }
}

// MARK: - Containers

struct Card<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }
}

struct SectionTitle: View {
    let text: String
    var trailing: String?
    var body: some View {
        HStack {
            Text(text.uppercased()).font(.footnote).foregroundStyle(Theme.muted)
            Spacer()
            if let trailing { Text(trailing).font(.footnote.weight(.semibold)).foregroundStyle(Theme.accent) }
        }
    }
}

/// Wraps its children onto as many lines as needed.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Controls

struct PrimaryButton: ButtonStyle {
    var color: Color = Theme.accent
    var foreground: Color = Theme.ink
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .lineLimit(2).minimumScaleFactor(0.75).multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 50)
            .foregroundStyle(foreground)
            .background(color.opacity(configuration.isPressed ? 0.8 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct GhostButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .lineLimit(2).minimumScaleFactor(0.75).multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 50)
            .foregroundStyle(Theme.accent)
            .background(Theme.accent.opacity(configuration.isPressed ? 0.25 : 0.15))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Segmented control with the same API everywhere.
struct ChipPicker<T: Hashable>: View {
    @Binding var selection: T
    let options: [(T, String)]
    var body: some View {
        Picker("", selection: $selection) {
            ForEach(options, id: \.0) { value, label in Text(label).tag(value) }
        }
        .pickerStyle(.segmented)
    }
}

struct DarkField: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12).frame(minHeight: 44)
            .background(Theme.surfaceHigh)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .foregroundStyle(Theme.text)
    }
}
extension View { func darkField() -> some View { modifier(DarkField()) } }

/// Circular countdown.
struct TimerRing: View {
    let remaining: Int
    let total: Int
    let running: Bool
    var size: CGFloat = 92
    var body: some View {
        let fraction = max(0, min(1, Double(remaining) / Double(max(total, 1))))
        let color = remaining <= 5 ? Theme.coral : Theme.accent
        ZStack {
            Circle().stroke(Theme.surfaceHigh, lineWidth: size * 0.09)
            Circle().trim(from: 0, to: fraction)
                .stroke(color, style: StrokeStyle(lineWidth: size * 0.09, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: running ? 1 : 0.25), value: remaining)
            Text(String(format: "%d:%02d", remaining / 60, remaining % 60))
                .font(.system(size: size * 0.26, weight: .bold).monospacedDigit())
                .foregroundStyle(remaining <= 5 && running ? Theme.coral : Theme.text)
        }
        .frame(width: size, height: size)
    }
}

struct Avatar: View {
    let name: String
    let index: Int
    var size: CGFloat = 36
    static let palette: [Color] = [.blue, .orange, .purple, .green, .pink, .teal]
    var body: some View {
        Text(String(name.trimmingCharacters(in: .whitespaces).first ?? "?").uppercased())
            .font(.system(size: size * 0.45, weight: .bold))
            .frame(width: size, height: size)
            .background(Self.palette[index % Self.palette.count])
            .foregroundStyle(Theme.ink)
            .clipShape(Circle())
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
