import Foundation
import SwiftProtobuf

// MARK: - Protobuf Deserializer

/// Deserializes Protocol Buffer binary data using dynamically loaded .proto definitions
nonisolated struct ProtobufDeserializer: MessageDeserializer {
    let id = "protobuf"
    let displayName = "Protocol Buffers"
    let requiresConfiguration = true

    private let protoFilePath: String?
    private let messageTypeName: String?

    init(protoFilePath: String? = nil, messageTypeName: String? = nil) {
        self.protoFilePath = protoFilePath
        self.messageTypeName = messageTypeName
    }

    func deserialize(_ data: Data?) -> DeserializedContent {
        guard let data, !data.isEmpty else {
            return data == nil ? .plainText("(null)") : .plainText("(empty)")
        }

        // Check if configuration is available
        guard protoFilePath != nil, messageTypeName != nil else {
            return .plainText("(protobuf - not configured)")
        }

        // Decode using protobuf wire format
        do {
            var decoder = ProtobufWireDecoder(data: data)
            let fields = try decoder.decodeFields()

            let formatted = Self.formatFieldsPretty(fields)
            return .plainText(formatted)
        } catch {
            return .plainText("(protobuf decode error: \(error.localizedDescription))")
        }
    }

    func prettyFormat(_ data: Data?) -> DeserializedContent {
        deserialize(data)
    }

    /// Flat one-liner format for table cells
    static func formatFieldsFlat(_ fields: [ProtobufField]) -> String {
        let parts = fields.map { field -> String in
            switch field.value {
            case let .varint(value):
                "f\(field.fieldNumber):\(value)"
            case let .fixed64(value):
                "f\(field.fieldNumber):\(value)"
            case let .lengthDelimited(bytes):
                if let string = String(data: bytes, encoding: .utf8),
                   !bytes.contains(0)
                {
                    "f\(field.fieldNumber):\"\(string)\""
                } else {
                    "f\(field.fieldNumber):<\(bytes.count)B>"
                }
            case let .fixed32(value):
                "f\(field.fieldNumber):\(value)"
            case let .nested(subFields):
                "f\(field.fieldNumber):{\(formatFieldsFlat(subFields))}"
            }
        }
        return "{ \(parts.joined(separator: ", ")) }"
    }

    /// Pretty JSON-like format for detail panel
    static func formatFieldsPretty(_ fields: [ProtobufField], indent: Int = 0) -> String {
        let pad = String(repeating: "  ", count: indent)
        let innerPad = String(repeating: "  ", count: indent + 1)
        var lines = ["\(pad){"]

        for (index, field) in fields.enumerated() {
            let isLast = index == fields.count - 1
            let comma = isLast ? "" : ","

            switch field.value {
            case let .varint(value):
                lines.append("\(innerPad)\"field_\(field.fieldNumber)\": \(value)\(comma)")
            case let .fixed64(value):
                lines.append("\(innerPad)\"field_\(field.fieldNumber)\": \(value)\(comma)")
            case let .lengthDelimited(bytes):
                if let string = String(data: bytes, encoding: .utf8),
                   !bytes.contains(0)
                {
                    let escaped = string.replacingOccurrences(of: "\"", with: "\\\"")
                    lines.append("\(innerPad)\"field_\(field.fieldNumber)\": \"\(escaped)\"\(comma)")
                } else {
                    let hex = bytes.map { String(format: "%02x", $0) }.joined()
                    lines.append("\(innerPad)\"field_\(field.fieldNumber)\": \"<binary: \(hex)>\"\(comma)")
                }
            case let .fixed32(value):
                lines.append("\(innerPad)\"field_\(field.fieldNumber)\": \(value)\(comma)")
            case let .nested(subFields):
                let nested = formatFieldsPretty(subFields, indent: indent + 1)
                lines.append("\(innerPad)\"field_\(field.fieldNumber)\": \(nested)\(comma)")
            }
        }

        lines.append("\(pad)}")
        return lines.joined(separator: "\n")
    }
}

// MARK: - Schema-Aware Formatting

