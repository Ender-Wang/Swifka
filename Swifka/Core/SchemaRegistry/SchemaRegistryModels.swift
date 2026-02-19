import Foundation

// MARK: - Schema Registry Models

enum SchemaType: String, Codable, Sendable {
    case avro = "AVRO"
    case protobuf = "PROTOBUF"
    case json = "JSON"
}

struct SchemaInfo: Sendable, Identifiable {
    let id: Int
    let subject: String?
    let version: Int?
    let schemaType: SchemaType
    let schema: String
}

nonisolated struct SubjectVersion: Sendable, Identifiable, Codable {
    let subject: String
    let id: Int
    let version: Int
    let schemaType: String?
    let schema: String

    /// Codable mapping for registry JSON response
    private enum CodingKeys: String, CodingKey {
        case subject, id, version, schemaType, schema
    }
}

/// Response from GET /schemas/ids/{id}
nonisolated struct SchemaByIDResponse: Codable, Sendable {
    let schema: String
    let schemaType: String?
}

/// Response from GET /subjects/{subject}/versions/{version}
nonisolated struct SubjectVersionResponse: Codable, Sendable {
    let subject: String
    let id: Int
    let version: Int
    let schemaType: String?
    let schema: String
}
