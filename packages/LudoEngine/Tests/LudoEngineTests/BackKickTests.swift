import Testing
@testable import LudoEngine

/// The back kick, edge by edge (GAME_PLAN.md, "Back kick"): a token on the track may move back exactly
/// the roll onto a lone opponent on the track and kick it to its yard, instead of moving forwards.
/// Never back past its own start, never through a wall, never onto a safe square or a pair; a kick
/// earns another roll (with that rule), a 6 always does.
@Suite("Back kick")
struct BackKickTests {
    /// A colour's progress at a track square.
    private func at(_ color: PlayerColor, _ trackIndex: Int) -> Int { GameState.progress(of: color, atTrackIndex: trackIndex) }

    private func game(_ placed: [PlayerColor: [Int]], rules: RuleSet = .ghana, players: [PlayerColor] = [.red, .yellow],
                      toMove: PlayerColor = .red, visits: [PlayerColor: [Move.Visit?]] = [:]) -> GameState {
        GameState.arranged(players: players, rules: rules, toMove: toMove, tokens: placed, visits: visits)
    }

    private func backKicks(_ g: GameState) -> [Move] { g.legalMoves().filter { $0.kind == .backKick } }

    @Test("Only the exact roll: an opponent 5 behind is kicked with a 5, and with no other roll")
    func exactDistance() {
        for roll in 1...5 {
            var g = game([.red: [12, -1, -1, -1], .yellow: [at(.yellow, 7), -1, -1, -1]])
            g.roll(roll)
            let kicks = backKicks(g)
            if roll == 5 {
                #expect(kicks == [Move(token: 0, kind: .backKick, from: 12, to: 7)])
            } else {
                #expect(kicks.isEmpty, "roll \(roll)")
            }
        }
    }

