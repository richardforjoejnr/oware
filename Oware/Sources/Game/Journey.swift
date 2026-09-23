import Foundation
import Observation
import OwareEngine
import OwareAI

/// The Journey: eight places in Ghana, each with three opponents. Opponents are respectful
/// archetypes with Akan, Ewe, Ga and Dagbani names appropriate to each region. Rewards are
/// cosmetic only; the rules never change.
enum Journey {
    struct Opponent: Identifiable, Hashable, Sendable {
        let id: String
        let name: String
        let role: String
        let greeting: String
        let difficulty: Difficulty
        let personality: Personality
    }

    struct Chapter: Identifiable, Hashable, Sendable {
        let id: String
        let title: String
        let region: String
        let blurb: String
        let opponents: [Opponent]
    }

    static let chapters: [Chapter] = [
        Chapter(id: "kumasi", title: "Kumasi", region: "Ashanti Region",
                blurb: "The Garden City. In the shade near Manhyia, boards come out in the late afternoon.",
                opponents: [
                    Opponent(id: "kumasi-1", name: "Kofi", role: "drummer's apprentice", greeting: "Akwaaba. Go easy on me — I only learned last week.", difficulty: .beginner, personality: .balanced),
                    Opponent(id: "kumasi-2", name: "Akua", role: "student", greeting: "I count faster than you. Let's see.", difficulty: .beginner, personality: .trickster),
                    Opponent(id: "kumasi-3", name: "Yaw", role: "taxi driver", greeting: "Every day I play at the station. Sit.", difficulty: .learner, personality: .aggressive),
                ]),
        Chapter(id: "bonwire", title: "Bonwire", region: "Kente village",
                blurb: "Looms clack all day. Between strips of cloth, the weavers play for tea.",
                opponents: [
                    Opponent(id: "bonwire-1", name: "Abena", role: "weaver", greeting: "Patience makes the cloth. Patience makes the game.", difficulty: .learner, personality: .cautious),
                    Opponent(id: "bonwire-2", name: "Kwabena", role: "master weaver", greeting: "Adweneasa — my skill is exhausted. Yours?", difficulty: .learner, personality: .hoarder),
                    Opponent(id: "bonwire-3", name: "Nana Afua", role: "elder", greeting: "Sit down, child. Watch my hands, not the seeds.", difficulty: .player, personality: .balanced),
                ]),
        Chapter(id: "bosomtwe", title: "Lake Bosomtwe", region: "Ashanti Region",
                blurb: "A crater lake ringed by hills. Fishermen play on planks by the water.",
                opponents: [
                    Opponent(id: "bosomtwe-1", name: "Kwesi", role: "fisherman", greeting: "The lake is calm. I am not.", difficulty: .player, personality: .aggressive),
                    Opponent(id: "bosomtwe-2", name: "Adwoa", role: "guesthouse keeper", greeting: "Everyone who stays here loses to me once.", difficulty: .player, personality: .trickster),
                    Opponent(id: "bosomtwe-3", name: "Kojo", role: "teacher", greeting: "I teach arithmetic with this board. Shall we?", difficulty: .player, personality: .cautious),
                ]),
        Chapter(id: "techiman", title: "Techiman", region: "Bono Region",
                blurb: "Bono country, where the game is as old as the market. Traders play between sales.",
                opponents: [
                    Opponent(id: "techiman-1", name: "Ama", role: "yam trader", greeting: "Buy something first. Then we play.", difficulty: .player, personality: .hoarder),
                    Opponent(id: "techiman-2", name: "Kwaku", role: "goldsmith", greeting: "Small, careful moves. Like my work.", difficulty: .strong, personality: .cautious),
                    Opponent(id: "techiman-3", name: "Nana Yaa", role: "queen mother", greeting: "They say Opoku Ware settled quarrels with this game. Let us have no quarrel.", difficulty: .strong, personality: .balanced),
                ]),
        Chapter(id: "capecoast", title: "Cape Coast", region: "Central Region",
                blurb: "Salt air and old stone. On the beach the seeds are cowries and the sun is low.",
                opponents: [
                    Opponent(id: "capecoast-1", name: "Esi", role: "fish smoker", greeting: "The tide waits. I don't.", difficulty: .strong, personality: .aggressive),
                    Opponent(id: "capecoast-2", name: "Ekow", role: "boat builder", greeting: "A good hull, a good board — both need balance.", difficulty: .strong, personality: .balanced),
                    Opponent(id: "capecoast-3", name: "Uncle Kobina", role: "retired headmaster", greeting: "I have failed better players than you. Begin.", difficulty: .strong, personality: .trickster),
                ]),
        Chapter(id: "accra", title: "Makola, Accra", region: "Greater Accra",
                blurb: "The market never stops. The Ga call the game awele; the rules are the same.",
                opponents: [
                    Opponent(id: "accra-1", name: "Naa Dede", role: "cloth seller", greeting: "Ayekoo if you win. Nobody has yet.", difficulty: .strong, personality: .trickster),
                    Opponent(id: "accra-2", name: "Nii Lartey", role: "mechanic", greeting: "I fix engines all day. Your plan too.", difficulty: .master, personality: .aggressive),
                    Opponent(id: "accra-3", name: "Auntie Adjoa", role: "chop bar owner", greeting: "Eat first. Then lose.", difficulty: .master, personality: .hoarder),
                ]),
        Chapter(id: "volta", title: "Ho", region: "Volta Region",
                blurb: "Ewe country under the hills. Here the game is adji, and it is played hard.",
                opponents: [
                    Opponent(id: "volta-1", name: "Selorm", role: "farmer", greeting: "Rain makes the yam. Patience makes the win.", difficulty: .master, personality: .cautious),
                    Opponent(id: "volta-2", name: "Dzifa", role: "nurse", greeting: "I see everything. Including your next move.", difficulty: .master, personality: .balanced),
                    Opponent(id: "volta-3", name: "Togbe Edem", role: "chief", greeting: "In my court we settle things with seeds.", difficulty: .master, personality: .trickster),
                ]),
        Chapter(id: "tamale", title: "Tamale", region: "Northern Region",
                blurb: "Dust and bright light. In Dagbani the game is wali; the savannah players are famous.",
                opponents: [
                    Opponent(id: "tamale-1", name: "Amina", role: "shea butter maker", greeting: "My hands are strong. So is my game.", difficulty: .master, personality: .aggressive),
                    Opponent(id: "tamale-2", name: "Fuseini", role: "cattle trader", greeting: "I count cattle all day. Seeds are easy.", difficulty: .grandmaster, personality: .hoarder),
                    Opponent(id: "tamale-3", name: "Alhassan", role: "the champion", greeting: "You came a long way. Show me why.", difficulty: .grandmaster, personality: .balanced),
                ]),
    ]

