/// The four players, in seating order clockwise from the top left (as on the owner's board art: red
/// top left, gold top right, black bottom right, green bottom left). Lelu Ludo uses the colours of
/// Ghana's flag (red, gold, green) with the black of its star, which sits at the centre of the board.
public enum PlayerColor: Int, Sendable, Codable, CaseIterable, Hashable {
    case red, gold, black, green

    /// The next colour clockwise.
    public var next: PlayerColor { PlayerColor(rawValue: (rawValue + 1) % 4)! }

    public var name: String {
        switch self {
        case .red: "Red"
        case .gold: "Gold"
        case .black: "Black"
        case .green: "Green"
        }
    }
}
