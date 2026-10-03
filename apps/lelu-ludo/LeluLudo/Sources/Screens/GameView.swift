import LudoEngine
import SwiftUI

/// A game, on the sand table: a wooden status plaque, the board in its box, and the tray with the
/// players, the die and the cup.
struct GameView: View {
    @Environment(LudoSession.self) private var session
    let goHome: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                WoodCircleButton(systemImage: "chevron.left", action: goHome)
                    .accessibilityLabel("Home")
                    .accessibilityIdentifier("btn-home")
                StatusPlaque(status: status, line: session.log.last)
            }
            Spacer(minLength: 0)
            BoardFrame(plaque: false) { BoardView() }
            Spacer(minLength: 0)
            Tray()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Table())
        .onChange(of: session.log) { _, log in
            if let line = log.last { AccessibilityNotification.Announcement(line).post() }
        }
    }

    private func name(_ color: PlayerColor) -> String { session.name(color) }

    private var status: String {
        let s = session.state
        if let w = s.winner { return name(w) == "You" ? "You win!" : "\(name(w)) wins" }
        if session.isComputerPlaying { return "\(name(s.toMove)) is playing…" }
        if session.selectedToken != nil { return "Choose a move" }
        if s.pendingRoll != nil { return name(s.toMove) == "You" ? "Choose a token" : "\(name(s.toMove)): choose a token" }
        return name(s.toMove) == "You" ? "Your roll" : "\(name(s.toMove)) to roll"
    }
}

/// Whose turn it is, and what just happened, carved on a wooden plaque.
struct StatusPlaque: View {
    let status: String
    let line: String?

    var body: some View {
        VStack(spacing: 2) {
            Text(status)
                .font(.system(.title3, design: .serif).weight(.semibold))
                .foregroundStyle(Palette.ivory)
                .accessibilityIdentifier("status")
            // Kicks, three sixes, no move: what just happened.
            Text(line ?? " ")
                .font(.system(.footnote, design: .serif))
                .foregroundStyle(Color(red: 0.95, green: 0.80, blue: 0.45))
                .lineLimit(2)
                .accessibilityIdentifier("commentary")
                .accessibilityHidden(line == nil)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, minHeight: 56)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .woodPanel(corner: 14)
    }
}

/// The wooden tray under the board: each player (pawn, name, tokens home) and the dice.
struct Tray: View {
    @Environment(LudoSession.self) private var session

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(session.state.players, id: \.self) { color in
                    PlayerRow(color: color, name: session.name(color), home: session.state.homeCount(color),
                              toMove: color == session.state.toMove && !session.state.isOver)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // One scoreboard for VoiceOver, not a row each.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(session.state.players.map { "\(session.name($0)): \(session.state.homeCount($0)) of 4 home" }.joined(separator: ". "))
            .accessibilityIdentifier("scoreboard")
            DiceView()
        }
        .padding(12)
        .woodPanel(corner: 20)
    }
}

/// A player in the tray: their pawn, name and four marks for tokens home; brass when it is their turn.
struct PlayerRow: View {
    let color: PlayerColor
    let name: String
    let home: Int
    let toMove: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(Art.pawn(color)).resizable().scaledToFit().frame(height: 26)
            Text(name)
                .font(.system(.subheadline, design: .serif).weight(toMove ? .bold : .regular))
                .foregroundStyle(Palette.ivory)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 4)
            HStack(spacing: 3) {
                ForEach(0..<4, id: \.self) { i in
                    Circle()
                        .fill(i < home ? Palette.color(color) : .black.opacity(0.35))
                        .overlay(Circle().stroke(Palette.brass.opacity(0.7), lineWidth: 1))
                        .frame(width: 9, height: 9)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(toMove ? Palette.brass.opacity(0.28) : .clear))
        .overlay(Capsule().stroke(toMove ? Palette.brass : .clear, lineWidth: 1.5))
    }
}
