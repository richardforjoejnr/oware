import SwiftUI

/// The opening card: LELU LUDO and the owner's line, "Play Ghana. Play Together.", over the board
/// in its box, on the launch screen's wood. It is the launch screen, picture for picture (both come
/// from art/make_art.py), so there is no blank wood while the app starts. Tap to go straight on.
struct SplashView: View {
    /// Stays until tapped instead of moving on by itself (the UI test that checks it).
    var holds = false
    let done: () -> Void

    /// Where the splash content sits: exactly as the launch screen places it (LaunchScreen.storyboard:
    /// aspect-fit, 24 pt in from the sides and 60 pt from top and bottom of the screen), so the app
    /// opens onto the launch screen's own picture without a jump.
    static let inset = EdgeInsets(top: 60, leading: 24, bottom: 60, trailing: 24)

    var body: some View {
        ZStack {
            Self.background
            Image(Art.splashContent)
                .resizable()
                .scaledToFit()
                .padding(Self.inset)
        }
        .ignoresSafeArea()
        .accessibilityElement()
        .accessibilityLabel("Lelu Ludo. Play Ghana. Play Together.")
        .accessibilityIdentifier("splash")
        .contentShape(Rectangle())
        .onTapGesture(perform: done)
        .task {
            guard !holds else { return }
            try? await Task.sleep(for: .seconds(2.2))
            done()
        }
    }

    /// Dark wood lit from above: the same picture as the launch screen (LaunchScreen.storyboard), drawn
    /// the same way (aspect-fill), so launch runs into the splash with no black and no jump.
    static var background: some View {
        GeometryReader { geo in
            Image(Art.launchSplash)
                .resizable()
                .scaledToFill()
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
        }
        .background(Palette.night)
    }
}
