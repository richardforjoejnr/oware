import SwiftUI
import UIKit

/// A board "look": the same carved board and seeds, lit and tinted differently, on its own
/// backdrop. Heritage is the reference; the others are variations on it. Some are part of the
/// one-time purchase.
struct BoardTheme: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let tagline: String
    /// Multiplied into the wood texture (white = untouched).
    let woodTint: (r: CGFloat, g: CGFloat, b: CGFloat)
    /// 0 = texture only, 1 = flat tint colour.
    let tintStrength: CGFloat
    let rimOpacity: CGFloat
    let backgroundTop: Color
    let backgroundBottom: Color
    let requiresPurchase: Bool

    static func == (lhs: BoardTheme, rhs: BoardTheme) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var uiTint: UIColor { UIColor(red: woodTint.r, green: woodTint.g, blue: woodTint.b, alpha: 1) }

    static let heritage = BoardTheme(
        id: "heritage", name: "Heritage", tagline: "Osese, redwood and black dye",
        woodTint: (1, 1, 1), tintStrength: 0, rimOpacity: 0.85,
        backgroundTop: Color(red: 0.06, green: 0.04, blue: 0.03), backgroundBottom: Color(red: 0.06, green: 0.04, blue: 0.03),
        requiresPurchase: false)

    static let evening = BoardTheme(
        id: "evening", name: "Evening", tagline: "Lamplight after the market",
        woodTint: (1.0, 0.86, 0.66), tintStrength: 0.18, rimOpacity: 0.85,
        backgroundTop: Color(red: 0.10, green: 0.06, blue: 0.04), backgroundBottom: Color(red: 0.04, green: 0.03, blue: 0.02),
        requiresPurchase: false)

    static let ebony = BoardTheme(
        id: "ebony", name: "Ebony", tagline: "Black wood, quiet gold",
        woodTint: (0.45, 0.42, 0.42), tintStrength: 0.55, rimOpacity: 0.6,
        backgroundTop: Color(red: 0.03, green: 0.03, blue: 0.035), backgroundBottom: Color(red: 0.02, green: 0.02, blue: 0.025),
        requiresPurchase: true)

    static let coast = BoardTheme(
        id: "coast", name: "Cape Coast", tagline: "Sun-bleached wood by the sea",
        woodTint: (1.0, 0.92, 0.78), tintStrength: 0.35, rimOpacity: 0.7,
        backgroundTop: Color(red: 0.05, green: 0.10, blue: 0.13), backgroundBottom: Color(red: 0.03, green: 0.06, blue: 0.08),
        requiresPurchase: true)

    static let kente = BoardTheme(
        id: "kente", name: "Kente", tagline: "Gold on deep green",
        woodTint: (0.95, 0.80, 0.45), tintStrength: 0.28, rimOpacity: 0.9,
        backgroundTop: Color(red: 0.05, green: 0.12, blue: 0.08), backgroundBottom: Color(red: 0.03, green: 0.07, blue: 0.05),
        requiresPurchase: true)

    static let all: [BoardTheme] = [.heritage, .evening, .ebony, .coast, .kente]
    static func named(_ id: String) -> BoardTheme { all.first { $0.id == id } ?? .heritage }
}
