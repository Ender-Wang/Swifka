import SwiftUI

struct ClustersView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = ConnectionViewModel()
    @State private var clusterToDelete: ClusterConfig?
    @State private var showDeleteConfirmation = false
    @State private var testingClusterId: UUID?
    @State private var connectedPingMs: Int?
    @State private var clusterPingResults: [UUID: Int] = [:]
    @State private var pingFailedIds: Set<UUID> = []
    @State private var banner: BannerInfo?

    var body: some View {
        let l10n = appState.l10n

        List {
            ForEach(appState.configStore.clusters) { cluster in
                let isConnected = appState.configStore.selectedClusterId == cluster.id
                    && appState.connectionStatus.isConnected
                ClusterRow(
                    cluster: cluster,
                    isConnected: isConnected,
                    isTesting: testingClusterId == cluster.id,
                    pingMs: isConnected ? connectedPingMs : clusterPingResults[cluster.id],
                    pingFailed: pingFailedIds.contains(cluster.id),
                    onConnect: { connectTo(cluster) },
                    onEdit: { editCluster(cluster) },
                    onDelete: { confirmDelete(cluster) },
                    onTest: { testCluster(cluster) },
                )
            }
        }
        .listStyle(.inset)
        .navigationTitle(l10n["sidebar.clusters"])
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
            // Ping loop for connected cluster
            while !Task.isCancelled {
                let ms = await appState.ping()
                withAnimation { connectedPingMs = ms }
                try? await Task.sleep(for: .seconds(1))
            }
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

// MARK: - Cluster Row

private struct ClusterRow: View {
    let cluster: ClusterConfig
    let isConnected: Bool
    let isTesting: Bool
    var pingMs: Int?
    var pingFailed: Bool = false
    let onConnect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onTest: () -> Void

    @Environment(AppState.self) private var appState

    private let iconFont: Font = .system(size: 13, weight: .medium)

    var body: some View {
        let l10n = appState.l10n

        HStack(spacing: 12) {
            // Left group — cluster info
            HStack(spacing: 10) {
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
                }
            }

            Spacer()

            // Middle — switch button
            Button {
                onConnect()
            } label: {
                Image(systemName: "arrow.right.arrow.left")
                    .font(iconFont)
            }
            .buttonStyle(.borderless)
            .disabled(isConnected)
            .opacity(isConnected ? 0 : 1)
            .help(l10n["clusters.switch"])

            Spacer()

            // Right group — actions
            HStack(spacing: 10) {
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
        .padding(.vertical, 4)
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
