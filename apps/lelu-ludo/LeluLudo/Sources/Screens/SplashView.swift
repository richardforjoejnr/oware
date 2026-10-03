import SwiftUI

/// The opening card: LELU LUDO and the owner's line, "Play Ghana. Play Together.", over the board
/// in its box. Tap to go straight on.
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
            BoardFrame { BoardCanvas(rules: .ghanaClassic) }
                .padding(.horizontal, 28)
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

    /// Dark wood lit from above, as in the owner's splash art.
    static var background: some View {
        ZStack {
            Palette.night
            Image(Art.darkWood).resizable(resizingMode: .tile).opacity(0.6)
            RadialGradient(colors: [Color(red: 0.55, green: 0.33, blue: 0.16).opacity(0.75), .clear],
                           center: .init(x: 0.5, y: 0.18), startRadius: 10, endRadius: 420)
        }
    }
}
