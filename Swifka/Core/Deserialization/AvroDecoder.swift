import Foundation

// MARK: - Avro Schema Model

/// Represents an Avro type parsed from a JSON schema.
/// Avro binary has no field tags — values are read sequentially in schema field order.
indirect nonisolated enum AvroType: Sendable {
    case null
    case boolean
    case int
    case long
    case float
    case double
    case string
    case bytes
    case record(name: String, fields: [AvroField])
    case array(items: AvroType)
    case map(values: AvroType)
    case enumType(name: String, symbols: [String])
    case union(branches: [AvroType])
    case fixed(name: String, size: Int)
}

nonisolated struct AvroField: Sendable {
    let name: String
    let type: AvroType
}

// MARK: - Avro Schema Parser

/// Parses Avro JSON schema string into an AvroType tree.
nonisolated enum AvroSchemaParser {
    static func parse(_ schemaJSON: String) throws -> AvroType {
        guard let data = schemaJSON.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data)
        else {
            throw AvroDecodingError.invalidSchema("Failed to parse schema JSON")
        }
        return try parseType(json)
    }

    private static func parseType(_ json: Any) throws -> AvroType {
        // Primitive type as string: "null", "boolean", "int", "long", etc.
        if let typeName = json as? String {
            return try parsePrimitive(typeName)
        }

        // Union as array: ["null", "string"]
        if let array = json as? [Any] {
            let branches = try array.map { try parseType($0) }
            return .union(branches: branches)
        }

        // Complex type as object: {"type": "record", ...}
        guard let dict = json as? [String: Any],
              let type = dict["type"] as? String
        else {
            throw AvroDecodingError.invalidSchema("Expected type string, array, or object")
        }

        switch type {
        case "record":
            let name = dict["name"] as? String ?? "Record"
            guard let fieldsJSON = dict["fields"] as? [[String: Any]] else {
                throw AvroDecodingError.invalidSchema("Record missing fields array")
            }
            let fields = try fieldsJSON.map { fieldDict -> AvroField in
                guard let fieldName = fieldDict["name"] as? String else {
                    throw AvroDecodingError.invalidSchema("Field missing name")
                }
                guard let fieldType = fieldDict["type"] else {
                    throw AvroDecodingError.invalidSchema("Field '\(fieldName)' missing type")
                }
                return try AvroField(name: fieldName, type: parseType(fieldType))
            }
            return .record(name: name, fields: fields)

        case "array":
            guard let items = dict["items"] else {
                throw AvroDecodingError.invalidSchema("Array missing items")
            }
            return try .array(items: parseType(items))

        case "map":
            guard let values = dict["values"] else {
                throw AvroDecodingError.invalidSchema("Map missing values")
            }
            return try .map(values: parseType(values))

        case "enum":
            let name = dict["name"] as? String ?? "Enum"
            guard let symbols = dict["symbols"] as? [String] else {
                throw AvroDecodingError.invalidSchema("Enum missing symbols array")
            }
            return .enumType(name: name, symbols: symbols)

        case "fixed":
            let name = dict["name"] as? String ?? "Fixed"
            guard let size = dict["size"] as? Int else {
                throw AvroDecodingError.invalidSchema("Fixed missing size")
            }
            return .fixed(name: name, size: size)

        default:
            // Could be a primitive type name in object form: {"type": "string"}
            return try parsePrimitive(type)
        }
    }

    private static func parsePrimitive(_ name: String) throws -> AvroType {
        switch name {
        case "null": .null
        case "boolean": .boolean
        case "int": .int
        case "long": .long
        case "float": .float
        case "double": .double
        case "string": .string
        case "bytes": .bytes
        default:
            throw AvroDecodingError.invalidSchema("Unknown type: \(name)")
        }
    }
}

// MARK: - Avro Binary Decoder

