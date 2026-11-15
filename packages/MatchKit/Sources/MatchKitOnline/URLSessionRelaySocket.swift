#if canImport(Darwin)
import Foundation
import MatchKit

/// The real connection: a WebSocket to the relay over URLSession.
public final class URLSessionRelaySocket: RelaySocket, @unchecked Sendable {
    public let incoming: AsyncStream<String>
    private let out: AsyncStream<String>.Continuation
    private let task: URLSessionWebSocketTask
    private var keepAlive: Task<Void, Never>?

    /// - Parameter pingEvery: a WebSocket ping this often finds a dead link within seconds. The
    ///   relay's gateway answers these itself and does not charge for them.
    public init(url: URL, session: URLSession = .shared, pingEvery: Double = 15) {
        (incoming, out) = AsyncStream.makeStream()
        task = session.webSocketTask(with: url)
        task.maximumMessageSize = Relay.maxFrameBytes * 2
        task.resume()
        listen()
        keepAlive = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(pingEvery * 1_000_000_000))
                guard let self, !Task.isCancelled else { return }
                self.task.sendPing { [weak self] error in if error != nil { self?.close() } }
            }
        }
    }

    private func listen() {
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case let .success(.string(text)):
                self.out.yield(text)
                self.listen()
            case let .success(.data(data)):
                self.out.yield(String(decoding: data, as: UTF8.self))
                self.listen()
            case .success:
                self.listen()
            case .failure:
                self.close()
            }
        }
    }

    public func send(_ text: String) async throws { try await task.send(.string(text)) }

    public func close() {
        keepAlive?.cancel()
        task.cancel(with: .goingAway, reason: nil)
        out.finish()
    }
}

public extension OnlineTransport {
    /// Connections to the relay at `url` (`wss://…`).
    static func dial(_ url: URL, session: URLSession = .shared) -> Dial {
        { URLSessionRelaySocket(url: url, session: session) }
    }
}
#endif
