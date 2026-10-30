import SupportKit
import SwiftUI

/// "Support me": SupportKit's tip jar in Lelu Oware's wood and gold. Opened from the home screen
/// and from Settings. Tips are thanks and unlock nothing.
struct OwareTipJar: View {
    var body: some View {
        TipJarView(title: "Support me",
                   message: "I make Lelu Oware on my own. It is free, with no adverts and nothing locked. If it has given you a good game, buy me a drink or a meal. It helps me keep making it better.",
                   labels: ["A cold drink", "A plate of waakye", "A feast"],
                   details: ["a small thank-you", "lunch is on you", "for the true Oware lovers"],
                   appName: "Lelu Oware",
                   reviewURL: Links.writeReview,
                   style: TipJarStyle(accent: Theme.gold, text: Theme.ivory, secondaryText: Theme.ivoryDim, background: Theme.ember,
                                      titleFont: Theme.title(30).fixed, bodyFont: Theme.body(18).fixed))
            .presentationDetents([.medium, .large])
            .presentationBackground(Theme.ember)
            .onAppear { PlayerEvents.shared.tipJarViewed() }
    }
}
