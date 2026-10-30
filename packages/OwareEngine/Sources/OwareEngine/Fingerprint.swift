extension GameState {
    /// A short code for this position, the same on every phone and platform: two phones compare
    /// it to check they hold the same game (before the first move, and after reconnecting).
    ///
    /// FNV-1a (64-bit) over a fixed text form of everything that decides the game: rules, move
    /// number, whose turn, houses, stores, territory, round and outcome. Not Swift's `hashValue`,
    /// which changes every launch. The "v1" names the format: change it on purpose, never by
    /// accident (`FingerprintTests` pins the opening).
    public var fingerprint: String {
        let outcomeText: String = switch outcome {
        case nil: "-"
        case let .win(player, reason): "win:\(player.label):\(reason.rawValue)"
        case let .draw(reason): "draw:\(reason.rawValue)"
        }
        let text = [
            "v1",
            rules.variant.rawValue,
            "\(moveNumber)",
            sideToMove.label,
            houses.map(String.init).joined(separator: ","),
            stores.map(String.init).joined(separator: ","),
            territory.map(\.label).joined(),
            "\(round)",
            outcomeText,
        ].joined(separator: "|")
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01b3
        }
        let hex = String(hash, radix: 16)
        return String(repeating: "0", count: 16 - hex.count) + hex
    }
}