extension ProtobufDeserializer {
    /// Flat one-liner with real field names for table cells
    static func formatFlatWithSchema(
        _ fields: [ProtobufField],
        schema: ProtoSchema,
        messageType: String,
    ) -> String {
        guard let msgDef = schema.messages[messageType] else {
            return formatFieldsFlat(fields)
        }

        let groups = groupByFieldNumber(fields)

        let parts = groups.map { fieldNumber, fieldsForNum -> String in
            let def = msgDef.fields[fieldNumber]
            let name = def?.name ?? "f\(fieldNumber)"
            let type = def?.typeName
            let isRepeated = def?.isRepeated ?? (fieldsForNum.count > 1)

            if isRepeated || fieldsForNum.count > 1 {
                let values = fieldsForNum.map { formatValueFlat($0.value, type: type, schema: schema) }
                return "\(name):[\(values.joined(separator: ","))]"
            } else {
                return "\(name):\(formatValueFlat(fieldsForNum[0].value, type: type, schema: schema))"
            }
        }

        return "{ \(parts.joined(separator: ", ")) }"
    }

    /// Pretty JSON with real field names for detail panel
    static func formatPrettyWithSchema(
        _ fields: [ProtobufField],
        schema: ProtoSchema,
        messageType: String,
        indent: Int = 0,
    ) -> String {
        guard let msgDef = schema.messages[messageType] else {
            return formatFieldsPretty(fields, indent: indent)
        }

        let pad = String(repeating: "  ", count: indent)
        let innerPad = String(repeating: "  ", count: indent + 1)

        let groups = groupByFieldNumber(fields)
        var lines = ["\(pad){"]

        for (groupIndex, (fieldNumber, fieldsForNum)) in groups.enumerated() {
            let isLast = groupIndex == groups.count - 1
            let comma = isLast ? "" : ","

            let def = msgDef.fields[fieldNumber]
            let name = def?.name ?? "field_\(fieldNumber)"
            let type = def?.typeName
            let isRepeated = def?.isRepeated ?? (fieldsForNum.count > 1)

            if isRepeated || fieldsForNum.count > 1 {
                lines.append("\(innerPad)\"\(name)\": [")
                let arrayPad = String(repeating: "  ", count: indent + 2)
                for (i, field) in fieldsForNum.enumerated() {
                    let elemComma = i == fieldsForNum.count - 1 ? "" : ","
                    let formatted = formatValuePretty(field.value, type: type, schema: schema, indent: indent + 2)
                    if formatted.contains("\n") {
                        lines.append("\(formatted)\(elemComma)")
                    } else {
                        lines.append("\(arrayPad)\(formatted)\(elemComma)")
                    }
                }
                lines.append("\(innerPad)]\(comma)")
            } else {
                let formatted = formatValuePretty(fieldsForNum[0].value, type: type, schema: schema, indent: indent + 1)
                if formatted.contains("\n") {
                    lines.append("\(innerPad)\"\(name)\": \(formatted.trimmingCharacters(in: .whitespaces))\(comma)")
                } else {
                    lines.append("\(innerPad)\"\(name)\": \(formatted)\(comma)")
                }
            }
        }

        lines.append("\(pad)}")
        return lines.joined(separator: "\n")
    }

    // MARK: - Grouping & Value Helpers

    /// Group fields by field number, preserving first-seen order
    private static func groupByFieldNumber(_ fields: [ProtobufField]) -> [(Int, [ProtobufField])] {
        var groups: [(Int, [ProtobufField])] = []
        var seen: [Int: Int] = [:] // fieldNumber → index in groups
        for field in fields {
            if let idx = seen[field.fieldNumber] {
                groups[idx].1.append(field)
            } else {
                seen[field.fieldNumber] = groups.count
                groups.append((field.fieldNumber, [field]))
            }
        }
        return groups
    }

    private static func formatValueFlat(_ value: ProtobufValue, type: String?, schema: ProtoSchema) -> String {
        switch value {
        case let .varint(v):
            return formatVarint(v, type: type, schema: schema)
        case let .fixed64(v):
            return formatFixed64(v, type: type)
        case let .lengthDelimited(bytes):
            return formatLengthDelimited(bytes, type: type, schema: schema, flat: true)
        case let .fixed32(v):
            return formatFixed32(v, type: type)
        case let .nested(sub):
            if let type, schema.messages[type] != nil {
                return formatFlatWithSchema(sub, schema: schema, messageType: type)
            }
            return formatFieldsFlat(sub)
        }
    }

