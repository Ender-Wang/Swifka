import Foundation

// MARK: - Confluent Wire Format

/// Utilities for detecting and parsing the Confluent Schema Registry wire format.
///
/// Wire format: [0x00 magic byte][4-byte big-endian schema ID][payload]
/// For Protobuf: [0x00][schema ID][varint message index array][protobuf payload]
enum ConfluentWireFormat {
    /// Minimum size: 1 byte magic + 4 bytes schema ID
    static let headerSize = 5

    /// Check if data uses the Confluent wire format (starts with magic byte 0x00).
    static func isConfluentEncoded(_ data: Data) -> Bool {
        data.count >= headerSize && data[data.startIndex] == 0x00
    }

    /// Extract the schema ID from bytes 1–4 (big-endian int32).
    static func extractSchemaID(_ data: Data) -> Int? {
        guard isConfluentEncoded(data) else { return nil }
        let start = data.startIndex
        return Int(data[start + 1]) << 24
            | Int(data[start + 2]) << 16
            | Int(data[start + 3]) << 8
            | Int(data[start + 4])
    }

    /// Extract the raw payload after the 5-byte header (for Avro and JSON Schema).
    static func extractPayload(_ data: Data) -> Data {
        Data(data.dropFirst(headerSize))
    }

    /// Extract Protobuf payload, accounting for the message index array.
    ///
    /// Protobuf wire format after the 5-byte header:
    /// - A varint-encoded array length (number of message indices)
    /// - If length > 0, that many varint-encoded message indices
    /// - The actual protobuf-encoded bytes
    ///
    /// Returns the message type index (0 = first message in .proto) and the payload.
    static func extractProtobufPayload(_ data: Data) -> (messageIndex: Int, payload: Data) {
        var offset = data.startIndex + headerSize

        // Read the array length (number of message indices)
        let (arrayLength, bytesRead) = readVarint(data, at: offset)
        offset += bytesRead

        if arrayLength == 0 {
            // No message indices → first message type (index 0)
            return (0, Data(data.suffix(from: offset)))
        }

        // Read the message indices (we only use the first one)
        var messageIndex = 0
        for i in 0 ..< Int(arrayLength) {
            let (idx, idxBytes) = readVarint(data, at: offset)
            offset += idxBytes
            if i == 0 {
                messageIndex = Int(idx)
            }
        }

        return (messageIndex, Data(data.suffix(from: offset)))
    }

    /// Extract ordered top-level message type names from .proto schema text.
    /// Used to map Confluent wire format message index to message type name.
    static func orderedMessageTypes(from protoText: String) -> [String] {
        let pattern = #"^\s*message\s+(\w+)\s*\{"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines) else { return [] }
        let range = NSRange(protoText.startIndex..., in: protoText)
        let matches = regex.matches(in: protoText, range: range)
        return matches.compactMap { match in
            guard let nameRange = Range(match.range(at: 1), in: protoText) else { return nil }
            return String(protoText[nameRange])
        }
    }

    /// Read a varint from data at the given offset.
    /// Returns (value, bytesConsumed).
    private static func readVarint(_ data: Data, at offset: Data.Index) -> (UInt64, Int) {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        var pos = offset
        var bytesRead = 0

        while pos < data.endIndex {
            let byte = data[pos]
            result |= UInt64(byte & 0x7F) << shift
            bytesRead += 1
            pos += 1

            if byte & 0x80 == 0 {
                break
            }
            shift += 7
        }

        return (result, bytesRead)
    }
}