    static func chapter(_ index: Int) -> Chapter? { chapters.indices.contains(index) ? chapters[index] : nil }
    static func opponent(chapter: Int, index: Int) -> Opponent? {
        guard let c = Self.chapter(chapter), c.opponents.indices.contains(index) else { return nil }
        return c.opponents[index]
    }

    /// Stars for a finished match from the human's (south) point of view.
    static func stars(for state: GameState) -> Int {
        guard state.outcome?.winner == .south else { return 0 }
        let seeds = state.store(of: .south)
        if seeds >= 32 { return 3 }
        if seeds >= 28 { return 2 }
        return 1
    }
}

/// Stars earned per opponent, persisted in UserDefaults.
@MainActor
@Observable
final class JourneyProgress {
    private(set) var stars: [String: Int]
    private let defaults: UserDefaults
    private static let key = "journeyStars"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        stars = (defaults.dictionary(forKey: Self.key) as? [String: Int]) ?? [:]
    }

    func stars(for opponent: Journey.Opponent) -> Int { stars[opponent.id] ?? 0 }
    func stars(in chapter: Journey.Chapter) -> Int { chapter.opponents.reduce(0) { $0 + stars(for: $1) } }
    var totalStars: Int { stars.values.reduce(0, +) }

    /// A chapter opens once every opponent in the previous chapter has been beaten.
    func isUnlocked(chapterIndex: Int) -> Bool {
        guard chapterIndex > 0, let previous = Journey.chapter(chapterIndex - 1) else { return true }
        return previous.opponents.allSatisfy { stars(for: $0) > 0 }
    }

    func record(stars newStars: Int, for opponent: Journey.Opponent) {
        guard newStars > stars(for: opponent) else { return }
        stars[opponent.id] = newStars
        defaults.set(stars, forKey: Self.key)
    }

    func reset() {
        stars = [:]
        defaults.removeObject(forKey: Self.key)
    }
}