    private static func formatValuePretty(_ value: ProtobufValue, type: String?, schema: ProtoSchema, indent: Int) -> String {
        switch value {
        case let .varint(v):
            return formatVarint(v, type: type, schema: schema)
        case let .fixed64(v):
            return formatFixed64(v, type: type)
        case let .lengthDelimited(bytes):
            return formatLengthDelimited(bytes, type: type, schema: schema, flat: false, indent: indent)
        case let .fixed32(v):
            return formatFixed32(v, type: type)
        case let .nested(sub):
            if let type, schema.messages[type] != nil {
                return formatPrettyWithSchema(sub, schema: schema, messageType: type, indent: indent)
            }
            return formatFieldsPretty(sub, indent: indent)
        }
    }

    // MARK: - Type-Specific Formatting

    private static func formatVarint(_ v: UInt64, type: String?, schema: ProtoSchema) -> String {
        guard let type else { return String(v) }
        switch type {
        case "bool":
            return v != 0 ? "true" : "false"
        case "sint32":
            let decoded = (v >> 1) ^ (0 &- (v & 1))
            return String(Int32(truncatingIfNeeded: decoded))
        case "sint64":
            let decoded = (v >> 1) ^ (0 &- (v & 1))
            return String(Int64(bitPattern: decoded))
        case "int32":
            return String(Int32(truncatingIfNeeded: v))
        case "int64":
            return String(Int64(bitPattern: v))
        default:
            // Check if it's an enum type
            if let enumDef = schema.enums[type] {
                let intVal = Int(v)
                return "\"\(enumDef.values[intVal] ?? "UNKNOWN_\(intVal)")\""
            }
            return String(v)
        }
    }

    private static func formatFixed64(_ v: UInt64, type: String?) -> String {
        guard let type else { return String(v) }
        switch type {
        case "double":
            return String(Double(bitPattern: v))
        case "sfixed64":
            return String(Int64(bitPattern: v))
        default:
            return String(v)
        }
    }

    private static func formatFixed32(_ v: UInt32, type: String?) -> String {
        guard let type else { return String(v) }
        switch type {
        case "float":
            return String(Float(bitPattern: v))
        case "sfixed32":
            return String(Int32(bitPattern: v))
        default:
            return String(v)
        }
    }

    private static func formatLengthDelimited(
        _ bytes: Data,
        type: String?,
        schema: ProtoSchema,
        flat: Bool,
        indent: Int = 0,
    ) -> String {
        guard let type else {
            // No type info — try UTF-8, fallback to binary indicator
            if let str = String(data: bytes, encoding: .utf8), !bytes.contains(0) {
                return "\"\(str.replacingOccurrences(of: "\"", with: "\\\""))\""
            }
            return "\"<\(bytes.count) bytes>\""
        }

        switch type {
        case "string":
            if let str = String(data: bytes, encoding: .utf8) {
                return "\"\(str.replacingOccurrences(of: "\"", with: "\\\""))\""
            }
            return "\"<invalid utf8: \(bytes.count) bytes>\""
        case "bytes":
            let hex = bytes.prefix(32).map { String(format: "%02x", $0) }.joined()
            let suffix = bytes.count > 32 ? "..." : ""
            return "\"<\(bytes.count)B: \(hex)\(suffix)>\""
        default:
            // Try to decode as nested message
            if schema.messages[type] != nil {
                do {
                    var decoder = ProtobufWireDecoder(data: bytes)
                    let subFields = try decoder.decodeFields()
                    if flat {
                        return formatFlatWithSchema(subFields, schema: schema, messageType: type)
                    } else {
                        return formatPrettyWithSchema(subFields, schema: schema, messageType: type, indent: indent)
                    }
                } catch {
                    // Nested decode failed — fall through
                }
            }
            // Unknown type — try as string, fallback to binary
            if let str = String(data: bytes, encoding: .utf8), !bytes.contains(0) {
                return "\"\(str.replacingOccurrences(of: "\"", with: "\\\""))\""
            }
            return "\"<\(bytes.count) bytes>\""
        }
    }
}

// MARK: - Protobuf Configuration Manager

/// Manages .proto file imports and message type registrations, scoped per cluster.
/// Proto file content is stored on disk at ~/Library/Application Support/Swifka/protos/<uuid>_<fileName>.proto.
/// Metadata index is stored alongside as proto_index.json.
@MainActor
@Observable
final class ProtobufConfigManager {
    static let shared = ProtobufConfigManager()

    /// All proto files across all clusters
    private(set) var allProtoFiles: [ProtoFileInfo] = []

