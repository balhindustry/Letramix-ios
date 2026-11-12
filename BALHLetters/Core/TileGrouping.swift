import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// One piece of text the OCR read: a single tile letter, or several tiles read together.
struct TextFragment: Equatable {
    /// Upper-case letters and ◇ only.
    let text: String
    /// Normalised box, origin bottom-left (Vision convention), in the *upright* image.
    let box: CGRect
    let confidence: Float
}

enum WordDirection: String, Codable, Hashable {
    case horizontal, vertical
}

/// A word assembled from tiles on the table.
struct TileWordCandidate: Equatable, Identifiable {
    var id: String { "\(direction.rawValue):\(text)" }
    let text: String
    let box: CGRect
    let confidence: Float
    let direction: WordDirection
    /// Boxes of the individual tiles, left→right or top→bottom.
    let tiles: [CGRect]
    var letterCount: Int { text.count }
    var points: Int { TileRules.points(text) }
}

/// Turns loose OCR fragments into words. Pure geometry, so it is unit-tested on Linux.
///
/// Rules:
/// - Fragments whose centres share a baseline (within 45 % of the tile height) form a row.
/// - Inside a row, neighbours join when the gap is at most 1.25 tile heights; overlaps
///   larger than a quarter tile split the run (two separate stacks).
/// - The same is done for columns, so vertical words count too. A single tile that is
///   part of a longer horizontal word is not also reported as a 1-letter vertical "word".
/// - Multi-letter fragments (OCR already joined the tiles) are kept whole and may still
///   be extended by neighbouring single tiles.
enum TileGrouping {
    static let maxGapFactor: CGFloat = 1.25
    static let overlapFactor: CGFloat = 0.25
    static let lineFactor: CGFloat = 0.45

    static func words(from fragments: [TextFragment], minLength: Int = 2,
                      directions: [WordDirection] = [.horizontal, .vertical]) -> [TileWordCandidate] {
        var result: [String: TileWordCandidate] = [:]
        for word in directions.flatMap({ runs(fragments, direction: $0) }) {
            guard word.letterCount >= minLength else { continue }
            // A vertical word made of pieces that are themselves multi-letter horizontal reads is noise
            // (e.g. two stacked words "KALA" / "TALO" would otherwise become "KALATALO").
            if word.direction == .vertical, word.tiles.count < word.letterCount { continue }
            if let existing = result[word.id], existing.confidence >= word.confidence { continue }
            result[word.id] = word
        }
        return result.values.sorted { a, b in
            if a.box.midY != b.box.midY { return a.box.midY > b.box.midY }
            return a.box.minX < b.box.minX
        }
    }

    private static func runs(_ fragments: [TextFragment], direction: WordDirection) -> [TileWordCandidate] {
        // Vertical words are only built from single tiles; a horizontal read of several letters
        // cannot be a letter of a vertical word.
        let usable = direction == .horizontal ? fragments : fragments.filter { $0.text.count == 1 }
        guard !usable.isEmpty else { return [] }
        // Along = the reading axis, across = the line axis.
        func along(_ r: CGRect) -> (lo: CGFloat, hi: CGFloat) { direction == .horizontal ? (r.minX, r.maxX) : (r.minY, r.maxY) }
        func acrossMid(_ r: CGRect) -> CGFloat { direction == .horizontal ? r.midY : r.midX }
        func size(_ r: CGRect) -> CGFloat { direction == .horizontal ? r.height : r.width }

        var lines: [[TextFragment]] = []
        for fragment in usable.sorted(by: { acrossMid($0.box) > acrossMid($1.box) }) {
            if let index = lines.firstIndex(where: { line in
                let mid = line.map { acrossMid($0.box) }.reduce(0, +) / CGFloat(line.count)
                let height = line.map { size($0.box) }.min() ?? 0
                return abs(mid - acrossMid(fragment.box)) < min(height, size(fragment.box)) * lineFactor
            }) { lines[index].append(fragment) } else { lines.append([fragment]) }
        }

        var words: [TileWordCandidate] = []
        for line in lines {
            // Horizontal: left→right. Vertical: top→bottom, i.e. descending Y.
            let ordered = line.sorted { direction == .horizontal ? along($0.box).lo < along($1.box).lo : along($0.box).hi > along($1.box).hi }
            var run: [TextFragment] = []
            func flush() {
                guard let first = run.first else { return }
                let text = run.map(\.text).joined()
                let box = run.dropFirst().reduce(first.box) { $0.union($1.box) }
                words.append(TileWordCandidate(text: text, box: box, confidence: run.map(\.confidence).min() ?? 0,
                                               direction: direction, tiles: run.map(\.box)))
                run = []
            }
            for fragment in ordered {
                if let previous = run.last {
                    let gap: CGFloat
                    if direction == .horizontal { gap = along(fragment.box).lo - along(previous.box).hi }
                    else { gap = along(previous.box).lo - along(fragment.box).hi }
                    let tile = max(size(previous.box), size(fragment.box))
                    let overlapLimit = -min(direction == .horizontal ? previous.box.width : previous.box.height,
                                            direction == .horizontal ? fragment.box.width : fragment.box.height) * overlapFactor
                    if gap > tile * maxGapFactor || gap < overlapLimit { flush() }
                }
                run.append(fragment)
            }
            flush()
        }
        return words
    }

    /// Cleans one OCR string into tile letters: drops the small point numbers printed on tiles,
    /// unifies joker glyphs, upper-cases. "K1A1L2A1" → "KALA".
    static func letters(in raw: String) -> [String] {
        var pieces: [String] = []
        var current = ""
        for scalar in raw.uppercased().precomposedStringWithCanonicalMapping {
            switch scalar {
            case "◊", "♢", "◇", "*": current.append(jokerSymbol)
            case let c where c.isLetter && ("A"..."Z").contains(c) || "ÅÄÖ".contains(c): current.append(c)
            case let c where c.isNumber: continue            // tile point values
            default: if !current.isEmpty { pieces.append(current); current = "" }
            }
        }
        if !current.isEmpty { pieces.append(current) }
        return pieces
    }
}
