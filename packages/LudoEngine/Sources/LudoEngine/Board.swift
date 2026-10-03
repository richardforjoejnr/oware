/// The standard Ludo cross on a 15×15 grid (columns and rows counted from the top left).
///
/// Each colour's yard is a corner (red top left, then clockwise yellow, black, green). The shared track
/// is 52 squares around the cross; each colour enters it on its own start square and, after 51
/// squares, turns into its own 5-square home lane towards the centre, where its tokens finish.
///
/// A token's journey is counted from its own start: progress 0…50 on the track, 51…55 in the home
/// lane, 56 home. `-1` is the yard.
public enum Board {
    public static let trackLength = 52
    public static let laneLength = 5
    /// Progress of the last track square, before the home lane.
    public static let lastTrackProgress = trackLength - 2   // 50
    public static let home = lastTrackProgress + laneLength + 1   // 56
    public static let yard = -1
    public static let tokensPerPlayer = 4

    public struct Cell: Hashable, Sendable, Codable, CustomStringConvertible {
        public let column: Int
        public let row: Int
        public init(_ column: Int, _ row: Int) { self.column = column; self.row = row }
        public var description: String { "(\(column),\(row))" }
    }

    /// The 52 track squares clockwise, starting at red's start square.
    public static let track: [Cell] = {
        var cells: [Cell] = []
        func run(_ from: (Int, Int), _ to: (Int, Int)) {
            let dc = (to.0 - from.0).signum(), dr = (to.1 - from.1).signum()
            var c = from.0, r = from.1
            while true {
                cells.append(Cell(c, r))
                if c == to.0 && r == to.1 { break }
                c += dc; r += dr
            }
        }
        run((1, 6), (5, 6))      // red's start, along the left arm's top row
        run((6, 5), (6, 0))      // up the top arm's left column
        run((7, 0), (7, 0))
        run((8, 0), (8, 5))      // down its right column
        run((9, 6), (14, 6))     // along the right arm's top row
        run((14, 7), (14, 7))
        run((14, 8), (9, 8))     // back along its bottom row
        run((8, 9), (8, 14))     // down the bottom arm's right column
        run((7, 14), (7, 14))
        run((6, 14), (6, 9))     // up its left column
        run((5, 8), (0, 8))      // along the left arm's bottom row
        run((0, 7), (0, 7))
        run((0, 6), (0, 6))      // the square before red's start
        return cells
    }()

    /// Where each colour joins the track (its progress 0), as an index into `track`.
    public static func startIndex(_ color: PlayerColor) -> Int { color.rawValue * 13 }

    /// The track index for a colour's progress 0…50.
    public static func trackIndex(_ color: PlayerColor, progress: Int) -> Int {
        precondition((0...lastTrackProgress).contains(progress), "not on the track")
        return (startIndex(color) + progress) % trackLength
    }

    /// A colour's home lane, from the track inwards (progress 51…55): the middle row or column of
    /// the arm its yard sits beside, entered from the arm's outer end.
    public static func lane(_ color: PlayerColor) -> [Cell] {
        switch color.rawValue {
        case 0: (1...5).map { Cell($0, 7) }                 // top left: left arm, left to right
        case 1: (1...5).map { Cell(7, $0) }                 // top right: top arm, downwards
        case 2: (1...5).map { Cell(14 - $0, 7) }            // bottom right: right arm, right to left
        default: (1...5).map { Cell(7, 14 - $0) }           // bottom left: bottom arm, upwards
        }
    }

    public static let centre = Cell(7, 7)

    /// Where a token at `progress` stands (nil in the yard).
    public static func cell(_ color: PlayerColor, progress: Int) -> Cell? {
        switch progress {
        case ...(-1): nil
        case 0...lastTrackProgress: track[trackIndex(color, progress: progress)]
        case (lastTrackProgress + 1)...(home - 1): lane(color)[progress - lastTrackProgress - 1]
        default: centre
        }
    }

    /// The four squares half-way along each arm, marked with a star on most boards (track indices).
    public static let starIndices: Set<Int> = Set(PlayerColor.allCases.map { (startIndex($0) + 8) % trackLength })
}