/// Decodes Avro binary data sequentially using a parsed schema.
/// No field tags — the schema dictates read order.
nonisolated struct AvroBinaryDecoder {
    private let data: Data
    private var position: Int

    init(data: Data) {
        self.data = data.startIndex == 0 ? data : Data(data)
        position = 0
    }

    /// Decode a value according to its Avro type. Returns a JSON-friendly Any.
    mutating func readValue(_ type: AvroType) throws -> Any {
        switch type {
        case .null:
            NSNull()
        case .boolean:
            try readBoolean()
        case .int:
            try readInt()
        case .long:
            try readLong()
        case .float:
            try readFloat()
        case .double:
            try readDouble()
        case .string:
            try readString()
        case .bytes:
            try readBytes()
        case let .record(_, fields):
            try readRecord(fields)
        case let .array(items):
            try readArray(items: items)
        case let .map(values):
            try readMap(values: values)
        case let .enumType(_, symbols):
            try readEnum(symbols: symbols)
        case let .union(branches):
            try readUnion(branches: branches)
        case let .fixed(_, size):
            try readFixed(size: size)
        }
    }

    // MARK: - Primitive Readers

    private mutating func readBoolean() throws -> Bool {
        guard position < data.count else {
            throw AvroDecodingError.unexpectedEnd("boolean")
        }
        let byte = data[position]
        position += 1
        return byte != 0
    }

    private mutating func readInt() throws -> Int32 {
        let raw = try readVarint()
        // Zigzag decode: (n >>> 1) ^ -(n & 1)
        return Int32(truncatingIfNeeded: (raw >> 1) ^ (~(raw & 1) &+ 1))
    }

    private mutating func readLong() throws -> Int64 {
        let raw = try readVarint()
        // Zigzag decode
        return Int64(bitPattern: (raw >> 1) ^ (~(raw & 1) &+ 1))
    }

    private mutating func readFloat() throws -> Float {
        guard position + 4 <= data.count else {
            throw AvroDecodingError.unexpectedEnd("float")
        }
        let bits = data[position ..< position + 4].withUnsafeBytes {
            $0.loadUnaligned(as: UInt32.self)
        }
        position += 4
        return Float(bitPattern: bits)
    }

    private mutating func readDouble() throws -> Double {
        guard position + 8 <= data.count else {
            throw AvroDecodingError.unexpectedEnd("double")
        }
        let bits = data[position ..< position + 8].withUnsafeBytes {
            $0.loadUnaligned(as: UInt64.self)
        }
        position += 8
        return Double(bitPattern: bits)
    }

    private mutating func readString() throws -> String {
        let length = try readLong()
        guard length >= 0 else {
            throw AvroDecodingError.invalidData("Negative string length: \(length)")
        }
        let len = Int(length)
        guard position + len <= data.count else {
            throw AvroDecodingError.unexpectedEnd("string(\(len))")
        }
        let bytes = data[position ..< position + len]
        position += len
        return String(data: bytes, encoding: .utf8) ?? "<invalid utf8>"
    }

    private mutating func readBytes() throws -> Data {
        let length = try readLong()
        guard length >= 0 else {
            throw AvroDecodingError.invalidData("Negative bytes length: \(length)")
        }
        let len = Int(length)
        guard position + len <= data.count else {
            throw AvroDecodingError.unexpectedEnd("bytes(\(len))")
        }
        let bytes = Data(data[position ..< position + len])
        position += len
        return bytes
    }

    // MARK: - Complex Readers

    private mutating func readRecord(_ fields: [AvroField]) throws -> OrderedDict {
        var result: [(String, Any)] = []
        for field in fields {
            let value = try readValue(field.type)
            result.append((field.name, value))
        }
        return OrderedDict(result)
    }

    /// Avro arrays: block-based encoding. Each block has a count followed by items.
    /// A block count of 0 terminates the array. Negative count means the block
    /// also includes its byte size (for skipping), and the absolute value is the count.
    private mutating func readArray(items: AvroType) throws -> [Any] {
        var result: [Any] = []
        while true {
            var blockCount = try readLong()
            if blockCount == 0 { break }
            if blockCount < 0 {
                blockCount = -blockCount
                _ = try readLong() // skip block byte size
            }
            for _ in 0 ..< blockCount {
                try result.append(readValue(items))
            }
        }
        return result
    }

    /// Avro maps: same block-based encoding as arrays, but each entry is a string key + value.
    private mutating func readMap(values: AvroType) throws -> OrderedDict {
        var result: [(String, Any)] = []
        while true {
            var blockCount = try readLong()
            if blockCount == 0 { break }
            if blockCount < 0 {
                blockCount = -blockCount
                _ = try readLong() // skip block byte size
            }
            for _ in 0 ..< blockCount {
                let key = try readString()
                let value = try readValue(values)
                result.append((key, value))
            }
        }
        return OrderedDict(result)
    }

    private mutating func readEnum(symbols: [String]) throws -> String {
        let index = try readInt()
        guard index >= 0, Int(index) < symbols.count else {
            return "UNKNOWN_\(index)"
        }
        return symbols[Int(index)]
    }

    /// Avro unions: varint branch index followed by the value of that branch type.
    private mutating func readUnion(branches: [AvroType]) throws -> Any {
        let index = try readInt()
        guard index >= 0, Int(index) < branches.count else {
            throw AvroDecodingError.invalidData("Union index \(index) out of range (0..<\(branches.count))")
        }
        let branch = branches[Int(index)]
        // If the selected branch is null, return NSNull
        if case .null = branch {
            return NSNull()
        }
        return try readValue(branch)
    }

    private mutating func readFixed(size: Int) throws -> Data {
        guard position + size <= data.count else {
            throw AvroDecodingError.unexpectedEnd("fixed(\(size))")
        }
        let bytes = Data(data[position ..< position + size])
        position += size
        return bytes
    }

    // MARK: - Varint

    /// Read an unsigned varint, then interpret as zigzag-encoded by callers.
    private mutating func readVarint() throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0

        while position < data.count {
            let byte = data[position]
            position += 1
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 {
                return result
            }
            shift += 7
            if shift >= 64 {
                throw AvroDecodingError.invalidData("Varint overflow")
            }
        }
        throw AvroDecodingError.unexpectedEnd("varint")
    }
}

