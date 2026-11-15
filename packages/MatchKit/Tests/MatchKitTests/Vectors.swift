import Foundation
import Testing

/// Any JSON, for comparing what is written with the examples in `shared/vectors` whatever the
/// order of keys. A game's match and intents are read as this, so MatchKit pins the room's part
/// of each message without knowing the game.
enum JSONValue: Codable, Sendable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? c.decode(Double.self) {
            self = .number(n)
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else if let a = try? c.decode([JSONValue].self) {
            self = .array(a)
        } else {
            self = .object(try c.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case let .bool(b): try c.encode(b)
        case let .number(n): try c.encode(n)
        case let .string(s): try c.encode(s)
        case let .array(a): try c.encode(a)
        case let .object(o): try c.encode(o)
        }
    }

    init(json data: Data) throws { self = try JSONDecoder().decode(JSONValue.self, from: data) }

    /// What `value` is written as.
    init(writing value: some Encodable) throws { try self.init(json: JSONEncoder().encode(value)) }
}

/// The JSON examples every side of a wire format is held to (shared/vectors/README.md).
enum Vectors {
    struct File: Sendable, CustomTestStringConvertible {
        let name: String
        let data: Data
        var testDescription: String { name }
    }

    static let root = URL(fileURLWithPath: #filePath)   // …/packages/MatchKit/Tests/MatchKitTests/Vectors.swift
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("shared/vectors", isDirectory: true)

    /// Every `.json` under `folder`, by path, in order.
    static func files(in folder: String) -> [File] {
        let base = root.appendingPathComponent(folder, isDirectory: true)
        let prefix = base.standardizedFileURL.path + "/"
        var out: [File] = []
        for case let url as URL in FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) ?? .init()
        where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url) else { continue }
            out.append(File(name: String(url.standardizedFileURL.path.dropFirst(prefix.count)), data: data))
        }
        return out.sorted { $0.name < $1.name }
    }
}
