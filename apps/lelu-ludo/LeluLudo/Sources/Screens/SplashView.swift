import SwiftUI

/// The opening card: LELU LUDO and the owner's line, "Play Ghana. Play Together.", over the board
/// in its box, on the launch screen's wood. Tap to go straight on.
struct SplashView: View {
    let done: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 20)
            VStack(spacing: 6) {
                Text("LELU\nLUDO")
                    .font(.custom("Didot", size: 76, relativeTo: .largeTitle))
                    .multilineTextAlignment(.center)
                    .lineSpacing(-8)
                    .foregroundStyle(Palette.ivory)
                    .shadow(color: Palette.brass.opacity(0.5), radius: 18)
                Text("Play Ghana. Play Together.")
                    .font(.system(.title3, design: .default).weight(.light))
                    .foregroundStyle(Palette.ivory.opacity(0.9))
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("splash")
            Image(Art.boardBox).resizable().scaledToFit()
                .shadow(color: .black.opacity(0.6), radius: 16, y: 12)
                .padding(.horizontal, 20)
                .accessibilityHidden(true)
            Spacer(minLength: 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Self.background.ignoresSafeArea())
        .contentShape(Rectangle())
        .onTapGesture(perform: done)
        .task {
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