// MARK: - High-Level Decoder & Formatters

/// Top-level Avro decode + format API. Used by MessageBrowserView.registryDecode().
nonisolated enum AvroDecoder {
    /// Decode Avro binary payload using a parsed schema. Returns a JSON-friendly dictionary.
    static func decode(payload: Data, schema: AvroType) throws -> Any {
        var decoder = AvroBinaryDecoder(data: payload)
        return try decoder.readValue(schema)
    }

    /// Flat one-liner for table cells: { order_id: 1001, customer: "Alice", total: 49.95 }
    static func formatFlat(_ value: Any) -> String {
        formatValue(value, flat: true)
    }

    /// Pretty indented JSON for detail panel
    static func formatPretty(_ value: Any) -> String {
        formatValue(value, flat: false, indent: 0)
    }

    // MARK: - Formatting Internals

    private static func formatValue(_ value: Any, flat: Bool, indent: Int = 0) -> String {
        switch value {
        case is NSNull:
            return "null"
        case let b as Bool:
            return b ? "true" : "false"
        case let i as Int32:
            return String(i)
        case let l as Int64:
            return String(l)
        case let f as Float:
            return formatFloat(f)
        case let d as Double:
            return formatDouble(d)
        case let s as String:
            return "\"\(escapeJSON(s))\""
        case let data as Data:
            let hex = data.prefix(32).map { String(format: "%02x", $0) }.joined()
            let suffix = data.count > 32 ? "..." : ""
            return "\"<\(data.count)B: \(hex)\(suffix)>\""
        case let dict as OrderedDict:
            return formatDict(dict.pairs, flat: flat, indent: indent)
        case let dict as [String: Any]:
            let pairs = dict.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
            return formatDict(pairs, flat: flat, indent: indent)
        case let arr as [Any]:
            return formatArray(arr, flat: flat, indent: indent)
        default:
            return String(describing: value)
        }
    }

    private static func formatDict(_ pairs: [(String, Any)], flat: Bool, indent: Int) -> String {
        if pairs.isEmpty { return "{}" }

        if flat {
            let parts = pairs.map { "\($0.0): \(formatValue($0.1, flat: true))" }
            return "{ \(parts.joined(separator: ", ")) }"
        }

        let pad = String(repeating: "  ", count: indent)
        let innerPad = String(repeating: "  ", count: indent + 1)
        var lines = ["{"]
        for (i, (key, val)) in pairs.enumerated() {
            let comma = i < pairs.count - 1 ? "," : ""
            let formatted = formatValue(val, flat: false, indent: indent + 1)
            lines.append("\(innerPad)\"\(escapeJSON(key))\": \(formatted)\(comma)")
        }
        lines.append("\(pad)}")
        return lines.joined(separator: "\n")
    }

    private static func formatArray(_ items: [Any], flat: Bool, indent: Int) -> String {
        if items.isEmpty { return "[]" }

        if flat {
            let parts = items.map { formatValue($0, flat: true) }
            return "[\(parts.joined(separator: ", "))]"
        }

        let pad = String(repeating: "  ", count: indent)
        let innerPad = String(repeating: "  ", count: indent + 1)
        var lines = ["["]
        for (i, item) in items.enumerated() {
            let comma = i < items.count - 1 ? "," : ""
            let formatted = formatValue(item, flat: false, indent: indent + 1)
            lines.append("\(innerPad)\(formatted)\(comma)")
        }
        lines.append("\(pad)]")
        return lines.joined(separator: "\n")
    }

    private static func formatFloat(_ f: Float) -> String {
        if f == f.rounded(), abs(f) < 1e7 {
            return String(format: "%.1f", f)
        }
        return String(f)
    }

    private static func formatDouble(_ d: Double) -> String {
        if d == d.rounded(), abs(d) < 1e15 {
            return String(format: "%.1f", d)
        }
        return String(d)
    }

    private static func escapeJSON(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }
}

// MARK: - Ordered Dictionary

/// Preserves insertion order for record fields (regular [String: Any] sorts keys).
final nonisolated class OrderedDict: @unchecked Sendable {
    let pairs: [(String, Any)]
    init(_ pairs: [(String, Any)]) {
        self.pairs = pairs
    }

    subscript(key: String) -> Any? {
        pairs.first { $0.0 == key }?.1
    }
}

// MARK: - Errors

nonisolated enum AvroDecodingError: LocalizedError {
    case invalidSchema(String)
    case unexpectedEnd(String)
    case invalidData(String)

    var errorDescription: String? {
        switch self {
        case let .invalidSchema(detail): "Invalid Avro schema: \(detail)"
        case let .unexpectedEnd(context): "Unexpected end of data reading \(context)"
        case let .invalidData(detail): "Invalid Avro data: \(detail)"
        }
    }
}
