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
                              selected: t.color == session.state.toMove && session.selectedToken == t.token,
                              size: layout.cell * (t.progress == Board.yard ? 1.1 : 0.86))
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
                // The moves of the selected token: a brass ring on the square each would end on, and its
                // label beside it; labels for neighbouring squares are spread so none covers another.
                if let token = session.selectedToken {
                    let moves = session.choices(for: token).filter { session.path(for: $0).last != nil }
                    let ends = moves.map { layout.center(session.path(for: $0).last!) }
                    let labels = ChoiceMarker.spread(ends, titles: moves.map(Self.title), board: side)
                    ForEach(Array(moves.enumerated()), id: \.offset) { i, move in
                        Circle().stroke(Palette.brassLight, lineWidth: 2.5)
                            .frame(width: layout.cell * 0.95, height: layout.cell * 0.95)
                            .position(ends[i])
                            .allowsHitTesting(false)
                            .zIndex(2)
                        ChoiceMarker(title: Self.title(move), kick: move.kind != .forward && move.kind != .enter)
                            .position(labels[i])
                            .onTapGesture { Task { await session.play(move) } }
                            .accessibilityElement()
                            .accessibilityLabel(Self.title(move))
                            .accessibilityAddTraits(.isButton)
                            .accessibilityIdentifier("choice-\(move.kind.rawValue)")
                            .zIndex(3)
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

/// A turned-wood pawn seen from above, as the board is. A ring shows it can move; chosen, it lifts.
struct TokenView: View {
    let color: PlayerColor
    let movable: Bool
    var kickChoice = false
    var selected = false
    let size: CGFloat

    var body: some View {
        ZStack {
            if movable {
                // Brass: can move. Red dashes: also has a kick to choose (back, side or home).
                Circle().stroke(kickChoice ? Palette.color(.red) : Palette.brass,
                                style: StrokeStyle(lineWidth: selected ? 4 : 3, dash: kickChoice ? [5, 3] : []))
                    .frame(width: size * 1.28, height: size * 1.28)
            }
            Image(Art.pawnTop(color))
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                // Lifted when chosen: bigger, its shadow further off.
                .scaleEffect(selected ? 1.15 : 1)
                .shadow(color: .black.opacity(0.45), radius: selected ? 4 : 1.5, x: selected ? 2 : 1, y: selected ? 4 : 1.5)
        }
        .frame(width: size, height: size)
    }
}


/// A move the selected token can make, on the square it would end on.
struct ChoiceMarker: View {
    let title: String
    let kick: Bool

    /// About how much room a label takes (its pill is at least 44 × 44).
    static func size(_ title: String) -> CGSize { CGSize(width: max(44, 18 + CGFloat(title.count) * 7.5), height: 44) }

    /// Where each label goes: on its square, unless that would cover a label already placed; then a row
    /// up (or down, near the top edge), and again if need be. Pure, so it is tested without a screen.
    static func spread(_ ends: [CGPoint], titles: [String], board: CGFloat) -> [CGPoint] {
        var placed: [(CGPoint, CGSize)] = []
        for (end, title) in zip(ends, titles) {
            let size = size(title)
            func clashes(_ p: CGPoint) -> Bool {
                placed.contains { q, s in abs(q.x - p.x) < (s.width + size.width) / 2 + 4 && abs(q.y - p.y) < (s.height + size.height) / 2 + 4 }
            }
            let step = size.height + 6
            let direction: CGFloat = end.y - step < size.height / 2 ? 1 : -1   // down if there's no room above
            var p = end
            var tries = 0
            while clashes(p), tries < 4 { p.y += direction * step; tries += 1 }
            // Keep it on the board.
            p.x = min(max(p.x, size.width / 2), board - size.width / 2)
            p.y = min(max(p.y, size.height / 2), board - size.height / 2)
            placed.append((p, size))
        }
        return placed.map(\.0)
    }

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
