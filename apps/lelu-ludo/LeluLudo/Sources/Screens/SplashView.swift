import SwiftUI

/// The opening card: the owner's splash art (LELU LUDO, "Play Ghana. Play Together.", the board),
/// the same image the launch screen shows (LaunchScreen.storyboard), so launch runs straight into it
/// with no change of picture. Tap to go straight on.
struct SplashView: View {
    let done: () -> Void

    var body: some View {
        // Drawn exactly as the launch screen draws it: aspect-fill, edge to edge, centred.
        GeometryReader { geo in
            Image(Art.launchSplash)
                .resizable()
                .scaledToFill()
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
        }
        .ignoresSafeArea()
        .background(Palette.night.ignoresSafeArea())
        .accessibilityElement()
        .accessibilityLabel("Lelu Ludo. Play Ghana. Play Together.")
        .accessibilityIdentifier("splash")
        .contentShape(Rectangle())
        .onTapGesture(perform: done)
        .task {
            try? await Task.sleep(for: .seconds(2.2))
            done()
        }
    }
}