    @Test("The kicked token goes to its yard; the kicker stands on its square; the kick is announced")
    func kickedToYard() throws {
        var g = game([.red: [12, -1, -1, -1], .yellow: [at(.yellow, 7), at(.yellow, 30), -1, -1]])
        g.roll(5)
        let events = try g.apply(try #require(backKicks(g).first))
        #expect(g.tokens(of: .yellow) == [Board.yard, at(.yellow, 30), Board.yard, Board.yard], "only the token kicked")
        #expect(g.tokens(of: .red)[0] == 7)
        #expect(events.contains(.kicked(.yellow, token: 0, at: 7, by: .red)))
    }

    @Test("Backwards across the end of the track: green from track 2 back to track 49, square by square")
    func wrapsRoundTheTrack() throws {
        // Green starts at track 39, so track 2 is its progress 15 and track 49 its progress 10.
        var g = game([.green: [at(.green, 2), -1, -1, -1], .yellow: [at(.yellow, 49), -1, -1, -1]],
                     players: [.yellow, .green], toMove: .green)
        g.roll(5)
        let kick = try #require(backKicks(g).first)
        #expect(kick.from == 15 && kick.to == 10)
        #expect(g.path(for: kick) == [1, 0, 51, 50, 49].map { Board.track[$0] }, "back over track 0 and 51")
        try g.apply(kick)
        #expect(g.tokens(of: .yellow)[0] == Board.yard)
    }

    @Test("Never back past your own start; onto it, yes")
    func ownStart() {
        // Red on progress 3, yellow on track 50 (behind red's start): a 5 would go behind the start.
        var behind = game([.red: [3, -1, -1, -1], .yellow: [at(.yellow, 50), -1, -1, -1]])
        behind.roll(5)
        #expect(backKicks(behind).isEmpty, "not into the previous arm")
        // A 6 from progress 5 would also go behind the start.
        var six = game([.red: [5, -1, -1, -1], .yellow: [at(.yellow, 51), -1, -1, -1]])
        six.roll(6)
        #expect(backKicks(six).isEmpty)
        // Exactly onto the start square (progress 0) is allowed while start squares are not safe.
        var onto = game([.red: [5, -1, -1, -1], .yellow: [at(.yellow, 0), -1, -1, -1]])
        onto.roll(5)
        #expect(backKicks(onto) == [Move(token: 0, kind: .backKick, from: 5, to: 0)])
    }

    @Test("Safe squares protect: no back kick onto a start or a star when those rules are on")
    func safeSquares() {
        // Yellow just out on its own start (track 13); red on track 18.
        let onStart: [PlayerColor: [Int]] = [.red: [18, -1, -1, -1], .yellow: [0, -1, -1, -1]]
        var open = game(onStart)
        open.roll(5)
        #expect(backKicks(open).count == 1, "start squares are not safe by default")
        var safe = game(onStart, rules: RuleSet(startSquaresSafe: true))
        safe.roll(5)
        #expect(backKicks(safe).isEmpty)
        // Red's own start, too.
        var redStart = game([.red: [5, -1, -1, -1], .yellow: [at(.yellow, 0), -1, -1, -1]], rules: RuleSet(startSquaresSafe: true))
        redStart.roll(5)
        #expect(backKicks(redStart).isEmpty)
        // A star (track 8).
        let onStar: [PlayerColor: [Int]] = [.red: [12, -1, -1, -1], .yellow: [at(.yellow, 8), -1, -1, -1]]
        var star = game(onStar)
        star.roll(4)
        #expect(backKicks(star).count == 1, "stars are not safe by default")
        var safeStar = game(onStar, rules: RuleSet(starSquaresSafe: true))
        safeStar.roll(4)
        #expect(backKicks(safeStar).isEmpty)
    }

    @Test("A pair cannot be kicked back, whether it is a wall or a safe stack")
    func pairsAreNotKicked() {
        let pair: [PlayerColor: [Int]] = [.red: [12, -1, -1, -1], .yellow: [at(.yellow, 7), at(.yellow, 7), -1, -1]]
        for stacking in [RuleSet.Stacking.wall, .safe] {
            var g = game(pair, rules: RuleSet(stacking: stacking))
            g.roll(5)
            #expect(backKicks(g).isEmpty, "\(stacking)")
        }
        // A lone token is kicked under every stacking rule.
        for stacking in RuleSet.Stacking.allCases {
            var g = game([.red: [12, -1, -1, -1], .yellow: [at(.yellow, 7), -1, -1, -1]], rules: RuleSet(stacking: stacking))
            g.roll(5)
            #expect(backKicks(g).count == 1, "\(stacking)")
        }
    }

    @Test("An opponent wall between blocks the back kick (walls only); a safe stack is passed")
    func wallsBetween() {
        // Yellow alone on track 7 and a yellow pair on track 9; red on 12 rolls 5.
        let yellowWall: [PlayerColor: [Int]] = [.red: [12, -1, -1, -1], .yellow: [at(.yellow, 7), at(.yellow, 9), at(.yellow, 9), -1]]
        var wall = game(yellowWall, rules: RuleSet(stacking: .wall))
        wall.roll(5)
        #expect(backKicks(wall).isEmpty, "not through a wall")
        var safe = game(yellowWall, rules: RuleSet(stacking: .safe))
        safe.roll(5)
        #expect(backKicks(safe).count == 1, "a safe stack can be passed")
        // Another opponent's wall blocks too.
        var third = game([.red: [12, -1, -1, -1], .yellow: [at(.yellow, 7), -1, -1, -1], .black: [at(.black, 10), at(.black, 10), -1, -1]],
                         rules: RuleSet(stacking: .wall), players: [.red, .yellow, .black])
        third.roll(5)
        #expect(backKicks(third).isEmpty)
        // A wall right next to the target, or right next to the kicker, still lies between.
        for wallAt in [8, 11] {
            var g = game([.red: [12, -1, -1, -1], .yellow: [at(.yellow, 7), at(.yellow, wallAt), at(.yellow, wallAt), -1]])
            g.roll(5)
            #expect(backKicks(g).isEmpty, "wall on \(wallAt)")
        }
    }

    @Test("Your own tokens between, alone or as a wall, never block your back kick")
    func ownTokensBetween() {
        var single = game([.red: [12, 10, -1, -1], .yellow: [at(.yellow, 7), -1, -1, -1]])
        single.roll(5)
        #expect(backKicks(single).map(\.token) == [0])
        var ownWall = game([.red: [12, 9, 9, -1], .yellow: [at(.yellow, 7), -1, -1, -1]])
        ownWall.roll(5)
        #expect(backKicks(ownWall).map(\.token) == [0])
    }

    @Test("The forward move is offered too, and choosing it kicks nobody")
    func forwardAlsoOffered() throws {
        var g = game([.red: [12, -1, -1, -1], .yellow: [at(.yellow, 7), -1, -1, -1]])
        g.roll(5)
        #expect(Set(g.legalMoves().map(\.kind)) == [.forward, .backKick])
        try g.apply(try #require(g.legalMoves().first { $0.kind == .forward }))
        #expect(g.tokens(of: .red)[0] == 17)
        #expect(g.tokens(of: .yellow)[0] == at(.yellow, 7), "the opponent stays")
        #expect(g.toMove == .yellow, "no kick, not a 6: the turn passes")
    }

    @Test("A back kick with a 6: entering is offered alongside, and the 6 rolls again")
    func withASix() throws {
        var g = game([.red: [12, -1, -1, -1], .yellow: [at(.yellow, 6), -1, -1, -1]])
        g.roll(6)
        #expect(Set(g.legalMoves().map(\.kind)) == [.enter, .forward, .backKick])
        let events = try g.apply(try #require(backKicks(g).first))
        #expect(events.contains(.rollAgain(.red)) && g.toMove == .red)
    }

    @Test("A back kick earns another roll, unless that rule is off")
    func bonusRoll() throws {
        var on = game([.red: [12, -1, -1, -1], .yellow: [at(.yellow, 7), -1, -1, -1]])
        on.roll(5)
        try on.apply(try #require(backKicks(on).first))
        #expect(on.toMove == .red && on.pendingRoll == nil, "another roll")
        var off = game([.red: [12, -1, -1, -1], .yellow: [at(.yellow, 7), -1, -1, -1]], rules: RuleSet(kickOrHomeEarnsRoll: false))
        off.roll(5)
        try off.apply(try #require(backKicks(off).first))
        #expect(off.toMove == .yellow)
    }

    @Test("A third 6 undoes the turn's back kick: the kicked token comes back to its square")
    func threeSixesUndo() throws {
        var g = game([.red: [12, 30, -1, -1], .yellow: [at(.yellow, 6), -1, -1, -1]])
        g.roll(6)
        try g.apply(try #require(backKicks(g).first))
        #expect(g.tokens(of: .yellow)[0] == Board.yard)
        g.roll(6)
        try g.apply(try #require(g.legalMoves().first { $0.token == 1 && $0.kind == .forward }))
        let events = g.roll(6)
        #expect(events.contains(.threeSixes(.red)))
        #expect(g.tokens(of: .red) == [12, 30, -1, -1], "everything this turn undone")
        #expect(g.tokens(of: .yellow)[0] == at(.yellow, 6), "the kicked token is back")
        #expect(g.toMove == .yellow)
    }

    @Test("Only from the track: not from the home lane, and not by a visitor in another lane")
    func onlyFromTheTrack() {
        // Red on its lane's first square (progress 51); yellow on red's progress 50 square; a 1.
        var lane = game([.red: [51, -1, -1, -1], .yellow: [at(.yellow, Board.trackIndex(.red, progress: 50)), -1, -1, -1]])
        lane.roll(1)
        #expect(backKicks(lane).isEmpty, "a token in its home lane never steps back out")
        // Red visiting yellow's lane (after a home kick), yellow tokens behind its entrance.
        let entrance = Board.entranceIndex(.yellow)   // track 11
        var visitor = game([.red: [at(.red, entrance), -1, -1, -1], .yellow: [at(.yellow, entrance - 2), -1, -1, -1]],
                           visits: [.red: [Move.Visit(owner: .yellow, depth: 1), nil, nil, nil]])
        visitor.roll(2)
        #expect(backKicks(visitor).isEmpty, "a visitor only walks out")
    }

    @Test("Only tokens on the track can be kicked back: not a visitor in a lane, not a colour not playing")
    func onlyVictimsOnTheTrack() {
        // Yellow visiting black's lane: its progress is black's lane entrance (track 24), but it stands
        // in the lane. Red on track 29 rolls 5 (onto track 24).
        let entrance = Board.entranceIndex(.black)
        var g = game([.red: [29, -1, -1, -1], .yellow: [at(.yellow, entrance), -1, -1, -1]], players: [.red, .yellow, .black],
                     visits: [.yellow: [Move.Visit(owner: .black, depth: 2), nil, nil, nil]])
        g.roll(5)
        #expect(backKicks(g).isEmpty, "the visitor is in the lane, not on the track")
        // Green is not playing: its tokens are not on the board.
        var absent = game([.red: [12, -1, -1, -1], .green: [at(.green, 7), -1, -1, -1]])
        absent.roll(5)
        #expect(backKicks(absent).isEmpty)
    }

    @Test("From the last track square, before the lane")
    func fromTheLastTrackSquare() {
        var g = game([.red: [50, -1, -1, -1], .yellow: [at(.yellow, 45), -1, -1, -1]])
        g.roll(5)
        #expect(backKicks(g) == [Move(token: 0, kind: .backKick, from: 50, to: 45)])
    }

    @Test("Several tokens, several targets: each back kick is its own move")
    func severalTargets() {
        var g = game([.red: [12, 20, -1, -1], .yellow: [at(.yellow, 7), at(.yellow, 15), -1, -1]])
        g.roll(5)
        #expect(Set(backKicks(g)) == [Move(token: 0, kind: .backKick, from: 12, to: 7), Move(token: 1, kind: .backKick, from: 20, to: 15)])
        // Two of your tokens together (a wall) can each kick the same opponent.
        var pair = game([.red: [12, 12, -1, -1], .yellow: [at(.yellow, 7), -1, -1, -1]])
        pair.roll(5)
        #expect(backKicks(pair).map(\.token).sorted() == [0, 1])
    }

    @Test("A back kick and a back side kick from the same roll are different moves")
    func backKickAndBackSideKick() {
        // Random positions until both come up from one token; never one move listed twice.
        var rng = ReferenceTests.LCG(s: 99)
        var both = 0
        for _ in 0..<4000 {
            var g = GameState(players: [.red, .yellow, .black, .green])
            var placed: [PlayerColor: [Int]] = [:]
            for c in PlayerColor.allCases { placed[c] = (0..<4).map { _ in Int.random(in: -1...50, using: &rng) } }
            g.place(placed)
            g.roll(Int.random(in: 1...6, using: &rng))
            let moves = g.legalMoves()
            #expect(Set(moves).count == moves.count, "no move listed twice")
            for m in moves where m.kind == .backKick {
                if moves.contains(where: { $0.token == m.token && $0.kind == .sideKickBack }) { both += 1 }
            }
        }
        #expect(both > 0, "the case came up")
    }

    @Test("With the rule off there is never a back kick, whatever the position")
    func ruleOff() {
        var rng = ReferenceTests.LCG(s: 7)
        for rules in [RuleSet.classic, RuleSet(backKick: false)] {
            for _ in 0..<3000 {
                var g = GameState(players: [.red, .yellow, .black, .green], rules: rules)
                var placed: [PlayerColor: [Int]] = [:]
                for c in PlayerColor.allCases { placed[c] = (0..<4).map { _ in Int.random(in: -1...50, using: &rng) } }
                g.place(placed)
                g.roll(Int.random(in: 1...6, using: &rng))
                #expect(!g.legalMoves().contains { $0.kind == .backKick })
            }
        }
    }

    @Test("Every back kick offered in random positions obeys the rule exactly")
    func randomPositionsObeyTheRule() throws {
        var rng = ReferenceTests.LCG(s: 2026)
        var seen = 0
        for stacking in RuleSet.Stacking.allCases {
            for safe in [false, true] {
                let rules = RuleSet(stacking: stacking, startSquaresSafe: safe, starSquaresSafe: safe)
                for _ in 0..<1500 {
                    var g = GameState(players: [.red, .yellow, .black, .green], rules: rules)
                    var placed: [PlayerColor: [Int]] = [:]
                    for c in PlayerColor.allCases { placed[c] = (0..<4).map { _ in Int.random(in: -1...50, using: &rng) } }
                    g.place(placed)
                    let r = Int.random(in: 1...6, using: &rng)
                    g.roll(r)
                    guard g.pendingRoll != nil else { continue }
                    let me = g.toMove
                    for m in g.legalMoves() where m.kind == .backKick {
                        seen += 1
                        #expect(m.from - m.to == r && m.to >= 0 && m.from <= Board.lastTrackProgress)
                        let target = Board.trackIndex(me, progress: m.to)
                        let victims = g.occupants(at: target).filter { $0.color != me }
                        #expect(!victims.isEmpty && !g.isSafe(target))
                        // One token per square ("not allowed") never forms a pair in play; random positions can.
                        if stacking != .notAllowed {
                            #expect(Dictionary(grouping: victims, by: \.color).values.allSatisfy { $0.count == 1 }, "never a pair, \(stacking)")
                        }
                        var after = g
                        try after.apply(m)
                        for v in victims { #expect(after.tokens(of: v.color)[v.token] == Board.yard) }
                    }
                }
            }
        }
        #expect(seen > 100, "back kicks came up: \(seen)")
    }
}
