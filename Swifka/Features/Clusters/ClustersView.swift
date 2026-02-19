import SwiftUI
import UniformTypeIdentifiers

struct ClustersView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = ConnectionViewModel()
    @State private var clusterToDelete: ClusterConfig?
    @State private var showDeleteConfirmation = false
    @State private var testingClusterId: UUID?
    @State private var clusterPingResults: [UUID: Int] = [:]
    @State private var pingFailedIds: Set<UUID> = []
    @State private var banner: BannerInfo?

    // Keyboard navigation
    @State private var keyboardSelectedClusterId: UUID?
    @FocusState private var isListFocused: Bool

    /// Drag-to-sort and drag-to-pin
    @State private var draggedCluster: ClusterConfig?

    // Export/Import
    @State private var showingExportSelectionSheet = false
    @State private var selectedClustersForExport: Set<UUID> = []
    @State private var showingExportSheet = false
    @State private var exportData: Data?

    @State private var showingImportSheet = false
    @State private var showingImportSelectionSheet = false
    @State private var importableClusters: [ClusterConfig] = []
    @State private var importableProtoFiles: [ProtoFileInfo] = []
    @State private var importableDeserializerConfigs: [TopicDeserializerConfig] = []
    @State private var selectedClustersForImport: Set<UUID> = []
    @State private var showingImportModeDialog = false
    @State private var pendingImportData: Data?
    @State private var missingPasswordClusters: [String] = []
    @State private var showMissingPasswordAlert = false

    /// Sorting
    @State private var sortMode: SortMode = .name

    private var exportFilename: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = formatter.string(from: Date())
        return "swifka-clusters-\(timestamp).json"
    }

    private enum SortMode: String, CaseIterable, Identifiable {
        case manual = "Manual"
        case name = "Name"
        case lastConnected = "Last Connected"
        case created = "Created"
        case modified = "Modified"

        var id: String {
            rawValue
        }
    }

    private var sortedClusters: [ClusterConfig] {
        appState.configStore.clusters.sorted { lhs, rhs in
            // Pinned clusters first
            if lhs.isPinned != rhs.isPinned {
                return lhs.isPinned
            }
            // Then sort by selected mode
            switch sortMode {
            case .manual:
                return lhs.sortOrder < rhs.sortOrder
            case .name:
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            case .lastConnected:
                // Most recent first, never connected at end
                if let lhsDate = lhs.lastConnectedAt, let rhsDate = rhs.lastConnectedAt {
                    return lhsDate > rhsDate
                } else if lhs.lastConnectedAt != nil {
                    return true
                } else if rhs.lastConnectedAt != nil {
                    return false
                } else {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
            case .created:
                return lhs.createdAt > rhs.createdAt
            case .modified:
                return lhs.updatedAt > rhs.updatedAt
            }
        }
    }

    var body: some View {
        let l10n = appState.l10n
        let sortedClusters = sortedClusters
        let pinnedClusters = sortedClusters.filter(\.isPinned)
        let unpinnedClusters = sortedClusters.filter { !$0.isPinned }

        ZStack(alignment: .top) {
            List {
                // Pinned section (only when there are pinned clusters)
                if !pinnedClusters.isEmpty {
                    Section(l10n["cluster.section.pinned"]) {
                        ForEach(pinnedClusters) { cluster in
                            clusterRow(for: cluster, isPinned: true)
                        }
                    }
                }

                // Regular clusters - no header to avoid gap
                Section {
                    ForEach(unpinnedClusters) { cluster in
                        clusterRow(for: cluster, isPinned: false)
                    }

                    // Empty drop zone for unpinning - 3x cluster row height (~200px)
                    Color.clear
                        .frame(height: 200)
                        .listRowInsets(EdgeInsets())
                        .onDrop(of: [.text], delegate: UnpinDropDelegate(
                            draggedCluster: $draggedCluster,
                            configStore: appState.configStore,
                        ))
                }
            }
            .listStyle(.inset)
            .focused($isListFocused)

            // Invisible drop zone at top for pinning (only when no pinned clusters)
            if pinnedClusters.isEmpty {
                Color.clear
                    .frame(height: 20)
                    .frame(maxWidth: .infinity)
                    .onDrop(of: [.text], delegate: PinDropDelegate(
                        draggedCluster: $draggedCluster,
                        configStore: appState.configStore,
                    ))
            }
        }
        .onKeyPress(.upArrow) {
            moveSelection(direction: .up)
            return .handled
        }
        .onKeyPress(.downArrow) {
            moveSelection(direction: .down)
            return .handled
        }
        .onKeyPress(.return) {
            connectToSelected()
            return .handled
        }
        .onKeyPress { press in
            if press.characters == "p" {
                testSelected()
                return .handled
            } else if press.characters == "e" {
                editSelected()
                return .handled
            } else if press.characters == "d", press.modifiers.contains(.command) {
                cloneSelected()
                return .handled
            } else if press.characters == "\u{7F}" || press.characters == "\u{08}" {
                // Handle delete key (forward delete \u{7F} or backspace \u{08})
                deleteSelected()
                return .handled
            }
            return .ignored
        }
        .task(id: appState.selectedSidebarItem) {
            // Auto-focus list and select first cluster when navigating to Clusters page
            if appState.selectedSidebarItem == .clusters {
                isListFocused = true
                if keyboardSelectedClusterId == nil, let first = sortedClusters.first {
                    keyboardSelectedClusterId = first.id
                }
            }
        }
        .navigationTitle(l10n["sidebar.clusters"])
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Menu {
                    Text(l10n["cluster.sort.by"])
                        .foregroundStyle(.secondary)

                    Divider()

                    ForEach(SortMode.allCases) { mode in
                        Button {
                            sortMode = mode
                        } label: {
                            HStack {
                                Text(l10n["cluster.sort.\(mode.rawValue.lowercased().replacingOccurrences(of: " ", with: "_"))"])
                                if sortMode == mode {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .help(l10n["cluster.sort"])

                Button {
                    // Show selection sheet with all clusters selected by default
                    selectedClustersForExport = Set(appState.configStore.clusters.map(\.id))
                    showingExportSelectionSheet = true
                } label: {
                    Image(systemName: "arrow.up.doc")
                }
                .help(l10n["cluster.export"])
                .keyboardShortcut("e", modifiers: .command)

                Button {
                    showingImportSheet = true
                } label: {
                    Image(systemName: "arrow.down.doc")
                }
                .help(l10n["cluster.import"])
                .keyboardShortcut("i", modifiers: .command)

                // Power button - RIGHTMOST
                if appState.connectionStatus.isConnected {
                    Button {
                        Task { await appState.disconnect() }
                    } label: {
                        Label(l10n["connection.disconnect"], systemImage: "power")
                            .labelStyle(.iconOnly)
                            .foregroundStyle(.green)
                    }
                    .help(l10n["connection.disconnect"])
                } else if appState.configStore.selectedCluster != nil {
                    Button {
                        Task { await appState.connect() }
                    } label: {
                        Label(l10n["connection.connect"], systemImage: "power")
                            .labelStyle(.iconOnly)
                            .foregroundStyle(.red)
                    }
                    .help(l10n["connection.connect"])
                } else {
                    Button {
                        // No-op - disabled state
                    } label: {
                        Label(l10n["connection.connect"], systemImage: "power")
                            .labelStyle(.iconOnly)
                            .foregroundStyle(.gray)
                    }
                    .disabled(true)
                    .help(l10n["connection.connect"])
                }
            }
        }
        .sheet(isPresented: $showingExportSelectionSheet) {
            ExportSelectionSheet(
                clusters: appState.configStore.clusters,
                selectedClusterIds: $selectedClustersForExport,
                l10n: appState.l10n,
                onExport: {
                    let selected = appState.configStore.clusters.filter { selectedClustersForExport.contains($0.id) }
                    exportData = ConfigStore.exportClusters(selected)
                    showingExportSelectionSheet = false
                    showingExportSheet = true
                },
                onCancel: {
                    showingExportSelectionSheet = false
                },
            )
        }
        .fileExporter(
            isPresented: $showingExportSheet,
            document: ClusterExportDocument(data: exportData ?? Data()),
            contentType: .json,
            defaultFilename: exportFilename,
        ) { _ in }
        .fileImporter(
            isPresented: $showingImportSheet,
            allowedContentTypes: [.json],
        ) { result in
            handleImport(result)
        }
        .sheet(isPresented: $showingImportSelectionSheet) {
            ImportSelectionSheet(
                clusters: importableClusters,
                selectedClusterIds: $selectedClustersForImport,
                l10n: appState.l10n,
                onImport: {
                    showingImportSelectionSheet = false
                    // If no existing clusters, skip mode dialog and use Replace
                    if appState.configStore.clusters.isEmpty {
                        performImport(mode: .replace)
                    } else {
                        showingImportModeDialog = true
                    }
                },
                onCancel: {
                    showingImportSelectionSheet = false
                },
            )
        }
        .alert(l10n["cluster.import.mode.title"], isPresented: $showingImportModeDialog) {
            Button(l10n["cluster.import.append"], role: .none) {
                performImport(mode: .append)
            }
            Button(l10n["cluster.import.replace"], role: .destructive) {
                performImport(mode: .replace)
            }
            Button(l10n["common.cancel"], role: .cancel) {}
        } message: {
            Text(l10n["cluster.import.mode.message"])
        }
        .alert(l10n["cluster.import.missing.passwords.title"], isPresented: $showMissingPasswordAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            let names = missingPasswordClusters.joined(separator: ", ")
            Text(l10n.t("cluster.import.missing.passwords.message", names))
        }
        .overlay {
            if appState.configStore.clusters.isEmpty {
                ContentUnavailableView(
                    l10n["cluster.none"],
                    systemImage: "square.stack.3d.up",
                    description: Text(l10n["cluster.none.description"]),
                )
            }
        }
        // Test result banner
        .overlay(alignment: .bottom) {
            if let banner {
                TestBanner(info: banner)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 16)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: banner != nil)
        .sheet(isPresented: $viewModel.showingEditSheet) {
            if let cluster = viewModel.editingCluster {
                ClusterFormView(mode: .edit(cluster)) { updated, password in
                    viewModel.updateCluster(updated, password: password, in: appState)
                }
                .environment(appState)
            }
        }
        .confirmationDialog(
            l10n["cluster.delete"],
            isPresented: $showDeleteConfirmation,
            presenting: clusterToDelete,
        ) { cluster in
            Button(l10n["common.delete"], role: .destructive) {
                Task {
                    await viewModel.deleteCluster(cluster.id, from: appState)
                }
            }
            Button(l10n["common.cancel"], role: .cancel) {}
        } message: { cluster in
            Text(l10n.t("clusters.delete.confirm", cluster.name))
        }
        .task {
            // Auto-test all disconnected clusters on page open
            await withTaskGroup(of: (UUID, Int?).self) { group in
                for cluster in appState.configStore.clusters {
                    let isConnected = appState.configStore.selectedClusterId == cluster.id
                        && appState.connectionStatus.isConnected
                    if isConnected { continue }
                    let password = cluster.authType == .sasl
                        ? KeychainManager.loadPassword(for: cluster.id)
                        : nil
                    group.addTask {
                        let start = DispatchTime.now()
                        let result = await appState.testConnection(config: cluster, password: password)
                        let elapsed = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
                        let pingMs = Int(elapsed / 1_000_000)
                        switch result {
                        case .success: return (cluster.id, pingMs)
                        case .failure: return (cluster.id, nil)
                        }
                    }
                }
                for await (id, pingMs) in group {
                    withAnimation {
                        if let pingMs {
                            clusterPingResults[id] = pingMs
                            pingFailedIds.remove(id)
                        } else {
                            clusterPingResults[id] = nil
                            pingFailedIds.insert(id)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func clusterRow(for cluster: ClusterConfig, isPinned: Bool) -> some View {
        let isConnected = appState.configStore.selectedClusterId == cluster.id
            && appState.connectionStatus.isConnected
        ClusterRow(
            cluster: cluster,
            isConnected: isConnected,
            isTesting: testingClusterId == cluster.id,
            pingMs: isConnected ? appState.pingMs : clusterPingResults[cluster.id],
            pingFailed: pingFailedIds.contains(cluster.id),
            isKeyboardSelected: keyboardSelectedClusterId == cluster.id,
            onConnect: { connectTo(cluster) },
            onEdit: { editCluster(cluster) },
            onDelete: { confirmDelete(cluster) },
            onTest: { testCluster(cluster) },
            onPin: { togglePin(cluster) },
            onClone: { cloneCluster(cluster) },
        )
        .contentShape(Rectangle())
        .onTapGesture {
            keyboardSelectedClusterId = cluster.id
            isListFocused = true
        }
        .onDrag {
            // Switch to manual sort mode when dragging
            if sortMode != .manual {
                sortMode = .manual
            }
            draggedCluster = cluster
            return NSItemProvider(object: cluster.id.uuidString as NSString)
        }
        .onDrop(of: [.text], delegate: ClusterDropDelegate(
            cluster: cluster,
            clusters: sortedClusters,
            draggedCluster: $draggedCluster,
            configStore: appState.configStore,
            targetIsPinned: isPinned,
        ))
    }

    // MARK: - Actions

    private func connectTo(_ cluster: ClusterConfig) {
        Task {
            await viewModel.selectCluster(cluster.id, appState: appState)
        }
    }

    private func editCluster(_ cluster: ClusterConfig) {
        viewModel.editingCluster = cluster
        viewModel.showingEditSheet = true
    }

    private func confirmDelete(_ cluster: ClusterConfig) {
        clusterToDelete = cluster
        showDeleteConfirmation = true
    }

    private func togglePin(_ cluster: ClusterConfig) {
        appState.configStore.togglePin(for: cluster.id)
    }

    private func cloneCluster(_ cluster: ClusterConfig) {
        viewModel.cloneCluster(cluster, in: appState)
    }

    private func testCluster(_ cluster: ClusterConfig) {
        testingClusterId = cluster.id
        let password = cluster.authType == .sasl
            ? KeychainManager.loadPassword(for: cluster.id)
            : nil
        Task {
            let start = DispatchTime.now()
            let result = await appState.testConnection(config: cluster, password: password)
            let elapsed = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
            let pingMs = Int(elapsed / 1_000_000)

            testingClusterId = nil

            switch result {
            case .success:
                withAnimation {
                    clusterPingResults[cluster.id] = pingMs
                    pingFailedIds.remove(cluster.id)
                }
                showBanner(.init(
                    success: true,
                    clusterName: cluster.name,
                    pingMs: pingMs,
                ))
            case let .failure(error):
                withAnimation {
                    clusterPingResults[cluster.id] = nil
                    pingFailedIds.insert(cluster.id)
                }
                showBanner(.init(
                    success: false,
                    clusterName: cluster.name,
                    message: error.localizedDescription,
                ))
            }
        }
    }

    private func showBanner(_ info: BannerInfo) {
        withAnimation { banner = info }
        Task {
            try? await Task.sleep(for: .seconds(3))
            withAnimation { banner = nil }
        }
    }

    // MARK: - Keyboard Navigation

    private enum Direction { case up, down }

    private func moveSelection(direction: Direction) {
        guard !sortedClusters.isEmpty else { return }

        if let currentId = keyboardSelectedClusterId,
           let currentIndex = sortedClusters.firstIndex(where: { $0.id == currentId })
        {
            let newIndex: Int = switch direction {
            case .up:
                max(0, currentIndex - 1)
            case .down:
                min(sortedClusters.count - 1, currentIndex + 1)
            }
            keyboardSelectedClusterId = sortedClusters[newIndex].id
        } else {
            // No selection, select first cluster
            keyboardSelectedClusterId = sortedClusters.first?.id
        }
    }

    private func connectToSelected() {
        guard let id = keyboardSelectedClusterId,
              let cluster = sortedClusters.first(where: { $0.id == id })
        else { return }
        connectTo(cluster)
    }

    private func testSelected() {
        guard let id = keyboardSelectedClusterId,
              let cluster = sortedClusters.first(where: { $0.id == id })
        else { return }
        testCluster(cluster)
    }

    private func editSelected() {
        guard let id = keyboardSelectedClusterId,
              let cluster = sortedClusters.first(where: { $0.id == id })
        else { return }
        editCluster(cluster)
    }

    private func deleteSelected() {
        guard let id = keyboardSelectedClusterId,
              let cluster = sortedClusters.first(where: { $0.id == id })
        else { return }
        confirmDelete(cluster)
    }

    private func cloneSelected() {
        guard let id = keyboardSelectedClusterId,
              let cluster = sortedClusters.first(where: { $0.id == id })
        else { return }
        cloneCluster(cluster)
    }

    // MARK: - Import/Export

    private enum ImportMode { case append, replace }

    private func handleImport(_ result: Result<URL, Error>) {
        guard case let .success(url) = result else { return }

        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let data = try Data(contentsOf: url)
            pendingImportData = data

            // Parse export data (supports both new wrapper and legacy formats)
            let export = try ConfigStore.parseExportData(data)
            importableClusters = export.clusters
            importableProtoFiles = export.protoFiles
            importableDeserializerConfigs = export.deserializerConfigs

            // Select all by default
            selectedClustersForImport = Set(importableClusters.map(\.id))

            // Show selection sheet
            showingImportSelectionSheet = true
        } catch {
            // Could add error banner here
        }
    }

    private func performImport(mode: ImportMode) {
        do {
            if mode == .replace {
                // Delete all existing clusters and their passwords + proto files
                for cluster in appState.configStore.clusters {
                    KeychainManager.deletePassword(for: cluster.id)
                    ProtobufConfigManager.shared.removeProtoFiles(for: cluster.id)
                }
                appState.configStore.clusters = []
            }

            // Import only selected clusters
            let selectedClusters = importableClusters.filter { selectedClustersForImport.contains($0.id) }
            let idMap = try appState.configStore.importSelectedClusters(selectedClusters)

            // Import proto files for selected clusters with remapped IDs
            let selectedClusterIDs = Set(selectedClusters.map(\.id))
            let relevantProtoFiles = importableProtoFiles.filter { selectedClusterIDs.contains($0.clusterID) }
            var protoPathMap: [String: String] = [:]
            if !relevantProtoFiles.isEmpty {
                protoPathMap = ProtobufConfigManager.shared.importProtoFiles(relevantProtoFiles, clusterIDMap: idMap)
            }

            // Import deserializer configs with remapped proto file paths
            if !importableDeserializerConfigs.isEmpty {
                DeserializerConfigStore.shared.importConfigs(importableDeserializerConfigs, protoPathMap: protoPathMap)
            }

            // Check for missing passwords
            missingPasswordClusters = selectedClusters.compactMap { cluster in
                if cluster.authType == .sasl,
                   KeychainManager.loadPassword(for: cluster.id) == nil
                {
                    return cluster.name
                }
                return nil
            }

            if !missingPasswordClusters.isEmpty {
                showMissingPasswordAlert = true
            }
        } catch {
            // Could add error banner here
        }
    }
}

// MARK: - Banner

struct BannerInfo: Equatable {
    let success: Bool
    let clusterName: String
    var pingMs: Int?
    var message: String?
}

private struct TestBanner: View {
    let info: BannerInfo

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: info.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(info.success ? .green : .red)
            Text(info.clusterName)
                .fontWeight(.medium)
            if info.success, let pingMs = info.pingMs {
                HStack(spacing: 3) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.caption)
                    Text("\(pingMs)ms")
                        .monospacedDigit()
                }
                .foregroundStyle(.secondary)
            } else if let message = info.message {
                Text(message)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
    }
}

// MARK: - Export Selection Sheet

private struct ExportSelectionSheet: View {
    let clusters: [ClusterConfig]
    @Binding var selectedClusterIds: Set<UUID>
    let l10n: L10n
    let onExport: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text(l10n["cluster.export"])
                .font(.headline)
                .padding()

            Divider()

            // Selection controls
            HStack {
                // Three-state checkbox for select all
                Toggle(isOn: Binding(
                    get: { selectedClusterIds.count == clusters.count },
                    set: { isOn in
                        if isOn {
                            selectedClusterIds = Set(clusters.map(\.id))
                        } else {
                            selectedClusterIds = []
                        }
                    },
                )) {
                    Text(l10n["cluster.select.all"])
                }
                .toggleStyle(.checkbox)

                Spacer()

                Text(l10n.t("cluster.selected.count", "\(selectedClusterIds.count)", "\(clusters.count)"))
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // Cluster list
            List(clusters) { cluster in
                HStack(alignment: .center) {
                    Toggle(isOn: Binding(
                        get: { selectedClusterIds.contains(cluster.id) },
                        set: { isSelected in
                            if isSelected {
                                selectedClusterIds.insert(cluster.id)
                            } else {
                                selectedClusterIds.remove(cluster.id)
                            }
                        },
                    )) {
                        HStack(spacing: 8) {
                            Text(cluster.name)
                                .fontWeight(.medium)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text("|")
                                .foregroundStyle(.tertiary)
                            Text(cluster.bootstrapServers)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }
            .frame(height: 300)

            Divider()

            // Actions
            HStack {
                Button(l10n["common.cancel"]) {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(l10n["cluster.export"]) {
                    onExport()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedClusterIds.isEmpty)
            }
            .padding()
        }
        .frame(width: 500)
    }
}

// MARK: - Import Selection Sheet

private struct ImportSelectionSheet: View {
    let clusters: [ClusterConfig]
    @Binding var selectedClusterIds: Set<UUID>
    let l10n: L10n
    let onImport: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text(l10n["cluster.import"])
                .font(.headline)
                .padding()

            Divider()

            // Selection controls
            HStack {
                // Three-state checkbox for select all
                Toggle(isOn: Binding(
                    get: { selectedClusterIds.count == clusters.count },
                    set: { isOn in
                        if isOn {
                            selectedClusterIds = Set(clusters.map(\.id))
                        } else {
                            selectedClusterIds = []
                        }
                    },
                )) {
                    Text(l10n["cluster.select.all"])
                }
                .toggleStyle(.checkbox)

                Spacer()

                Text(l10n.t("cluster.selected.count", "\(selectedClusterIds.count)", "\(clusters.count)"))
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // Cluster list
            List(clusters) { cluster in
                HStack(alignment: .center) {
                    Toggle(isOn: Binding(
                        get: { selectedClusterIds.contains(cluster.id) },
                        set: { isSelected in
                            if isSelected {
                                selectedClusterIds.insert(cluster.id)
                            } else {
                                selectedClusterIds.remove(cluster.id)
                            }
                        },
                    )) {
                        HStack(spacing: 8) {
                            Text(cluster.name)
                                .fontWeight(.medium)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text("|")
                                .foregroundStyle(.tertiary)
                            Text(cluster.bootstrapServers)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }
            .frame(height: 300)

            Divider()

            // Actions
            HStack {
                Button(l10n["common.cancel"]) {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(l10n["cluster.import"]) {
                    onImport()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedClusterIds.isEmpty)
            }
            .padding()
        }
        .frame(width: 500)
    }
}

// MARK: - Cluster Row

private struct ClusterRow: View {
    let cluster: ClusterConfig
    let isConnected: Bool
    let isTesting: Bool
    var pingMs: Int?
    var pingFailed: Bool = false
    var isKeyboardSelected: Bool = false
    let onConnect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onTest: () -> Void
    let onPin: () -> Void
    let onClone: () -> Void

    @Environment(AppState.self) private var appState
    @State private var isHovered = false

    private let iconFont: Font = .system(size: 13, weight: .medium)

    var body: some View {
        let l10n = appState.l10n

        HStack(spacing: 12) {
            // Left group — cluster info (with hover effect)
            HStack(spacing: 10) {
                // Pin indicator
                if cluster.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Circle()
                    .fill(dotColor)
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(cluster.name)
                        .fontWeight(isConnected ? .semibold : .regular)
                    HStack(spacing: 6) {
                        Image(systemName: authIcon)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .help(authLabel)
                        Text(cluster.bootstrapServers)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if let pingMs {
                            HStack(spacing: 2) {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                    .font(.system(size: 9, weight: .semibold))
                                Text("\(pingMs)ms")
                                    .contentTransition(.numericText())
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .animation(.default, value: pingMs)
                        }
                    }
                    // Timestamps
                    HStack(spacing: 6) {
                        // Always show last connected timestamp (even when currently connected)
                        if let lastConnected = cluster.lastConnectedAt {
                            Image(systemName: "clock.badge.checkmark")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.tertiary)
                            Text(l10n["cluster.last.connected.short"])
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Text(lastConnected, format: Date.FormatStyle(date: .abbreviated, time: .standard))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("•")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        } else {
                            Image(systemName: "clock.badge.xmark")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.tertiary)
                            Text(l10n["cluster.never.connected"])
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Text("•")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Image(systemName: "pencil.circle")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                        Text(l10n["cluster.last.modified.short"])
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(cluster.updatedAt, format: Date.FormatStyle(date: .abbreviated, time: .standard))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("•")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Image(systemName: "calendar.badge.plus")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                        Text(l10n["cluster.created.short"])
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(cluster.createdAt, format: Date.FormatStyle(date: .abbreviated, time: .standard))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            // Right group — actions (switch button moved to beginning)
            HStack(spacing: 10) {
                // Switch button / Connected indicator - at beginning of action group
                if isConnected {
                    // Show checkmark for connected cluster
                    Image(systemName: "checkmark.circle.fill")
                        .font(iconFont)
                        .foregroundStyle(.green)
                        .help(l10n["clusters.status.connected"])
                } else {
                    // Show switch button for disconnected clusters
                    Button {
                        onConnect()
                    } label: {
                        Image(systemName: "arrow.right.arrow.left")
                            .font(iconFont)
                    }
                    .buttonStyle(.borderless)
                    .help(l10n["clusters.switch"])
                }

                Button {
                    onTest()
                } label: {
                    if isTesting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "network")
                            .font(iconFont)
                    }
                }
                .buttonStyle(.borderless)
                .disabled(isTesting)
                .help(l10n["connection.test"])

                Button {
                    onPin()
                } label: {
                    Image(systemName: cluster.isPinned ? "pin.slash" : "pin")
                        .font(iconFont)
                }
                .buttonStyle(.borderless)
                .help(l10n[cluster.isPinned ? "cluster.unpin" : "cluster.pin"])

                Button {
                    onClone()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(iconFont)
                }
                .buttonStyle(.borderless)
                .help(l10n["cluster.clone"])

                Button {
                    onEdit()
                } label: {
                    Image(systemName: "pencil")
                        .font(iconFont)
                }
                .buttonStyle(.borderless)
                .help(l10n["cluster.edit"])

                Button {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .font(iconFont)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                .help(l10n["cluster.delete"])
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            (isKeyboardSelected || isHovered)
                ? Color.accentColor.opacity(0.1)
                : Color.clear,
            in: RoundedRectangle(cornerRadius: 6),
        )
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.2), value: isHovered)
        .animation(.snappy(duration: 0.08), value: isKeyboardSelected)
        .onTapGesture(count: 2) { onEdit() }
    }

    private var dotColor: Color {
        if isConnected { return .green }
        if pingFailed { return .red }
        return .gray.opacity(0.3)
    }

    private var authLabel: String {
        switch cluster.authType {
        case .none: "No Auth"
        case .sasl: cluster.saslMechanism?.rawValue ?? "SASL"
        }
    }

    private var authIcon: String {
        switch cluster.authType {
        case .none: "lock.open"
        case .sasl: "lock.fill"
        }
    }
}

// MARK: - Pin Drop Delegate

private struct PinDropDelegate: DropDelegate {
    @Binding var draggedCluster: ClusterConfig?
    let configStore: ConfigStore

    func validateDrop(info _: DropInfo) -> Bool {
        // Accept drops if we have a dragged cluster
        draggedCluster != nil
    }

    func performDrop(info _: DropInfo) -> Bool {
        guard let draggedCluster else { return false }

        // Pin if currently unpinned
        if !draggedCluster.isPinned {
            configStore.togglePin(for: draggedCluster.id)
        }

        self.draggedCluster = nil
        return true
    }

    func dropEntered(info _: DropInfo) {
        // Visual feedback could be added here
    }
}

// MARK: - Unpin Drop Delegate

private struct UnpinDropDelegate: DropDelegate {
    @Binding var draggedCluster: ClusterConfig?
    let configStore: ConfigStore

    func validateDrop(info _: DropInfo) -> Bool {
        // Accept drops if we have a dragged cluster
        draggedCluster != nil
    }

    func performDrop(info _: DropInfo) -> Bool {
        guard let draggedCluster else { return false }

        // Unpin if currently pinned
        if draggedCluster.isPinned {
            configStore.togglePin(for: draggedCluster.id)
        }

        self.draggedCluster = nil
        return true
    }

    func dropEntered(info _: DropInfo) {
        // Visual feedback could be added here
    }
}

// MARK: - Cluster Drop Delegate

private struct ClusterDropDelegate: DropDelegate {
    let cluster: ClusterConfig
    let clusters: [ClusterConfig]
    @Binding var draggedCluster: ClusterConfig?
    let configStore: ConfigStore
    let targetIsPinned: Bool

    func performDrop(info _: DropInfo) -> Bool {
        guard let draggedCluster else { return false }

        // Handle pin/unpin when dragging between sections
        if draggedCluster.isPinned != targetIsPinned {
            configStore.togglePin(for: draggedCluster.id)
        }

        self.draggedCluster = nil
        return true
    }

    func dropEntered(info _: DropInfo) {
        guard let draggedCluster else { return }
        guard draggedCluster.id != cluster.id else { return }

        // Only reorder if in the same section (same pin status)
        guard draggedCluster.isPinned == targetIsPinned else { return }

        let from = clusters.firstIndex { $0.id == draggedCluster.id }
        let to = clusters.firstIndex { $0.id == cluster.id }

        guard let from, let to else { return }

        // Reorder clusters by updating sortOrder
        var updatedClusters = clusters
        let movedCluster = updatedClusters.remove(at: from)
        updatedClusters.insert(movedCluster, at: to)

        // Update sortOrder for all clusters
        for (index, cluster) in updatedClusters.enumerated() {
            if let idx = configStore.clusters.firstIndex(where: { $0.id == cluster.id }) {
                configStore.clusters[idx].sortOrder = index
            }
        }
        configStore.save()
    }
}
