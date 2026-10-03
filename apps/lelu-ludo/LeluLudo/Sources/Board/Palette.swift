import LudoEngine
import SwiftUI

/// Colours: Ghana's flag for the players, wood and cream for the board (until the owner's art).
enum Palette {
    static let night = Color(red: 0.06, green: 0.04, blue: 0.03)
    static let wood = Color(red: 0.23, green: 0.14, blue: 0.09)
    static let cream = Color(red: 0.93, green: 0.88, blue: 0.76)
    static let line = Color(red: 0.35, green: 0.25, blue: 0.17)
    static let brass = Color(red: 0.77, green: 0.59, blue: 0.15)
    static let ivory = Color(red: 0.92, green: 0.85, blue: 0.72)

    static func color(_ c: PlayerColor) -> Color {
        switch c {
        case .red: Color(red: 0xCE / 255, green: 0x11 / 255, blue: 0x26 / 255)
        case .yellow: Color(red: 0xFC / 255, green: 0xD1 / 255, blue: 0x16 / 255)
        case .green: Color(red: 0x00 / 255, green: 0x6B / 255, blue: 0x3F / 255)
        case .black: Color(red: 0.08, green: 0.07, blue: 0.06)
        }
    }
}
