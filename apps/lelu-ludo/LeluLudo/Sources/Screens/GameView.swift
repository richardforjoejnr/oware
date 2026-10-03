import LudoEngine
import SwiftUI

/// A game: whose turn it is, the board, the die.
struct GameView: View {
    @Environment(LudoSession.self) private var session
    let goHome: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Button(action: goHome) {
                    Image(systemName: "chevron.left").font(.title2.weight(.semibold))
                        .frame(width: 44, height: 44)   // the whole square is the button, not just the icon
                        .contentShape(Rectangle())
                }
                    .accessibilityLabel("Home")
                    .accessibilityIdentifier("btn-home")
                Spacer()
                Text(status)
                    .font(.system(.title3, design: .serif).weight(.semibold))
                    .foregroundStyle(Palette.ivory)
                    .multilineTextAlignment(.trailing)
                    .accessibilityIdentifier("status")
            }
            .foregroundStyle(Palette.ivory)
            BoardView()
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 10).fill(Palette.wood))
            HStack(spacing: 18) {
                // One scoreboard for VoiceOver (and one target big enough for the audit), not a chip each.
                HStack(spacing: 18) {
                    ForEach(session.state.players, id: \.self) { color in
                        VStack(spacing: 4) {
                            Circle().fill(Palette.color(color)).frame(width: 18, height: 18)
                                .overlay(Circle().stroke(color == session.state.toMove ? Palette.brass : .clear, lineWidth: 3).padding(-4))
                            Text("\(session.state.homeCount(color))/4").font(.caption).foregroundStyle(Palette.ivory)
                        }
                    }
                }
                .frame(minHeight: 44)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(session.state.players.map { "\(name($0)): \(session.state.homeCount($0)) of 4 home" }.joined(separator: ". "))
                .accessibilityIdentifier("scoreboard")
                Spacer()
                DiceView()
            }
            Spacer(minLength: 0)
        }
        .padding()
        .background(Palette.night.ignoresSafeArea())
    }

    private func name(_ color: PlayerColor) -> String {
        switch session.setup.seat(color) {
        case .human: session.setup.seats.values.filter({ $0 == .human }).count > 1 ? color.name : "You"
        case let .computer(level): "\(color.name) (\(level.displayName))"
        }
    }

    private var status: String {
        let s = session.state
        if let w = s.winner { return name(w) == "You" ? "You win!" : "\(name(w)) wins" }
        if session.isComputerPlaying { return "\(name(s.toMove)) is playing…" }
        if s.pendingRoll != nil { return name(s.toMove) == "You" ? "Choose a token" : "\(name(s.toMove)): choose a token" }
        return name(s.toMove) == "You" ? "Your roll" : "\(name(s.toMove)) to roll"
    }
}
