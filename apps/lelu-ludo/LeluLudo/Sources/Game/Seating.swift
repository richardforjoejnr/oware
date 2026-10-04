import LudoEngine

/// Choosing your colour against the computer (owner's mockup, 2026-10-04): one colour, yours; the
/// computers take the colours left. Pure, so it is tested without a screen.
struct ComputerSeating: Equatable {
    var you: PlayerColor = .red
    var opponents = 1

    /// The computers' colours: opposite you first, then beside you.
    var opponentColours: [PlayerColor] { GameSetup.opponentColours(for: you, count: opponents) }

    /// "Random colour": any colour but the one you have, so the tap always changes something.
    mutating func randomColour<G: RandomNumberGenerator>(using rng: inout G) {
        you = PlayerColor.allCases.filter { $0 != you }.randomElement(using: &rng)!
    }
}

/// Choosing colours and names for pass & play (owner's mockup): tap a colour to add a player, tap it
/// again to take them out. Each colour is one player, so two can never share it. Names are optional.
struct FriendsSeating: Equatable {
    /// Who is playing, in board order, and the name each typed ("" until they type one).
    private(set) var names: [PlayerColor: String] = [.red: "", .black: ""]

    var colours: [PlayerColor] { PlayerColor.allCases.filter { names[$0] != nil } }
    func isPlaying(_ c: PlayerColor) -> Bool { names[c] != nil }
    var canPlay: Bool { (2...4).contains(names.count) }

    /// A colour in or out of the game.
    mutating func toggle(_ c: PlayerColor) {
        if names[c] != nil { names[c] = nil } else { names[c] = "" }
    }

    mutating func setName(_ name: String, for c: PlayerColor) {
        guard names[c] != nil else { return }
        names[c] = String(name.prefix(GameSetup.nameLimit))
    }

    /// What a player is called: their name, or their colour.
    func displayName(_ c: PlayerColor) -> String { GameSetup.cleanName(names[c] ?? "") ?? c.name }

    /// "Random colours": the same players (and their names) in colours drawn at random; with fewer
    /// than two, two random colours.
    mutating func randomColours<G: RandomNumberGenerator>(using rng: inout G) {
        let typed = colours.map { names[$0] ?? "" }
        let people = typed.count >= 2 ? typed : ["", ""]
        let drawn = PlayerColor.allCases.shuffled(using: &rng).prefix(people.count)
        names = Dictionary(uniqueKeysWithValues: zip(drawn, people))
    }

    func setup(rules: RuleSet) -> GameSetup? { GameSetup.passAndPlay(names, rules: rules) }
}
