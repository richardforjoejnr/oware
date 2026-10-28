import Foundation

/// Seconds, for heartbeats. Injected so tests and the demo can move time on by hand.
public protocol RoomClock: Sendable {
    var now: Double { get }
}

public struct SystemClock: RoomClock {
    public init() {}
    public var now: Double { ProcessInfo.processInfo.systemUptime }
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
