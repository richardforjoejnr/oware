import LudoEngine

/// The owner's art in the asset catalog (built by art/make_art.py from art/source/). Every name the
/// app uses is here, so one test can prove each image is in the bundle.
enum Art {
    /// A pawn standing, seen from the side (the tray).
    static func pawn(_ color: PlayerColor) -> String { "Pawn-\(color.name.lowercased())" }
    /// The same pawn seen from above (the board, which is seen from above, as in Lelu Oware).
    static func pawnTop(_ color: PlayerColor) -> String { "PawnTop-\(color.name.lowercased())" }
    /// 1…6; the 6 shows the black star.
    static func die(_ value: Int) -> String { "Die-\(max(1, min(6, value)))" }
    /// The die before anyone has rolled: Ghana's flag.
    static let dieFlag = "Die-flag"
    static let diceCup = "DiceCup"
    static let boardPlaque = "BoardPlaque"
    static let woodGrain = "WoodGrain"
    static let maple = "Maple"
    static let darkWood = "DarkWood"
    static let darkWoodAcross = "DarkWoodAcross"
    static let linen = "Linen"
    /// The boxed board in three-quarter view, the menu's centrepiece.
    static let boardBox = "BoardBox"
    static let menuTitle = "MenuTitle"
    /// The owner's splash art, full screen; also the launch screen's image (LaunchScreen.storyboard).
    static let launchSplash = "LaunchSplash"
    /// The splash's title, line and board on nothing, over LaunchSplash at launch and in SplashView.
    static let splashContent = "SplashContent"
    static let tileStart = "Tile-start"
    static let tileFriends = "Tile-friends"
    static let tileSettings = "Tile-settings"
    /// Made from the menu art's Online tile: an open book on the blue disc (art/make_art.py).
    static let tileLearn = "Tile-learn"
    /// For the tip jar (release stage).
    static let tileSupport = "Tile-support"

    static var all: [String] {
        PlayerColor.allCases.map(pawn) + PlayerColor.allCases.map(pawnTop) + (1...6).map(die)
            + [dieFlag, diceCup, boardPlaque, woodGrain, maple, darkWood, darkWoodAcross, linen, boardBox, menuTitle, launchSplash, splashContent, tileStart, tileFriends, tileSettings, tileLearn, tileSupport]
    }
}
