import Foundation

/// Messages over a stream (TCP): a 4-byte big-endian length, then the message.
public enum Framer {
    /// Game Center's turn-based limit, so whatever fits nearby fits online too.
    public static let maxMessageBytes = 64 * 1024

    public enum Failure: Error, Equatable {
        case tooLarge(Int)
    }

    public static func frame(_ message: Data) throws -> Data {
        guard message.count <= maxMessageBytes else { throw Failure.tooLarge(message.count) }
        let n = UInt32(message.count)
        var out = Data([UInt8(n >> 24), UInt8(n >> 16 & 0xFF), UInt8(n >> 8 & 0xFF), UInt8(n & 0xFF)])
        out.append(message)
        return out
    }

    /// Joins what arrives, however it is split, back into whole messages.
    public struct Reader: Sendable {
        private var buffer = Data()

        public init() {}

        /// The messages completed by `bytes`. Throws on a length over the limit; the connection
        /// should then be closed, since the stream can no longer be trusted.
        public mutating func push(_ bytes: Data) throws -> [Data] {
            buffer.append(bytes)
            var out: [Data] = []
            while buffer.count >= 4 {
                let b = [UInt8](buffer.prefix(4))
                let length = Int(b[0]) << 24 | Int(b[1]) << 16 | Int(b[2]) << 8 | Int(b[3])
                guard length <= Framer.maxMessageBytes else {
                    buffer.removeAll()
                    throw Failure.tooLarge(length)
                }
                guard buffer.count >= 4 + length else { break }
                out.append(Data(buffer.dropFirst(4).prefix(length)))
                buffer = Data(buffer.dropFirst(4 + length))
            }
            return out
        }
    }
}
