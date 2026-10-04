import LudoEngine
import SwiftUI

/// Colours: Ghana's flag for the players, wood and maple for the board, sand for the menu table.
enum Palette {
    static let night = Color(red: 0.06, green: 0.04, blue: 0.03)
    static let wood = Color(red: 0.23, green: 0.14, blue: 0.09)
    static let cream = Color(red: 0.93, green: 0.88, blue: 0.76)
    static let line = Color(red: 0.16, green: 0.11, blue: 0.07)
    /// The table under the menu (the owner's art: warm sand cloth).
    static let sand = Color(red: 0.87, green: 0.78, blue: 0.63)
    static let sandDeep = Color(red: 0.72, green: 0.58, blue: 0.42)
    static let brass = Color(red: 0.77, green: 0.59, blue: 0.15)
    /// Brass catching the light, and brass in shadow: the bevels on the menu's buttons and studs.
    static let brassLight = Color(red: 0.96, green: 0.82, blue: 0.45)
    static let brassDark = Color(red: 0.52, green: 0.37, blue: 0.08)
    static let ivory = Color(red: 0.92, green: 0.85, blue: 0.72)

    /// The colour painted on maple (multiplied over the grain): the flag colours, a touch deeper.
    static func paint(_ c: PlayerColor) -> Color {
        switch c {
        case .red: Color(red: 0.84, green: 0.10, blue: 0.12)
        case .yellow: Color(red: 0.98, green: 0.76, blue: 0.10)
        case .green: Color(red: 0.06, green: 0.48, blue: 0.24)
        case .black: Color(red: 0.16, green: 0.14, blue: 0.13)
        }
    }

    static func color(_ c: PlayerColor) -> Color {
        switch c {
        case .red: Color(red: 0xCE / 255, green: 0x11 / 255, blue: 0x26 / 255)
        case .yellow: Color(red: 0xFC / 255, green: 0xD1 / 255, blue: 0x16 / 255)
        case .green: Color(red: 0x00 / 255, green: 0x6B / 255, blue: 0x3F / 255)
        case .black: Color(red: 0.08, green: 0.07, blue: 0.06)
        }
    }
}
