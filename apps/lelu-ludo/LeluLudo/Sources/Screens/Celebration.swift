import LudoEngine
import SwiftUI

/// The end of a game, over the board. A win: the winner's four pawns cheer before rays and sparkles,
/// over a green ribbon ("Wadi nkunim!"). A loss: your pawn is knocked over, over a red ribbon
/// ("Wa ri, wa ri!"). The words are set here, not painted in the art, so they can be corrected and
/// are read aloud. Then Play again or the menu.
struct GameOverCard: View {
    let outcome: Outcome
    let playAgain: () -> Void
    let mainMenu: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    @State private var hop = false
    @State private var spin = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.68)
                .ignoresSafeArea()
                .accessibilityHidden(true)
            VStack(spacing: 4) {
                ZStack {
                    if outcome.youWon {
                        Image(Art.glowRays).resizable().scaledToFit()
                            .frame(width: 300)
                            .rotationEffect(.degrees(spin ? 360 : 0))
                            .opacity(0.9)
                        Image(Art.glowSparkles).resizable().scaledToFit()
                            .frame(width: 320)
                            .opacity(shown ? 1 : 0)
                        HStack(spacing: -10) {
                            ForEach(0..<4, id: \.self) { i in
                                Image(Art.cheer(outcome.winner)).resizable().scaledToFit()
                                    .frame(height: 104)
                                    .offset(y: hop ? -12 : 0)
                                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.42).repeatForever().delay(Double(i) * 0.12), value: hop)
                            }
                        }
                        .offset(y: 26)
                    } else {
                        // Your pawn when you played alone; otherwise the colour that lost to the winner's.
                        Image(Art.toppled(outcome.yours ?? .red)).resizable().scaledToFit()
                            .frame(height: 120)
                            .rotationEffect(.degrees(shown || reduceMotion ? 0 : -50), anchor: .bottomTrailing)
                            .offset(y: 28)
                    }
                }
                .frame(height: 170)
                .accessibilityHidden(true)

                // The ribbon across the top of a wooden plaque holding the English and the buttons.
                VStack(spacing: 12) {
                    Text(outcome.meaning.uppercased())
                        .font(.system(.title3, design: .serif).weight(.bold))
                        .tracking(1)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Palette.brassLight)
                        .accessibilityHidden(true)
                    BrassButton(title: "Play again", systemImage: "arrow.counterclockwise", compact: true, action: playAgain)
                        .accessibilityIdentifier("btn-play-again")
                    Button(action: mainMenu) {
                        Label("Main menu", systemImage: "house.fill")
                            .font(.system(.body, design: .serif).weight(.semibold))
                            .foregroundStyle(Palette.ivory)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.brass.opacity(0.7), lineWidth: 1.5))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("btn-main-menu")
                }
                .padding(.horizontal, 20)
                .padding(.top, 56)
                .padding(.bottom, 20)
                .woodPanel(corner: 18)
                .overlay(alignment: .top) { ribbon.padding(.horizontal, -26).offset(y: -44) }
                .padding(.top, 30)
            }
            .frame(maxWidth: 340)
            .padding(.horizontal, 24)
            .scaleEffect(shown || reduceMotion ? 1 : 0.85)
            .opacity(shown ? 1 : 0)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("game-over")
        .onAppear {
            // A beat for the last token to settle, then the card.
            withAnimation(.spring(response: 0.45, dampingFraction: 0.7).delay(0.35)) { shown = true }
            guard !reduceMotion else { return }
            hop = true
            withAnimation(.linear(duration: 24).repeatForever(autoreverses: false)) { spin = true }
        }
    }

    /// The Twi on its ribbon, in the ribbon's band (the upper two thirds of the art).
    private var ribbon: some View {
        Image(outcome.youWon ? Art.ribbonGreen : Art.ribbonRed)
            .resizable()
            .scaledToFit()
            .overlay {
                GeometryReader { geo in
                    Text(outcome.phrase)
                        .font(.system(size: geo.size.height * 0.27, weight: .heavy, design: .serif))
                        .foregroundStyle(Color(red: 1, green: 0.95, blue: 0.80))
                        .shadow(color: .black.opacity(0.55), radius: 0, x: 1.5, y: 2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .frame(width: geo.size.width * 0.62)
                        .position(x: geo.size.width / 2, y: geo.size.height * 0.33)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("\(outcome.phrase) \(outcome.meaning)")
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("game-over-title")
    }
}

/// A person's token has reached home (yours, or each friend's in pass & play): a ring of light at its spot in the centre and "Eiii! Chale!"
/// in a speech bubble above it, for a moment. It never takes a tap, so play goes straight on.
struct HomeCheerView: View {
    let cheer: HomeCheer
    let layout: BoardLayout
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = Phase.hidden

    private enum Phase { case hidden, shown, gone }

    var body: some View {
        let spot = layout.position(cheer.color, token: cheer.token, progress: Board.home)
        let bubbleWidth = layout.cell * 5.2
        let bubbleHeight = bubbleWidth * 442 / 720
        // The bubble's tail is at its lower left, about a sixth of the way along: put it over the token,
        // keeping the bubble on the board.
        let x = min(max(spot.x + bubbleWidth * 0.33, bubbleWidth / 2), layout.size - bubbleWidth / 2)
        let y = max(spot.y - layout.cell * 0.6 - bubbleHeight / 2, bubbleHeight / 2)
        ZStack(alignment: .topLeading) {
            Image(Art.glowRing).resizable().scaledToFit()
                .frame(width: layout.cell * 2.2)
                .scaleEffect(phase == .hidden && !reduceMotion ? 0.4 : 1)
                .position(spot)
            Image(Art.bubbleYellow).resizable().scaledToFit()
                .frame(width: bubbleWidth)
                .overlay {
                    Text(Outcome.homePhrase)
                        .font(.system(size: bubbleHeight * 0.3, weight: .heavy, design: .serif))
                        .foregroundStyle(Color(red: 0.09, green: 0.27, blue: 0.13))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .frame(width: bubbleWidth * 0.8)
                        .offset(y: -bubbleHeight * 0.09)
                }
                .scaleEffect(phase == .hidden && !reduceMotion ? 0.3 : 1, anchor: .bottomLeading)
                .position(x: x, y: y)
                .accessibilityElement()
                .accessibilityLabel(cheer.spoken)
                .accessibilityIdentifier("home-cheer")
        }
        .opacity(phase == .shown ? 1 : 0)
        .allowsHitTesting(false)
        .task(id: cheer.id) {
            phase = .hidden
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { phase = .shown }
            try? await Task.sleep(for: .seconds(1.4))
            withAnimation(.easeOut(duration: 0.3)) { phase = .gone }
        }
    }
}
