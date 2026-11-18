import Foundation
import Observation

/// Recent players: the last five people played online, newest first, so one of them can be asked
/// for another game without a new link. Kept on this phone only (docs/ONLINE_PLAY.md §6).
///
/// A player is known by their player number: 32 hex characters their phone made for itself and
/// gave this one during a game. It stands for their copy of the app, not for them.
@MainActor
@Observable
final class RecentPlayers {
    struct Entry: Codable, Equatable, Identifiable {
        /// Their player number.
        var id: String
        var name: String
        var lastPlayed: Date
    }

    /// Someone whose invitations are refused. The name is kept so the block can be undone by name.
    struct Blocked: Codable, Equatable, Identifiable {
        var id: String
        var name: String
    }

    static let limit = 5
    static let unnamed = "A friend"
    private static let playersKey = "recentPlayers"
    private static let blockedKey = "blockedPlayers"

    private(set) var players: [Entry]
    private(set) var blocked: [Blocked]
    /// This phone's own player number, so a game against yourself (two of your devices) lists nobody.
    var me: String?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: () -> Date

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
        players = Self.read([Entry].self, Self.playersKey, defaults) ?? []
        blocked = Self.read([Blocked].self, Self.blockedKey, defaults) ?? []
    }

    /// 32 lowercase hex characters, as the relay asks.
    nonisolated static func isPlayerNumber(_ text: String) -> Bool {
        text.count == 32 && text.allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }

    func isBlocked(_ id: String) -> Bool { blocked.contains { $0.id == id } }

    /// A game with them has started. They go to the top; the sixth drops off.
    func played(with id: String, name: String) {
        guard Self.isPlayerNumber(id), id != me, !isBlocked(id) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        players.removeAll { $0.id == id }
        players.insert(Entry(id: id, name: trimmed.isEmpty ? Self.unnamed : trimmed, lastPlayed: now()), at: 0)
        players = Array(players.prefix(Self.limit))
        save()
    }

    func remove(_ id: String) {
        players.removeAll { $0.id == id }
        save()
    }

    /// Off the list, and their invitations are refused from now on.
    func block(_ id: String) {
        guard Self.isPlayerNumber(id), !isBlocked(id) else { return }
        let name = players.first { $0.id == id }?.name ?? Self.unnamed
        players.removeAll { $0.id == id }
        blocked.append(Blocked(id: id, name: name))
        save()
    }

    func unblock(_ id: String) {
        blocked.removeAll { $0.id == id }
        save()
    }

    private func save() {
        let encoder = JSONEncoder()
        defaults.set(try? encoder.encode(players), forKey: Self.playersKey)
        defaults.set(try? encoder.encode(blocked), forKey: Self.blockedKey)
    }

    private static func read<T: Decodable>(_ type: T.Type, _ key: String, _ defaults: UserDefaults) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }
}
