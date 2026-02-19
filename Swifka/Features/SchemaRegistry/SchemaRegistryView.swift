import SwiftUI

struct SchemaRegistryView: View {
    @Environment(AppState.self) private var appState

    @State private var subjects: [String] = []
    @State private var selectedSubject: String?
    @State private var versions: [Int] = []
    @State private var selectedVersion: Int?
    @State private var currentSchema: SchemaInfo?
    @State private var isLoadingSubjects = false
    @State private var isLoadingSchema = false
    @State private var error: String?
    @State private var searchQuery = ""
    @State private var schemaCopied = false

    private var filteredSubjects: [String] {
        if searchQuery.isEmpty { return subjects }
        return subjects.filter { $0.localizedCaseInsensitiveContains(searchQuery) }
    }

    var body: some View {
        let l10n = appState.l10n

        if appState.schemaRegistryClient == nil {
            ContentUnavailableView(
                l10n["schema.not.configured"],
                systemImage: "doc.text.magnifyingglass",
                description: Text(l10n["schema.not.configured.description"]),
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !appState.connectionStatus.isConnected {
            ContentUnavailableView(
                l10n["schema.not.connected"],
                systemImage: "doc.text.magnifyingglass",
                description: Text(l10n["schema.not.connected.description"]),
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                summaryBar

                HStack(spacing: 0) {
                    subjectsList
                    Divider()
                    schemaDetail
                }
            }
            .onAppear { loadSubjects() }
            .onChange(of: appState.connectionStatus.isConnected) {
                if appState.connectionStatus.isConnected {
                    loadSubjects()
                } else {
                    subjects = []
                    selectedSubject = nil
                }
            }
        }
    }

    // MARK: - Summary Bar

    @ViewBuilder
    private var summaryBar: some View {
        let l10n = appState.l10n

        HStack(spacing: 16) {
            HStack(spacing: 6) {
                Image(systemName: "doc.text.magnifyingglass")
                    .foregroundStyle(.blue)
                    .font(.system(size: 12))
                Text("\(subjects.count)")
                    .font(.headline.monospacedDigit())
                    .contentTransition(.numericText())
                Text(l10n["schema.summary.subjects"])
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !searchQuery.isEmpty {
                Text(l10n.t("messages.search.results", String(filteredSubjects.count), String(subjects.count)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isLoadingSubjects {
                ProgressView()
                    .controlSize(.small)
            }

            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - Subjects List

    @ViewBuilder
    private var subjectsList: some View {
        let l10n = appState.l10n

        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 13))
                TextField(l10n["schema.search"], text: $searchQuery)
                    .textFieldStyle(.plain)
                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            .padding(8)

            Divider()

            if filteredSubjects.isEmpty {
                ContentUnavailableView(
                    l10n["schema.no.subjects"],
                    systemImage: "doc.text",
                    description: Text(searchQuery.isEmpty
                        ? l10n["schema.no.subjects.description"]
                        : l10n["schema.no.results"]),
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredSubjects, id: \.self, selection: $selectedSubject) { subject in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(subject)
                            .lineLimit(1)
                        if subject.hasSuffix("-value") {
                            Text("value")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 3))
                        } else if subject.hasSuffix("-key") {
                            Text("key")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 3))
                        }
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.sidebar)
            }
        }
        .frame(minWidth: 200, idealWidth: 280, maxWidth: 350)
        .onChange(of: selectedSubject) {
            schemaCopied = false
            if let subject = selectedSubject {
                loadVersions(for: subject)
            } else {
                versions = []
                selectedVersion = nil
                currentSchema = nil
            }
        }
    }

    // MARK: - Schema Detail

    @ViewBuilder
    private var schemaDetail: some View {
        let l10n = appState.l10n

        if let subject = selectedSubject {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(subject)
                            .font(.headline)
                        HStack(spacing: 8) {
                            schemaTypeBadge(currentSchema?.schemaType ?? .json)
                            Text("ID: \(currentSchema?.id ?? 0)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .opacity(currentSchema != nil ? 1 : 0)
                    }

                    Spacer()

                    Picker(l10n["schema.version"], selection: Binding(
                        get: { selectedVersion },
                        set: { newVersion in
                            selectedVersion = newVersion
                            if let version = newVersion {
                                loadSchema(subject: subject, version: version)
                            }
                        },
                    )) {
                        ForEach(versions.reversed(), id: \.self) { version in
                            Text("v\(version)").tag(version as Int?)
                        }
                    }
                    .fixedSize()
                    .opacity(versions.isEmpty ? 0 : 1)
                }
                .padding(12)

                Divider()

                // Schema content
                ZStack(alignment: .topTrailing) {
                    if isLoadingSchema {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let schema = currentSchema {
                        ScrollView([.horizontal, .vertical]) {
                            Text(prettyPrintSchema(schema.schema))
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                                .lineLimit(nil)
                                .fixedSize(horizontal: true, vertical: false)
                                .padding(12)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    } else {
                        ContentUnavailableView(
                            l10n["schema.select.version"],
                            systemImage: "doc.text",
                            description: Text(l10n["schema.select.version.description"]),
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }

                    Button {
                        if let schema = currentSchema {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(prettyPrintSchema(schema.schema), forType: .string)
                            schemaCopied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                schemaCopied = false
                            }
                        }
                    } label: {
                        ZStack {
                            Label(l10n["common.copied"], systemImage: "checkmark")
                                .opacity(schemaCopied ? 1 : 0)
                            Label(l10n["common.copy"], systemImage: "doc.on.doc")
                                .opacity(schemaCopied ? 0 : 1)
                        }
                        .font(.caption)
                        .foregroundStyle(schemaCopied ? .green : .secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                    .opacity(currentSchema != nil ? 1 : 0)
                }
            }
        } else {
            ContentUnavailableView(
                l10n["schema.select.subject"],
                systemImage: "doc.text.magnifyingglass",
                description: Text(l10n["schema.select.subject.description"]),
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func schemaTypeBadge(_ type: SchemaType) -> some View {
        let color: Color = switch type {
        case .protobuf: .blue
        case .avro: .orange
        case .json: .green
        }

        Text(type.rawValue)
            .font(.caption2.bold())
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Data Loading

    private func loadSubjects() {
        guard let client = appState.schemaRegistryClient else { return }
        isLoadingSubjects = true
        error = nil

        Task {
            do {
                let result = try await client.fetchSubjects()
                subjects = result.sorted()
                isLoadingSubjects = false
            } catch {
                self.error = error.localizedDescription
                isLoadingSubjects = false
            }
        }
    }

    private func loadVersions(for subject: String) {
        guard let client = appState.schemaRegistryClient else { return }
        isLoadingSchema = true

        Task {
            do {
                let result = try await client.fetchVersions(subject: subject)
                guard selectedSubject == subject else { return }
                versions = result
                // Auto-select latest version
                if let latest = result.last {
                    selectedVersion = latest
                    loadSchema(subject: subject, version: latest)
                } else {
                    isLoadingSchema = false
                }
            } catch {
                guard selectedSubject == subject else { return }
                self.error = error.localizedDescription
                isLoadingSchema = false
            }
        }
    }

    private func loadSchema(subject: String, version: Int) {
        guard let client = appState.schemaRegistryClient else { return }
        isLoadingSchema = true
        schemaCopied = false

        Task {
            do {
                let schema = try await client.fetchSchema(subject: subject, version: version)
                guard selectedSubject == subject, selectedVersion == version else { return }
                currentSchema = schema
                isLoadingSchema = false
            } catch {
                guard selectedSubject == subject else { return }
                self.error = error.localizedDescription
                isLoadingSchema = false
            }
        }
    }

    /// Try to pretty-print JSON strings; return as-is for non-JSON (e.g. Protobuf).
    private func prettyPrintSchema(_ raw: String) -> String {
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
              let result = String(data: pretty, encoding: .utf8)
        else {
            return raw
        }
        return result
    }
}
