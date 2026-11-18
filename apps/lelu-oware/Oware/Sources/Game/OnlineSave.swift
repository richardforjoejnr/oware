import Foundation
import MatchKit
import MatchKitOnline
import Observation
import OwareEngine
import Security

/// Small secrets kept on this phone: the Keychain in the app, memory in tests.
protocol SecretStore: Sendable {
    func read(_ key: String) -> Data?
    /// False if it could not be kept.
    @discardableResult func write(_ data: Data, for key: String) -> Bool
    func remove(_ key: String)
}

/// The phone's Keychain. Items stay on this phone (they are not in a backup restored to another),
/// and can be read once the phone has been unlocked after starting up.
struct Keychain: SecretStore {
    var service = (Bundle.main.bundleIdentifier ?? "LeluOware") + ".online"

    private func item(_ key: String) -> [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: key]
    }

    func read(_ key: String) -> Data? {
        var query = item(key)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var found: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &found) == errSecSuccess else { return nil }
        return found as? Data
    }

    @discardableResult
    func write(_ data: Data, for key: String) -> Bool {
        let status = SecItemUpdate(item(key) as CFDictionary, [kSecValueData: data] as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var new = item(key)
        new[kSecValueData] = data
        new[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(new as CFDictionary, nil) == errSecSuccess
    }

    func remove(_ key: String) {
        SecItemDelete(item(key) as CFDictionary)
    }
}

/// Secrets in memory, for tests.
final class MemorySecrets: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var kept: [String: Data] = [:]
    /// As when the Keychain cannot be used.
    var refusesWrites = false

    func read(_ key: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return kept[key]
    }

    @discardableResult
    func write(_ data: Data, for key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !refusesWrites else { return false }
        kept[key] = data
        return true
    }

    func remove(_ key: String) {
        lock.lock()
        defer { lock.unlock() }
        kept[key] = nil
    }
}

/// Secrets in a plain file, for the demo player only (`--online-demo`, which only Debug builds
/// take). Its relay is inside the app, so its tokens open nothing; and the test builds that run
/// it on the simulator are not signed, so they have no Keychain.
struct DemoSecrets: SecretStore {
    private let folder: URL

    init(folder: URL? = nil) {
        self.folder = folder ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LeluOware/demo", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.folder, withIntermediateDirectories: true)
    }

    private func file(_ key: String) -> URL { folder.appendingPathComponent(key) }

    func read(_ key: String) -> Data? { try? Data(contentsOf: file(key)) }

    @discardableResult
    func write(_ data: Data, for key: String) -> Bool { (try? data.write(to: file(key), options: .atomic)) != nil }

    func remove(_ key: String) { try? FileManager.default.removeItem(at: file(key)) }
}

/// An online game as a phone keeps it, to come back to after the app was closed
/// (docs/ONLINE_PLAY.md §5): where it is, this phone's seat in it, the match so far and who the
/// other player is. The tokens in `relay` and `room` are secrets: whoever holds them is this seat.
struct OnlineSave: Equatable, Sendable {
    /// The game's code, and this phone's place in it at the relay.
    var relay: OnlineTransport.Seat
    /// This phone's seat among the phones, and the names.
    var room: RoomSave
    var table: OwareTable
    var opponentName: String

    var code: String { relay.code }
    /// 0 made the game (its phone is in charge and plays South), 1 joined it.
    var seat: Int { room.seat }
}

/// Where the online game is kept: the game in a file, its tokens in the Keychain. One game at a
/// time, as there is one board.
@MainActor
@Observable
final class OnlineSaves {
    /// The app's: tokens in the Keychain. (The demo player's game keeps its own apart: `DemoSecrets`.)
    static let shared = OnlineSaves(secrets: LaunchOptions.onlineDemo ? DemoSecrets() : Keychain())
    /// The Keychain item that holds the saved game's tokens.
    nonisolated static let secretsKey = "onlineGame"

    /// The game to come back to, if there is one.
    private(set) var current: OnlineSave?

    @ObservationIgnored private let url: URL
    @ObservationIgnored private let secrets: any SecretStore

    /// Everything but the tokens.
    private struct Kept: Codable {
        var code: String
        var peer: String
        var seat: Int
        var names: [Int: String]
        var sequence: Int
        var table: OwareTable
        var opponentName: String
    }

    private struct Tokens: Codable, Equatable {
        /// For the relay: `rejoin(code, token)`.
        var relay: String
        /// For the other phone: the seat tokens of the game's room.
        var room: [Int: UUID]
    }

    init(directory: URL? = nil, secrets: any SecretStore = Keychain()) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LeluOware", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        url = base.appendingPathComponent("online-game.json")
        self.secrets = secrets
        current = load()
    }

    private func load() -> OnlineSave? {
        guard let data = try? Data(contentsOf: url), let kept = try? JSONDecoder().decode(Kept.self, from: data),
              let secret = secrets.read(Self.secretsKey), let tokens = try? JSONDecoder().decode(Tokens.self, from: secret) else { return nil }
        return OnlineSave(relay: .init(code: kept.code, peer: PeerID(kept.peer), token: tokens.relay),
                          room: RoomSave(seat: kept.seat, names: kept.names, tokens: tokens.room, sequence: kept.sequence),
                          table: kept.table, opponentName: kept.opponentName)
    }

    /// Keeps the game as it now stands. Without the Keychain nothing is kept: a game without its
    /// tokens cannot be gone back to.
    func save(_ game: OnlineSave) {
        guard game != current else { return }
        let tokens = Tokens(relay: game.relay.token, room: game.room.tokens)
        let before = current.map { Tokens(relay: $0.relay.token, room: $0.room.tokens) }
        if tokens != before {
            guard let secret = try? JSONEncoder().encode(tokens), secrets.write(secret, for: Self.secretsKey) else { return }
        }
        let kept = Kept(code: game.relay.code, peer: game.relay.peer.raw, seat: game.room.seat, names: game.room.names,
                        sequence: game.room.sequence, table: game.table, opponentName: game.opponentName)
        guard let data = try? JSONEncoder().encode(kept), (try? data.write(to: url, options: .atomic)) != nil else { return }
        current = game
    }

    /// The game is over, or left, or gone: nothing to come back to.
    func clear() {
        try? FileManager.default.removeItem(at: url)
        secrets.remove(Self.secretsKey)
        current = nil
    }
}