    /// Cached parsed schemas keyed by proto file ID
    @ObservationIgnored
    private var schemaCache: [UUID: ProtoSchema] = [:]

    @ObservationIgnored
    private let protosDir: URL

    @ObservationIgnored
    private let indexURL: URL

    private init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
        ).first!
        let baseDir = appSupport.appendingPathComponent(Constants.configDirectory)
        protosDir = baseDir.appendingPathComponent(Constants.protosDirectory)
        indexURL = baseDir.appendingPathComponent(Constants.protoIndexFileName)

        try? FileManager.default.createDirectory(at: protosDir, withIntermediateDirectories: true)

        // Clean up legacy UserDefaults storage if present
        UserDefaults.standard.removeObject(forKey: "proto_files")

        load()
    }

    /// Get (or parse and cache) the schema for a proto file
    func schema(for protoFileID: UUID) -> ProtoSchema? {
        if let cached = schemaCache[protoFileID] {
            return cached
        }
        guard let file = allProtoFiles.first(where: { $0.id == protoFileID }) else {
            return nil
        }
        let schema = ProtoSchemaParser.parse(file.content)
        schemaCache[protoFileID] = schema
        return schema
    }

    /// Proto files for a specific cluster
    func protoFiles(for clusterID: UUID) -> [ProtoFileInfo] {
        allProtoFiles.filter { $0.clusterID == clusterID }
    }

    /// Import a .proto file from disk for a specific cluster
    func importProtoFile(from url: URL, clusterID: UUID) throws {
        guard url.pathExtension == "proto" else {
            throw ProtobufError.invalidFileType
        }

        let content = try String(contentsOf: url, encoding: .utf8)
        let messageTypes = parseMessageTypes(from: content)
        let id = UUID()
        let originalFileName = url.lastPathComponent

        let protoInfo = ProtoFileInfo(
            id: id,
            clusterID: clusterID,
            fileName: originalFileName,
            filePath: protoFilePath(for: id, fileName: originalFileName),
            content: content,
            messageTypes: messageTypes,
            importedAt: Date(),
        )

        writeProtoContent(content, for: id, fileName: originalFileName)
        allProtoFiles.append(protoInfo)
        saveIndex()
    }

    /// Import proto files from cluster export (remapping cluster IDs).
    /// Preserves original proto file ID when no collision exists locally.
    /// Returns a mapping of old filePath → new filePath for deserializer config remapping.
    @discardableResult
    func importProtoFiles(_ files: [ProtoFileInfo], clusterIDMap: [UUID: UUID]) -> [String: String] {
        var pathMap: [String: String] = [:]
        let existingIDs = Set(allProtoFiles.map(\.id))
        for file in files {
            guard let newClusterID = clusterIDMap[file.clusterID] else { continue }
            let effectiveID = existingIDs.contains(file.id) ? UUID() : file.id
            let newPath = protoFilePath(for: effectiveID, fileName: file.fileName)
            pathMap[file.filePath] = newPath
            let imported = ProtoFileInfo(
                id: effectiveID,
                clusterID: newClusterID,
                fileName: file.fileName,
                filePath: newPath,
                content: file.content,
                messageTypes: file.messageTypes,
                importedAt: Date(),
            )
            writeProtoContent(file.content, for: effectiveID, fileName: file.fileName)
            allProtoFiles.append(imported)
        }
        saveIndex()
        return pathMap
    }

    /// Remove a proto file
    func removeProtoFile(_ id: UUID) {
        let fileName = allProtoFiles.first { $0.id == id }?.fileName ?? ""
        allProtoFiles.removeAll { $0.id == id }
        schemaCache.removeValue(forKey: id)
        deleteProtoContent(for: id, fileName: fileName)
        saveIndex()
    }

    /// Remove all proto files for a cluster
    func removeProtoFiles(for clusterID: UUID) {
        let toRemove = allProtoFiles.filter { $0.clusterID == clusterID }
        allProtoFiles.removeAll { $0.clusterID == clusterID }
        for file in toRemove {
            schemaCache.removeValue(forKey: file.id)
            deleteProtoContent(for: file.id, fileName: file.fileName)
        }
        saveIndex()
    }

    /// Get message types from a specific proto file
    func messageTypes(for protoFileID: UUID) -> [String] {
        allProtoFiles.first { $0.id == protoFileID }?.messageTypes ?? []
    }

    // MARK: - Disk Storage

    /// Disk filename for a proto file: <uuid>_<originalFileName>.proto
    private func diskFileName(for id: UUID, fileName: String) -> String {
        // Strip .proto extension from original name since we add it back
        let baseName = fileName.hasSuffix(".proto")
            ? String(fileName.dropLast(6))
            : fileName
        return "\(id.uuidString)_\(baseName).proto"
    }

    /// Managed path for a proto file: ~/Library/Application Support/Swifka/protos/<uuid>_<name>.proto
    private func protoFilePath(for id: UUID, fileName: String) -> String {
        protosDir.appendingPathComponent(diskFileName(for: id, fileName: fileName)).path
    }

    private func writeProtoContent(_ content: String, for id: UUID, fileName: String) {
        let url = protosDir.appendingPathComponent(diskFileName(for: id, fileName: fileName))
        try? content.write(to: url, atomically: true, encoding: .utf8)
    }

    private func readProtoContent(for id: UUID, fileName: String) -> String? {
        let url = protosDir.appendingPathComponent(diskFileName(for: id, fileName: fileName))
        return try? String(contentsOf: url, encoding: .utf8)
    }

    private func deleteProtoContent(for id: UUID, fileName: String) {
        let url = protosDir.appendingPathComponent(diskFileName(for: id, fileName: fileName))
        try? FileManager.default.removeItem(at: url)
    }

    /// Save metadata index (without content — content lives in individual .proto files)
    private func saveIndex() {
        let metadata = allProtoFiles.map { ProtoFileMetadata(from: $0) }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(metadata) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    /// Load metadata index and fill in content from individual .proto files
    private func load() {
        guard let data = try? Data(contentsOf: indexURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let metadata = try? decoder.decode([ProtoFileMetadata].self, from: data) else { return }

        allProtoFiles = metadata.compactMap { meta in
            guard let content = readProtoContent(for: meta.id, fileName: meta.fileName) else { return nil }
            return ProtoFileInfo(
                id: meta.id,
                clusterID: meta.clusterID,
                fileName: meta.fileName,
                filePath: protoFilePath(for: meta.id, fileName: meta.fileName),
                content: content,
                messageTypes: meta.messageTypes,
                importedAt: meta.importedAt,
            )
        }
    }

    // MARK: - Private Helpers

    private func parseMessageTypes(from content: String) -> [String] {
        var types: [String] = []

        let pattern = #"message\s+(\w+)\s*\{"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return types
        }

        let range = NSRange(content.startIndex..., in: content)
        let matches = regex.matches(in: content, range: range)

        for match in matches {
            if let messageNameRange = Range(match.range(at: 1), in: content) {
                let messageName = String(content[messageNameRange])
                types.append(messageName)
            }
        }

        return types
    }
}

