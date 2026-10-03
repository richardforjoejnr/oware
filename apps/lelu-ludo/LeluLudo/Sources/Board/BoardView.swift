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
                    TokenView(color: t.color, movable: t.movable, size: layout.cell * 0.82)
                        // At least 44 pt to tap (the HIG minimum), though squares are smaller on a phone.
                        .frame(width: max(44, layout.cell), height: max(44, layout.cell))
                        .contentShape(Rectangle())
                        .position(t.position(layout))
                        // Movable tokens on top and the only ones that take taps, so a neighbour's
                        // larger target never swallows the tap meant for the token that can move.
                        .zIndex(t.movable ? 1 : 0)
                        .allowsHitTesting(t.movable)
                        .onTapGesture { Task { await session.play(token: t.token) } }
                        .accessibilityElement()
                        .accessibilityLabel(t.label)
                        .accessibilityAddTraits(t.movable ? .isButton : [])
                        .accessibilityHint(t.movable ? "Moves \(session.state.pendingRoll ?? 0)" : "")
                        .accessibilityIdentifier("token-\(t.color.name.lowercased())-\(t.token)")
                }
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.35), value: session.state)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    struct Placed {
        let color: PlayerColor
        let token: Int
        let progress: Int
        let movable: Bool
        let stackIndex: Int
        var id: String { "\(color.rawValue)-\(token)" }

        func position(_ layout: BoardLayout) -> CGPoint {
            var p = layout.position(color, token: token, progress: progress)
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
                if p >= 0 && p < Board.home, let cell = Board.cell(color, progress: p) {
                    let key = "\(cell.column),\(cell.row)"
                    stack = seen[key, default: 0]
                    seen[key] = stack + 1
                }
                out.append(Placed(color: color, token: i, progress: p,
                                  movable: color == session.state.toMove && movable.contains(i), stackIndex: stack))
            }
        }
        return out
    }
}

/// A turned-wood pawn seen from above (a drawn stand-in until the owner's token art).
struct TokenView: View {
    let color: PlayerColor
    let movable: Bool
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
                Circle().stroke(Palette.brass, lineWidth: 3).frame(width: size * 1.3, height: size * 1.3)
            }
        }
        .frame(width: size, height: size)
    }
}
