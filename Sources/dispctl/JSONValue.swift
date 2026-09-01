// Minimal heterogeneous value so `list --json` can be encoded without a model type.

import Foundation

enum JSONValue: Encodable {
    case string(String)
    case number(UInt32)
    case bool(Bool)

    init(_ value: String) { self = .string(value) }
    init(_ value: UInt32) { self = .number(value) }
    init(_ value: Bool) { self = .bool(value) }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        }
    }
}
