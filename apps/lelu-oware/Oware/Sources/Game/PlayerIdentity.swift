import Foundation
import MatchKitOnline
import Security

/// Who this phone is when it asks someone for another game, or may be asked
/// (docs/ONLINE_PLAY.md §6). Not an account, and it names nobody.
///
/// - `id` is the player number: the phones this one plays online are given it, so they can ask
///   for another game. It stands for this copy of the app.
/// - `secret` goes only to the relay, to show that a later message comes from the phone that
///   registered the number. Nobody who has the number can use it without the secret.
struct PlayerIdentity: Codable, Equatable, Sendable {
    var id: String
    var secret: String

    static let key = "onlinePlayer"

    /// This phone's, made the first time and kept in the Keychain. Nil when it cannot be kept
    /// there: a secret goes nowhere less safe, and the phone then has no player number.
    static func mine(secrets: any SecretStore = Keychain()) -> PlayerIdentity? {
        if let kept = secrets.read(key), let identity = try? JSONDecoder().decode(PlayerIdentity.self, from: kept),
           RecentPlayers.isPlayerNumber(identity.id), !identity.secret.isEmpty {
            return identity
        }
        let made = new()
        guard let data = try? JSONEncoder().encode(made), secrets.write(data, for: key) else { return nil }
        return made
    }

    /// A new one: 128 random bits for the number, 256 for the secret.
    static func new() -> PlayerIdentity {
        PlayerIdentity(id: hex(16), secret: hex(32))
    }

    private static func hex(_ count: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        if SecRandomCopyBytes(kSecRandomDefault, count, &bytes) != errSecSuccess {
            var generator = SystemRandomNumberGenerator()
            bytes = (0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    var forRelay: RelayPlayer { RelayPlayer(id: id, secret: secret, game: OnlineConfig.game.name) }
}
