import Foundation
@main struct TileRulesChecks {
    static func main() {
        for letter in "HUMNLOJ" { assert(TileRules.points(String(letter)) == 2) }
        for letter in "ÄVP" { assert(TileRules.points(String(letter)) == 3) }
        for letter in "GBF" { assert(TileRules.points(String(letter)) == 5) }
        assert(TileRules.points("T") == 1)
        assert(TileRules.points("Ö") == 4)
        assert(TileRules.points("Å") == 7)
        assert(TileRules.points("KALA") == 5)
        assert(TileRules.points("K◇LA") == 4)
        assert(TileRules.points("◇◊♢") == 0)
        assert(TileRules.points("äöå") == 14)
        assert(TileRules.points("A1 T1") == 2)
        print("Tile scoring checks passed")
    }
}
