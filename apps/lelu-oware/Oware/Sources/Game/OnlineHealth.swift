import Foundation
import MatchKit
import MatchKitOnline
import Observation

/// Whether online play can be used just now: asked of the relay as the app opens and each time it
/// comes to the front (`ping` with the game; shared/vectors/relay-v1). Home greys out Play online
/// when the relay is down or the game is paused there, instead of failing after Start game.
@MainActor
@Observable
final class OnlineHealth {
    enum State: Equatable {
        /// Not asked yet, or asking for the first time: nothing is held against online play.
        case unknown
        case up
        /// The relay is there and Oware is paused on it (its off switch).
        case resting
        /// No answer: the relay is down, or this phone has no internet.
        case unreachable
    }

    private(set) var state: State
    var isDown: Bool { state == .resting || state == .unreachable }
    /// Under Play online on Home while it cannot be used. Tapping the row asks again.
    var note: String? {
        switch state {
        case .resting: "resting just now · tap to check again"
        case .unreachable: "can't be reached · tap to try again"
        case .unknown, .up: nil
        }
    }

    /// Between checks nobody asked for (the app coming to the front), in seconds.
    static let interval: TimeInterval = 30

    private let dial: OnlineTransport.Dial
    private let wait: Double
    private let now: () -> Date
    /// Test launches and the demo: never asks, always this.
    private let fixed: State?
    private var lastAsked: Date?
    private var asking: Task<State, Never>?

    init(dial: @escaping OnlineTransport.Dial = OnlineConfig.dial, wait: Double = 6, now: @escaping () -> Date = Date.init, fixed: State? = nil) {
        self.dial = dial
        self.wait = wait
        self.now = now
        self.fixed = fixed
        state = fixed ?? .unknown
    }

    /// What the relay's answer means. Any answer at all means it is there.
    static func reading(_ answer: RelayEvent?) -> State {
        switch answer {
        case .none: .unreachable
        case .health(open: false), .refused(.paused): .resting
        default: .up
        }
    }

    /// Asks the relay, unless it was asked in the last half minute (`force`: ask anyway, as when
    /// the player taps the greyed-out row). One silence is tried again before it counts as down.
    @discardableResult
    func check(force: Bool = false) async -> State {
        if let fixed { return fixed }
        if let asking { return await asking.value }
        if !force, let lastAsked, now().timeIntervalSince(lastAsked) < Self.interval { return state }
        lastAsked = now()
        let dial = dial, wait = wait
        let task = Task { () -> State in
            var answer = await RelayCall.ask(.health(game: OnlineConfig.game.name), dial: dial, wait: wait)
            if answer == nil { answer = await RelayCall.ask(.health(game: OnlineConfig.game.name), dial: dial, wait: wait) }
            return Self.reading(answer)
        }
        asking = task
        state = await task.value
        asking = nil
        return state
    }
}