/// Metadata-only struct for the on-disk index (content stored in separate .proto files)
private struct ProtoFileMetadata: Codable {
    let id: UUID
    let clusterID: UUID
    let fileName: String
    let messageTypes: [String]
    let importedAt: Date

    init(id: UUID, clusterID: UUID, fileName: String, messageTypes: [String], importedAt: Date) {
        self.id = id
        self.clusterID = clusterID
        self.fileName = fileName
        self.messageTypes = messageTypes
        self.importedAt = importedAt
    }

    init(from info: ProtoFileInfo) {
        id = info.id
        clusterID = info.clusterID
        fileName = info.fileName
        messageTypes = info.messageTypes
        importedAt = info.importedAt
    }
}

// MARK: - Supporting Types

struct ProtoFileInfo: Codable, Identifiable, Sendable {
    let id: UUID
    let clusterID: UUID
    let fileName: String
    let filePath: String
    let content: String
    let messageTypes: [String]
    let importedAt: Date
}

enum ProtobufError: LocalizedError {
    case invalidFileType
    case parseError
    case messageTypeNotFound
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidFileType:
            "File must have .proto extension"
        case .parseError:
            "Failed to parse .proto file"
        case .messageTypeNotFound:
            "Message type not found in proto file"
        case let .decodingFailed(reason):
            "Protobuf decoding failed: \(reason)"
        }
    }
}

// MARK: - Protobuf Wire Format Decoder

