import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var showClearDataConfirm = false
    @State private var dataCleared = false

    // Backup
    @State private var showingBackupExport = false
    @State private var showingBackupImport = false
    @State private var backupData: Data?
    @State private var showRestartAlert = false
    @State private var isExporting = false
    @State private var importError: String?
    @State private var showImportError = false

    private var backupFilename: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = formatter.string(from: Date())
        return "swifka-backup-\(timestamp).zip"
    }

    private var dataDirectoryPath: String {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent(Constants.configDirectory)
            .path
    }

    var body: some View {
        @Bindable var state = appState
        let l10n = appState.l10n

        Form {
            // Appearance
            Section(l10n["settings.appearance"]) {
                Picker(l10n["settings.appearance"], selection: $state.appearanceMode) {
                    Text(l10n["settings.appearance.system"]).tag(AppearanceMode.system)
                    Text(l10n["settings.appearance.light"]).tag(AppearanceMode.light)
                    Text(l10n["settings.appearance.dark"]).tag(AppearanceMode.dark)
                }

                Picker(l10n["settings.display.density"], selection: $state.rowDensity) {
                    Text(l10n["settings.density.compact"]).tag(RowDensity.compact)
                    Text(l10n["settings.density.regular"]).tag(RowDensity.regular)
                    Text(l10n["settings.density.large"]).tag(RowDensity.large)
                }
            }

            // Refresh
            Section(l10n["settings.refresh"]) {
                Picker(l10n["settings.refresh.mode"], selection: Binding(
                    get: { appState.defaultRefreshMode },
                    set: { newMode in
                        appState.defaultRefreshMode = newMode
                        appState.refreshManager.updateMode(newMode)
                    },
                )) {
                    ForEach(RefreshMode.presets) { mode in
                        Text(refreshModeLabel(mode, l10n: l10n)).tag(mode)
                    }
                }
            }

            // Charts
            Section(l10n["settings.charts"]) {
                Picker(l10n["settings.charts.time.window"], selection: $state.chartTimeWindow) {
                    ForEach(ChartTimeWindow.allCases) { window in
                        Text(window.rawValue).tag(window)
                    }
                }
            }

            // Alerts
            Section(l10n["settings.alerts"]) {
                Toggle(l10n["settings.alerts.isr.enabled"], isOn: $state.isrAlertsEnabled)

                if appState.isrAlertsEnabled {
                    Stepper(
                        value: $state.minInsyncReplicas,
                        in: 1 ... 10,
                    ) {
                        HStack {
                            Text(l10n["settings.alerts.min.isr"])
                            Spacer()
                            Text("\(appState.minInsyncReplicas)")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(l10n["settings.alerts.min.isr.description"])
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                Toggle(l10n["settings.alerts.desktop"], isOn: $state.desktopNotificationsEnabled)

                if appState.desktopNotificationsEnabled, !appState.notificationPermissionGranted {
                    Text(l10n["settings.alerts.desktop.denied"])
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            // Data
            Section(l10n["settings.data"]) {
                // Backup export
                HStack {
                    VStack(alignment: .leading) {
                        Text(l10n["settings.data.export"])
                        Text(l10n["settings.data.export.description"])
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if isExporting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button(l10n["settings.data.export"]) {
                            Task {
                                isExporting = true
                                do {
                                    backupData = try await BackupManager.exportBackup(
                                        metricDatabase: appState.metricDatabase,
                                    )
                                    showingBackupExport = true
                                } catch {
                                    importError = error.localizedDescription
                                    showImportError = true
                                }
                                isExporting = false
                            }
                        }
                    }
                }

                // Backup import
                HStack {
                    VStack(alignment: .leading) {
                        Text(l10n["settings.data.import"])
                        Text(l10n["settings.data.import.description"])
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(l10n["settings.data.import"]) {
                        showingBackupImport = true
                    }
                }

                // Reveal data folder
                HStack {
                    VStack(alignment: .leading) {
                        Text(l10n["settings.data.reveal"])
                        Text(l10n["settings.data.reveal.description"])
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(dataDirectoryPath)
                            .font(.caption2)
                            .monospaced()
                            .foregroundStyle(.tertiary)
                            .textSelection(.enabled)
                    }
                    Spacer()
                    Button(l10n["settings.data.reveal"]) {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: dataDirectoryPath)
                    }
                }

                // Retention policy
                Picker(l10n["settings.retention.policy"], selection: $state.retentionPolicy) {
                    Text(l10n["settings.retention.1d"]).tag(DataRetentionPolicy.oneDay)
                    Text(l10n["settings.retention.7d"]).tag(DataRetentionPolicy.sevenDays)
                    Text(l10n["settings.retention.30d"]).tag(DataRetentionPolicy.thirtyDays)
                    Text(l10n["settings.retention.90d"]).tag(DataRetentionPolicy.ninetyDays)
                    Text(l10n["settings.retention.unlimited"]).tag(DataRetentionPolicy.unlimited)
                }

                Button(role: .destructive) {
                    showClearDataConfirm = true
                } label: {
                    Text(l10n["settings.retention.clear"])
                }
                .disabled(dataCleared)
                .confirmationDialog(
                    l10n["settings.retention.clear.confirm"],
                    isPresented: $showClearDataConfirm,
                    titleVisibility: .visible,
                ) {
                    Button(l10n["common.delete"], role: .destructive) {
                        Task {
                            await appState.clearAllMetricData()
                            dataCleared = true
                        }
                    }
                }
            }

            // Language
            Section(l10n["settings.language"]) {
                Picker(l10n["settings.language"], selection: Binding(
                    get: { appState.l10n.locale },
                    set: { appState.l10n.locale = $0 },
                )) {
                    Text(l10n["settings.language.system"]).tag("system")
                    Text(l10n["settings.language.en"]).tag("en")
                    Text(l10n["settings.language.zh"]).tag("zh-Hans")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(l10n["settings.title"])
        .task(id: appState.selectedSidebarItem) {
            dataCleared = false
        }
        .fileExporter(
            isPresented: $showingBackupExport,
            document: BackupDocument(data: backupData ?? Data()),
            contentType: .zip,
            defaultFilename: backupFilename,
        ) { _ in }
        .fileImporter(
            isPresented: $showingBackupImport,
            allowedContentTypes: [.zip],
        ) { result in
            handleBackupImport(result)
        }
        .alert(
            l10n["settings.data.import.restart.title"],
            isPresented: $showRestartAlert,
        ) {
            Button(l10n["settings.data.import.restart.button"]) {
                // Spawn a shell that polls until the current process exits, then relaunches
                let appPath = Bundle.main.bundleURL.path
                let pid = ProcessInfo.processInfo.processIdentifier
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/bin/sh")
                task.arguments = [
                    "-c",
                    "while kill -0 \(pid) 2>/dev/null; do sleep 0.1; done; open \"\(appPath)\"",
                ]
                try? task.run()
                NSApplication.shared.terminate(nil)
            }
            Button(l10n["common.cancel"], role: .cancel) {}
        } message: {
            Text(l10n["settings.data.import.restart.message"])
        }
        .alert(
            l10n["common.error"],
            isPresented: $showImportError,
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
    }

    // MARK: - Backup Import

    private func handleBackupImport(_ result: Result<URL, Error>) {
        guard case let .success(url) = result else { return }

        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let data = try Data(contentsOf: url)
            let backup = try BackupManager.importBackup(from: data)

            // Smart cluster import: skip duplicates, only add new clusters
            let existingIDs = Set(appState.configStore.clusters.map(\.id))
            let newClusters = backup.clusters.filter { !existingIDs.contains($0.id) }

            if !newClusters.isEmpty {
                let idMap = try appState.configStore.importSelectedClusters(newClusters)

                // Import proto files for new clusters with ID remapping
                let newClusterIDs = Set(newClusters.map(\.id))
                let relevantProtoFiles = backup.protoFiles.filter { newClusterIDs.contains($0.clusterID) }
                var protoPathMap: [String: String] = [:]
                if !relevantProtoFiles.isEmpty {
                    protoPathMap = ProtobufConfigManager.shared.importProtoFiles(
                        relevantProtoFiles, clusterIDMap: idMap,
                    )
                }

                // Import deserializer configs with proto path remapping
                if !backup.deserializerConfigs.isEmpty {
                    DeserializerConfigStore.shared.importConfigs(
                        backup.deserializerConfigs, protoPathMap: protoPathMap,
                    )
                }

                // Persist newly imported cluster IDs for "New" badge after restart
                let importedIDs = Set(idMap.values)
                let idStrings = importedIDs.map(\.uuidString)
                UserDefaults.standard.set(idStrings, forKey: "backup.recentlyImportedClusterIDs")
            }

            // Show restart alert only if metrics DB was replaced
            if backup.hasMetricsDB {
                showRestartAlert = true
            }
        } catch {
            importError = error.localizedDescription
            showImportError = true
        }
    }

    // MARK: - Helpers

    private func refreshModeLabel(_ mode: RefreshMode, l10n: L10n) -> String {
        switch mode {
        case .manual: l10n["settings.refresh.manual"]
        case let .interval(seconds): l10n.t("settings.refresh.interval.seconds", "\(seconds)")
        }
    }
}
