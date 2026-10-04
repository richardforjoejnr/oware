/// The four players, in seating order clockwise from the top left (as on the owner's board art: red
/// top left, yellow top right, black bottom right, green bottom left). Red, yellow and green from
/// Ghana's flag with the black of its star, which sits at the centre of the board. Black rather than
/// the usual blue is a Lelu design choice, not a Ghana Ludo rule (owner, 2026-10-03).
public enum PlayerColor: Int, Sendable, Codable, CaseIterable, Hashable {
    case red, yellow, black, green

    public var name: String {
        switch self {
        case .red: "Red"
        case .yellow: "Yellow"
        case .black: "Black"
        case .green: "Green"
        }
    }
}
