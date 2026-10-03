import Testing
@testable import LudoEngine

/// The squares a move passes through, for the app to animate it step by step instead of sliding in a
/// straight line across the board.
@Suite("Move paths")
struct PathTests {
    func touching(_ a: Board.Cell, _ b: Board.Cell) -> Bool { max(abs(a.column - b.column), abs(a.row - b.row)) == 1 }
    func yellow(_ t: Int) -> Int { GameState.progress(of: .yellow, atTrackIndex: t) }

    @Test("Forward: one square per pip, along the track, each next to the last")
    func forward() throws {
        var g = GameState(players: [.red, .yellow], rules: .classic, first: .red)
        g.place([.red: [10, -1, -1, -1]])
        g.roll(4)
        let path = g.path(for: try #require(g.legalMoves().first))
        #expect(path == (11...14).map { Board.cell(.red, progress: $0)! })
    }

    @Test("Back kick: backwards, square by square")
    func backKick() throws {
        var g = GameState(players: [.red, .yellow], rules: .ghanaClassic, first: .red)
        g.place([.red: [12, -1, -1, -1], .yellow: [yellow(7), -1, -1, -1]])
        g.roll(5)
        let path = g.path(for: try #require(g.legalMoves().first { $0.kind == .backKick }))
        #expect(path == (7...11).reversed().map { Board.cell(.red, progress: $0)! })
    }

    @Test("Side kick: by the roll, then one jump across the lane")
    func sideKick() throws {
        var g = GameState(players: [.red, .yellow], rules: .ghanaClassic, first: .red)
        g.place([.red: [5, -1, -1, -1], .yellow: [yellow(15), -1, -1, -1]])
        g.roll(2)
        let path = g.path(for: try #require(g.legalMoves().first { $0.kind == .sideKickForward }))
        #expect(path == [Board.cell(.red, progress: 6)!, Board.cell(.red, progress: 7)!, Board.track[15]])
    }

    @Test("Home kick: on to the entrance, then into the lane")
    func homeKick() throws {
        var g = GameState(players: [.red, .yellow], rules: .ghanaClassic, first: .red)
        g.place([.red: [8, -1, -1, -1], .yellow: [52, -1, -1, -1]])
        g.roll(5)
        let path = g.path(for: try #require(g.legalMoves().first { $0.kind == .homeKick }))
        #expect(path == [Board.track[9], Board.track[10], Board.track[11], Board.lane(.yellow)[0], Board.lane(.yellow)[1]])
    }

    @Test("Entering: straight onto the start square")
    func enter() throws {
        var g = GameState(players: [.red, .yellow], first: .red)
        g.roll(6)
        #expect(g.path(for: try #require(g.legalMoves().first)) == [Board.track[0]])
    }

    @Test("Every legal move's path in random games is connected and ends where the token lands",
          arguments: [RuleSet.ghanaClassic, .classic])
    func everyPath(rules: RuleSet) throws {
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<40 {
            var g = GameState(players: PlayerColor.allCases, rules: rules)
            var n = 0
            while !g.isOver && n < 3000 {
                n += 1
                g.roll(Int.random(in: 1...6, using: &rng))
                guard let move = g.legalMoves().randomElement(using: &rng) else { continue }
                let me = g.toMove
                let path = g.path(for: move)
                try #require(!path.isEmpty)
                let start = move.kind == .enter ? nil : g.cell(of: me, token: move.token)
                if let start {
                    // Steps are to a neighbouring square, except a side kick's jump across a lane.
                    for (a, b) in zip([start] + path, path) where !(move.kind == .sideKickForward || move.kind == .sideKickBack) || b != path.last {
                        try #require(touching(a, b) || (Board.lane(me).last == a && b == Board.centre) || b == Board.centre, "\(move): \(a) → \(b)")
                    }
                }
                try g.apply(move)
                try #require(path.last == g.cell(of: me, token: move.token), "\(move) ends where it lands")
            }
        }
    }
}