/// Decodes protobuf binary data using the wire format specification
/// Wire types: 0=varint, 1=64-bit, 2=length-delimited, 5=32-bit
nonisolated struct ProtobufWireDecoder {
    private let data: Data
    private var position = 0

    init(data: Data) {
        // Ensure contiguous 0-based indexing (Data slices from readBytes retain parent indices)
        self.data = data.startIndex == 0 ? data : Data(data)
    }

    mutating func decodeFields() throws -> [ProtobufField] {
        var fields: [ProtobufField] = []

        while position < data.count {
            // Read field key (field_number << 3 | wire_type)
            let key = try readVarint()
            let fieldNumber = Int(key >> 3)
            let wireType = Int(key & 0x07)

            // Decode based on wire type
            let value: ProtobufValue
            switch wireType {
            case 0: // Varint
                let varint = try readVarint()
                value = .varint(varint)

            case 1: // 64-bit
                let fixed64 = try readFixed64()
                value = .fixed64(fixed64)

            case 2: // Length-delimited
                let length = try readVarint()
                let bytes = try readBytes(count: Int(length))
                value = .lengthDelimited(bytes)

            case 5: // 32-bit
                let fixed32 = try readFixed32()
                value = .fixed32(fixed32)

            default:
                throw ProtobufError.decodingFailed("Unknown wire type: \(wireType)")
            }

            fields.append(ProtobufField(fieldNumber: fieldNumber, value: value))
        }

        return fields
    }

    private mutating func readVarint() throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0

        while position < data.count {
            let byte = data[position]
            position += 1

            result |= UInt64(byte & 0x7F) << shift

            if (byte & 0x80) == 0 {
                return result
            }

            shift += 7
            if shift >= 64 {
                throw ProtobufError.decodingFailed("Varint overflow")
            }
        }

        throw ProtobufError.decodingFailed("Unexpected end of data while reading varint")
    }

    private mutating func readFixed64() throws -> UInt64 {
        guard position + 8 <= data.count else {
            throw ProtobufError.decodingFailed("Not enough bytes for fixed64")
        }

        let bytes = data[position ..< position + 8]
        position += 8

        return bytes.withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) }
    }

    private mutating func readFixed32() throws -> UInt32 {
        guard position + 4 <= data.count else {
            throw ProtobufError.decodingFailed("Not enough bytes for fixed32")
        }

        let bytes = data[position ..< position + 4]
        position += 4

        return bytes.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
    }

    private mutating func readBytes(count: Int) throws -> Data {
        guard position + count <= data.count else {
            throw ProtobufError.decodingFailed("Not enough bytes for length-delimited field")
        }

        let bytes = data[position ..< position + count]
        position += count

        return bytes
    }
}

struct ProtobufField {
    let fieldNumber: Int
    let value: ProtobufValue
}

enum ProtobufValue {
    case varint(UInt64)
    case fixed64(UInt64)
    case lengthDelimited(Data)
    case fixed32(UInt32)
    case nested([ProtobufField])
}

// MARK: - Proto Schema Types

/// Context passed to format methods for schema-aware protobuf decoding
struct ProtobufContext: Sendable {
    let schema: ProtoSchema
    let messageTypeName: String
}

/// Parsed .proto file schema containing message and enum definitions
struct ProtoSchema: Sendable {
    let messages: [String: ProtoMessageDef]
    let enums: [String: ProtoEnumDef]
    let packageName: String?
}

/// A protobuf message definition with its field mappings
struct ProtoMessageDef: Sendable {
    let name: String
    let fields: [Int: ProtoFieldDef] // field number → definition
}

/// A single field within a protobuf message
struct ProtoFieldDef: Sendable {
    let number: Int
    let name: String
    let typeName: String // "string", "int32", "double", "Customer", etc.
    let isRepeated: Bool
}

/// A protobuf enum definition with value-to-name mappings
struct ProtoEnumDef: Sendable {
    let name: String
    let values: [Int: String] // number → symbolic name
}

// MARK: - Proto Schema Parser

