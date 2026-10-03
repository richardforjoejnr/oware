import LudoEngine
import SwiftUI

/// The board with its tokens. Tokens that can move are ringed in brass; tapping one plays it.
struct BoardView: View {
    @Environment(LudoSession.self) private var session

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let layout = BoardLayout(size: side)
            ZStack(alignment: .topLeading) {
                BoardCanvas(rules: session.state.rules)
                    .frame(width: side, height: side)
                ForEach(tokens, id: \.id) { t in
                    TokenView(color: t.color, movable: t.movable, kickChoice: t.kickChoice,
                              selected: t.color == session.state.toMove && session.selectedToken == t.token, size: layout.cell * 0.82)
                        // At least 44 pt to tap (the HIG minimum), though squares are smaller on a phone.
                        .frame(width: max(44, layout.cell), height: max(44, layout.cell))
                        .contentShape(Rectangle())
                        .position(position(of: t, layout))
                        // Movable tokens on top and the only ones that take taps, so a neighbour's
                        // larger target never swallows the tap meant for the token that can move.
                        .zIndex(t.movable ? 1 : 0)
                        .allowsHitTesting(t.movable)
                        .onTapGesture { Task { await session.tap(token: t.token) } }
                        .accessibilityElement()
                        .accessibilityLabel(t.label)
                        .accessibilityAddTraits(t.movable ? .isButton : [])
                        // The value says what the token can do, for VoiceOver and for UI tests alike.
                        .accessibilityValue(t.kickChoice ? "Can kick" : (t.movable ? "Can move" : ""))
                        .accessibilityHint(t.movable ? (t.kickChoice ? "Double tap to choose a move" : "Double tap to move") : "")
                        .accessibilityIdentifier("token-\(t.color.name.lowercased())-\(t.token)")
                }
                // The moves of the selected token, each a marker on the square it would end on.
                if let token = session.selectedToken {
                    ForEach(Array(session.choices(for: token).enumerated()), id: \.offset) { _, move in
                        if let end = session.path(for: move).last {
                            ChoiceMarker(title: Self.title(move), kick: move.kind != .forward && move.kind != .enter)
                                .position(layout.center(end))
                                .onTapGesture { Task { await session.play(move) } }
                                .accessibilityElement()
                                .accessibilityLabel(Self.title(move))
                                .accessibilityAddTraits(.isButton)
                                .accessibilityIdentifier("choice-\(move.kind.rawValue)")
                                .zIndex(3)
                        }
                    }
                }
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.35), value: session.state)
            .animation(.linear(duration: 0.12), value: session.motion)   // one square at a time
        }
        .aspectRatio(1, contentMode: .fit)
    }

    static func title(_ move: Move) -> String {
        switch move.kind {
        case .enter: "Come out"
        case .forward: move.to == Board.home ? "Go home" : "Move \(move.to - move.from)"
        case .backKick: "Back kick"
        case .sideKickForward, .sideKickBack: "Side kick"
        case .homeKick: "Home kick"
        case .walkOut: "Walk out"
        }
    }

    /// Where a token is drawn: on its path while it walks, else where it stands.
    private func position(of t: Placed, _ layout: BoardLayout) -> CGPoint {
        if let m = session.motion, m.color == t.color, m.token == t.token { return layout.center(m.cell) }
        return t.position(layout, cell: session.state.cell(of: t.color, token: t.token))
    }

    struct Placed {
        let color: PlayerColor
        let token: Int
        let progress: Int
        let movable: Bool
        let kickChoice: Bool
        let stackIndex: Int
        var id: String { "\(color.rawValue)-\(token)" }

        func position(_ layout: BoardLayout, cell: Board.Cell?) -> CGPoint {
            // Visitors in another colour's lane stand on that lane square.
            var p = (cell != nil && progress >= 0 && progress < Board.home) ? layout.center(cell!) : layout.position(color, token: token, progress: progress)
            // Tokens sharing a square fan out a little so each can be seen and tapped.
            if progress >= 0 && progress < Board.home && stackIndex > 0 {
                p.x += CGFloat(stackIndex) * layout.cell * 0.18
                p.y -= CGFloat(stackIndex) * layout.cell * 0.18
            }
            return p
        }

        var label: String {
            let place: String
            switch progress {
            case Board.yard: place = "in the yard"
            case Board.home: place = "home"
            case (Board.lastTrackProgress + 1)...: place = "in the home lane, \(Board.home - progress) from home"
            default: place = "\(progress) squares from start"
            }
            return "\(color.name) token \(token + 1), \(place)"
        }
    }

    private var tokens: [Placed] {
        let movable = Set(session.movableTokens)
        var seen: [String: Int] = [:]
        var out: [Placed] = []
        for color in session.state.players {
            for (i, p) in session.state.tokens(of: color).enumerated() {
                var stack = 0
                if p >= 0 && p < Board.home, let cell = session.state.cell(of: color, token: i) {
                    let key = "\(cell.column),\(cell.row)"
                    stack = seen[key, default: 0]
                    seen[key] = stack + 1
                }
                let canMove = color == session.state.toMove && movable.contains(i)
                out.append(Placed(color: color, token: i, progress: p, movable: canMove,
                                  kickChoice: canMove && session.hasKickChoice(i), stackIndex: stack))
            }
        }
        return out
    }
}

/// A turned-wood pawn seen from above (a drawn stand-in until the owner's token art).
struct TokenView: View {
    let color: PlayerColor
    let movable: Bool
    var kickChoice = false
    var selected = false
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Palette.color(color).opacity(0.75), Palette.color(color)],
                                     center: .init(x: 0.35, y: 0.3), startRadius: 1, endRadius: size * 0.6))
                .overlay(Circle().stroke(color == .black ? Palette.brass : .black.opacity(0.45), lineWidth: color == .black ? 2 : 1))
                .shadow(color: .black.opacity(0.35), radius: 2, y: 1.5)
            Circle().fill(.white.opacity(0.25)).frame(width: size * 0.28).offset(x: -size * 0.14, y: -size * 0.16)
            if movable {
                // Brass: can move. Red dashes: also has a kick to choose (back, side or home).
                Circle().stroke(kickChoice ? Palette.color(.red) : Palette.brass,
                                style: StrokeStyle(lineWidth: selected ? 4 : 3, dash: kickChoice ? [5, 3] : []))
                    .frame(width: size * 1.3, height: size * 1.3)
            }
        }
        .frame(width: size, height: size)
    }
}


/// A move the selected token can make, on the square it would end on.
struct ChoiceMarker: View {
    let title: String
    let kick: Bool

    var body: some View {
        Text(title)
            .font(.caption.weight(.bold))
            .padding(.horizontal, 8)
            .frame(minWidth: 44, minHeight: 44)
            .background(Capsule().fill(kick ? Palette.color(.red) : Palette.brass))
            .foregroundStyle(kick ? .white : Palette.night)
            .overlay(Capsule().stroke(.white.opacity(0.8), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.4), radius: 3, y: 2)
    }
}
