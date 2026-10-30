import Foundation

/// Seconds, for heartbeats. Injected so tests and the demo can move time on by hand.
public protocol RoomClock: Sendable {
    var now: Double { get }
}

/// Seconds since this clock was made. `ContinuousClock` rather than ProcessInfo's uptime, which Apple
/// counts as reading the boot time and asks apps to give a reason for in their privacy manifest.
public struct SystemClock: RoomClock {
    private let start = ContinuousClock.now

    public init() {}

    public var now: Double {
        let elapsed = start.duration(to: .now).components
        return Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
    }
}

/// A clock that moves only when told to.
public final class ManualClock: RoomClock, @unchecked Sendable {
    private let lock = NSLock()
    private var seconds: Double

    public init(now: Double = 0) { seconds = now }

    public var now: Double { lock.sync { seconds } }

    public func advance(by interval: Double) { lock.sync { seconds += interval } }
}

extension NSLock {
    /// `withLock` is missing from older Linux Foundations.
    func sync<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