/// Parses .proto file content into a structured ProtoSchema
enum ProtoSchemaParser {
    static func parse(_ content: String) -> ProtoSchema {
        let stripped = stripComments(content)
        var messages: [String: ProtoMessageDef] = [:]
        var enums: [String: ProtoEnumDef] = [:]
        var packageName: String?

        // Extract package name
        if let regex = try? NSRegularExpression(pattern: #"package\s+([\w.]+)\s*;"#),
           let match = regex.firstMatch(in: stripped, range: NSRange(stripped.startIndex..., in: stripped)),
           let range = Range(match.range(at: 1), in: stripped)
        {
            packageName = String(stripped[range])
        }

        // Parse all message and enum blocks
        parseBlocks(stripped, messages: &messages, enums: &enums)

        return ProtoSchema(messages: messages, enums: enums, packageName: packageName)
    }

    private static func stripComments(_ content: String) -> String {
        var result = content
        // Remove single-line comments
        result = result.replacingOccurrences(of: #"//[^\n]*"#, with: "", options: .regularExpression)
        // Remove multi-line comments
        result = result.replacingOccurrences(of: #"/\*[\s\S]*?\*/"#, with: "", options: .regularExpression)
        return result
    }

    private static func parseBlocks(
        _ content: String,
        messages: inout [String: ProtoMessageDef],
        enums: inout [String: ProtoEnumDef],
    ) {
        guard let blockRegex = try? NSRegularExpression(pattern: #"(message|enum)\s+(\w+)\s*\{"#) else { return }
        var searchStart = content.startIndex

        while searchStart < content.endIndex {
            let searchRange = NSRange(searchStart..., in: content)
            guard let match = blockRegex.firstMatch(in: content, range: searchRange),
                  let keywordRange = Range(match.range(at: 1), in: content),
                  let nameRange = Range(match.range(at: 2), in: content),
                  let fullRange = Range(match.range, in: content)
            else { break }

            let keyword = String(content[keywordRange])
            let name = String(content[nameRange])
            let openBrace = content.index(before: fullRange.upperBound)

            guard let closeBrace = findMatchingBrace(in: content, from: openBrace) else {
                searchStart = fullRange.upperBound
                continue
            }

            let body = String(content[content.index(after: openBrace) ..< closeBrace])

            if keyword == "message" {
                // Recursively parse nested message/enum definitions
                parseBlocks(body, messages: &messages, enums: &enums)
                let fields = parseMessageFields(body)
                messages[name] = ProtoMessageDef(name: name, fields: fields)
            } else {
                let values = parseEnumValues(body)
                enums[name] = ProtoEnumDef(name: name, values: values)
            }

            searchStart = content.index(after: closeBrace)
        }
    }

    private static func findMatchingBrace(in content: String, from start: String.Index) -> String.Index? {
        guard content[start] == "{" else { return nil }
        var depth = 1
        var i = content.index(after: start)
        while i < content.endIndex {
            if content[i] == "{" { depth += 1 }
            if content[i] == "}" { depth -= 1 }
            if depth == 0 { return i }
            i = content.index(after: i)
        }
        return nil
    }

    private static func parseMessageFields(_ body: String) -> [Int: ProtoFieldDef] {
        var fields: [Int: ProtoFieldDef] = [:]

        // Pattern: (repeated)? type name = number ;
        // Note: [;\[] — the \[ escapes the bracket inside the character class for ICU regex
        guard let regex = try? NSRegularExpression(
            pattern: #"(repeated\s+)?([\w.]+)\s+(\w+)\s*=\s*(\d+)\s*[;\[]"#,
        ) else { return fields }

        let range = NSRange(body.startIndex..., in: body)
        for match in regex.matches(in: body, range: range) {
            let isRepeated = match.range(at: 1).location != NSNotFound

            guard let typeRange = Range(match.range(at: 2), in: body),
                  let nameRange = Range(match.range(at: 3), in: body),
                  let numberRange = Range(match.range(at: 4), in: body),
                  let number = Int(body[numberRange])
            else { continue }

            let typeName = String(body[typeRange])
            let name = String(body[nameRange])

            // Skip nested message/enum keywords picked up by regex
            if typeName == "message" || typeName == "enum" { continue }

            fields[number] = ProtoFieldDef(
                number: number,
                name: name,
                typeName: typeName,
                isRepeated: isRepeated,
            )
        }

        return fields
    }

    private static func parseEnumValues(_ body: String) -> [Int: String] {
        var values: [Int: String] = [:]

        guard let regex = try? NSRegularExpression(
            pattern: #"(\w+)\s*=\s*(-?\d+)\s*;"#,
        ) else { return values }

        let range = NSRange(body.startIndex..., in: body)
        for match in regex.matches(in: body, range: range) {
            guard let nameRange = Range(match.range(at: 1), in: body),
                  let numberRange = Range(match.range(at: 2), in: body),
                  let number = Int(body[numberRange])
            else { continue }

            values[number] = String(body[nameRange])
        }

        return values
    }
}
