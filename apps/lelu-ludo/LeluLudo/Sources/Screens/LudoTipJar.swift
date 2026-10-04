import SupportKit
import SwiftUI

/// The tip jar (SupportKit, as in Lelu Oware): optional tips that unlock nothing, in Lelu Ludo's wood
/// and brass. Opened from the Support tile and from Settings ▸ About.
struct LudoTipJar: View {
    var body: some View {
        TipJarView(title: "Support me",
                   message: "I make Lelu Ludo on my own. It is free, with no adverts and nothing locked. If it has given you a good game, buy me a drink or a meal. It helps me keep making it better.",
                   labels: ["A cold drink", "A plate of waakye", "A feast"],
                   details: ["a small thank-you", "lunch is on you", "for the true Ludo lovers"],
                   appName: "Lelu Ludo",
                   reviewURL: Links.writeReview,
                   style: TipJarStyle(accent: Palette.brassLight, text: Palette.ivory, secondaryText: Palette.ivory.opacity(0.75),
                                      background: Palette.wood,
                                      titleFont: .system(.title, design: .serif).weight(.bold),
                                      bodyFont: .system(.body, design: .serif)))
            .presentationDetents([.medium, .large])
            .presentationBackground(Palette.wood)
    }
}
