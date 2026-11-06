import Foundation

/// Shared by camera results, manual entry and the scoreboard.
enum TileRules {
    static func points(_ word: String) -> Int {
        word.precomposedStringWithCanonicalMapping.uppercased().reduce(0) { total, letter in
            let value: Int
            switch letter {
            case "◇", "◊", "♢": value = 0
            case "H", "U", "M", "N", "L", "O", "J": value = 2
            case "Ä", "V", "P": value = 3
            case "Ö": value = 4
            case "G", "B", "F": value = 5
            case "Å": value = 7
            default: value = letter.isLetter ? 1 : 0
            }
            return total + value
        }
    }
}
