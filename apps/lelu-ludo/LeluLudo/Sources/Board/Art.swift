import LudoEngine

/// The owner's art in the asset catalog (built by art/make_art.py from art/source/). Every name the
/// app uses is here, so one test can prove each image is in the bundle.
enum Art {
    static func pawn(_ color: PlayerColor) -> String { "Pawn-\(color.name.lowercased())" }
    /// 1…6; the 6 shows the black star.
    static func die(_ value: Int) -> String { "Die-\(max(1, min(6, value)))" }
    /// The die before anyone has rolled: Ghana's flag.
    static let dieFlag = "Die-flag"
    static let diceCup = "DiceCup"
    static let boardPlaque = "BoardPlaque"
    static let woodGrain = "WoodGrain"
    static let maple = "Maple"
    static let darkWood = "DarkWood"
    static let menuTitle = "MenuTitle"
    static let tileStart = "Tile-start"
    static let tileFriends = "Tile-friends"
    static let tileSettings = "Tile-settings"

    static var all: [String] {
        PlayerColor.allCases.map(pawn) + (1...6).map(die)
            + [dieFlag, diceCup, boardPlaque, woodGrain, maple, darkWood, menuTitle, tileStart, tileFriends, tileSettings]
    }
}
