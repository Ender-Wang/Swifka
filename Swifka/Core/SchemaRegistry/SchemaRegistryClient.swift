import Foundation
import OSLog

// MARK: - Schema Registry Client

/// Actor-based HTTP client for Confluent-compatible Schema Registry REST API.
/// All operations are read-only. Schema IDs are immutable — once cached, entries never need invalidation.
actor SchemaRegistryClient {
    private let baseURL: URL
    private let session: URLSession

    /// In-memory cache: schema ID → SchemaInfo
    /// Schema IDs are globally unique and immutable in the registry.
    private var schemaCache: [Int: SchemaInfo] = [:]

    init(baseURL: URL) {
        self.baseURL = baseURL
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 30
        session = URLSession(configuration: config)
    }

    // MARK: - Public API

    /// List all registered subjects.
    func fetchSubjects() async throws -> [String] {
        let url = baseURL.appendingPathComponent("subjects")
        let data = try await fetch(url)
        let subjects = try JSONDecoder().decode([String].self, from: data)
        Log.decode.debug("[SchemaRegistryClient] fetchSubjects: \(subjects.count) subjects")
        return subjects
    }

    /// List all version numbers for a subject.
    func fetchVersions(subject: String) async throws -> [Int] {
        let url = baseURL
            .appendingPathComponent("subjects")
            .appendingPathComponent(subject)
            .appendingPathComponent("versions")
        let data = try await fetch(url)
        return try JSONDecoder().decode([Int].self, from: data)
    }

    /// Fetch a specific schema version for a subject.
    func fetchSchema(subject: String, version: Int) async throws -> SchemaInfo {
        let url = baseURL
            .appendingPathComponent("subjects")
            .appendingPathComponent(subject)
            .appendingPathComponent("versions")
            .appendingPathComponent("\(version)")
        let data = try await fetch(url)
        let response = try JSONDecoder().decode(SubjectVersionResponse.self, from: data)

        let info = SchemaInfo(
            id: response.id,
            subject: response.subject,
            version: response.version,
            schemaType: SchemaType(rawValue: response.schemaType ?? "AVRO") ?? .avro,
            schema: response.schema,
        )

        // Cache by ID
        schemaCache[info.id] = info
        return info
    }

    /// Fetch a schema by its global ID. Uses cache if available.
    func fetchSchemaByID(_ id: Int) async throws -> SchemaInfo {
        if let cached = schemaCache[id] {
            Log.decode.debug("[SchemaRegistryClient] fetchSchemaByID: cache hit for ID \(id)")
            return cached
        }

        let url = baseURL
            .appendingPathComponent("schemas")
            .appendingPathComponent("ids")
            .appendingPathComponent("\(id)")
        let data = try await fetch(url)
        let response = try JSONDecoder().decode(SchemaByIDResponse.self, from: data)

        let info = SchemaInfo(
            id: id,
            subject: nil,
            version: nil,
            schemaType: SchemaType(rawValue: response.schemaType ?? "AVRO") ?? .avro,
            schema: response.schema,
        )

        schemaCache[id] = info
        Log.decode.debug("[SchemaRegistryClient] fetchSchemaByID: fetched ID \(id) — \(info.schemaType.rawValue, privacy: .public)")
        return info
    }

    /// Check if the registry is reachable.
    func healthCheck() async throws -> Bool {
        let url = baseURL.appendingPathComponent("subjects")
        let (_, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse else { return false }
        return httpResponse.statusCode == 200
    }

    /// Clear all cached schemas.
    func clearCache() {
        schemaCache.removeAll()
    }

    // MARK: - Private

    private func fetch(_ url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SchemaRegistryError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            return data
        case 401:
            Log.decode.error("[SchemaRegistryClient] fetch: HTTP 401 unauthorized for \(url.path, privacy: .public)")
            throw SchemaRegistryError.unauthorized
        case 404:
            Log.decode.error("[SchemaRegistryClient] fetch: HTTP 404 not found for \(url.path, privacy: .public)")
            throw SchemaRegistryError.notFound
        default:
            Log.decode.error("[SchemaRegistryClient] fetch: HTTP \(httpResponse.statusCode) for \(url.path, privacy: .public)")
            throw SchemaRegistryError.httpError(httpResponse.statusCode)
        }
    }
}

// MARK: - Errors

enum SchemaRegistryError: LocalizedError, Sendable {
    case invalidResponse
    case unauthorized
    case notFound
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "Invalid response from Schema Registry"
        case .unauthorized: "Authentication required"
        case .notFound: "Schema not found"
        case let .httpError(code): "HTTP error \(code)"
        }
    }
}
