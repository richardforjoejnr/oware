import Testing
@testable import LudoEngine

@Suite("Board")
struct BoardTests {
    @Test("The track is 52 different squares, each next to the one before, closing the loop")
    func trackIsALoop() {
        let t = Board.track
        #expect(t.count == 52)
        #expect(Set(t).count == 52)
        for i in 0..<t.count {
            let a = t[i], b = t[(i + 1) % t.count]
            // Straight steps, except the four inner corners where the track turns diagonally.
            #expect(max(abs(a.column - b.column), abs(a.row - b.row)) == 1, "\(a) → \(b)")
        }
        for cell in t { #expect((0...14).contains(cell.column) && (0...14).contains(cell.row)) }
    }

    @Test("Starts are a quarter of the way round from each other, on the arm beside each yard")
    func starts() {
        #expect(Board.track[Board.startIndex(.red)] == Board.Cell(1, 6))
        #expect(Board.track[Board.startIndex(.gold)] == Board.Cell(8, 1))
        #expect(Board.track[Board.startIndex(.black)] == Board.Cell(13, 8))
        #expect(Board.track[Board.startIndex(.green)] == Board.Cell(6, 13))
    }

    @Test("Each home lane starts beside the colour's last track square and ends beside the centre",
          arguments: PlayerColor.allCases)
    func lanes(color: PlayerColor) {
        let lane = Board.lane(color)
        #expect(lane.count == Board.laneLength)
        let last = Board.cell(color, progress: Board.lastTrackProgress)!
        func touching(_ a: Board.Cell, _ b: Board.Cell) -> Bool { abs(a.column - b.column) + abs(a.row - b.row) == 1 }
        #expect(touching(last, lane[0]), "\(color): \(last) → \(lane[0])")
        for i in 1..<lane.count { #expect(touching(lane[i - 1], lane[i])) }
        // The centre is the 3×3 home in the middle of the cross; each lane runs up to its edge.
        let centreBlock = (6...8).flatMap { c in (6...8).map { Board.Cell(c, $0) } }
        #expect(centreBlock.contains { touching(lane[lane.count - 1], $0) })
        #expect(!centreBlock.contains(lane[lane.count - 1]))
        #expect(Set(lane).isDisjoint(with: Set(Board.track)), "lanes are not track squares")
    }

    @Test("Every progress maps to a square; the yard to none; home to the centre")
    func cells() {
        for color in PlayerColor.allCases {
            #expect(Board.cell(color, progress: Board.yard) == nil)
            #expect(Board.cell(color, progress: Board.home) == Board.centre)
            let path = (0..<Board.home).compactMap { Board.cell(color, progress: $0) }
            #expect(Set(path).count == Board.home, "\(color) never visits a square twice")
        }
    }
}
