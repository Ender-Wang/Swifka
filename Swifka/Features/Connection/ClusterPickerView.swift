import SwiftUI

struct ClusterPickerView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = ConnectionViewModel()

    var body: some View {
        let l10n = appState.l10n

        VStack(alignment: .leading, spacing: 8) {
            if appState.configStore.clusters.isEmpty {
                Button {
                    viewModel.showingAddSheet = true
                } label: {
                    Label(l10n["cluster.add"], systemImage: "plus.circle")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            } else {
                Menu {
                    ForEach(appState.configStore.clusters) { cluster in
                        Button {
                            Task {
                                await viewModel.selectCluster(cluster.id, appState: appState)
                            }
                        } label: {
                            HStack {
                                Text(cluster.name)
                                if appState.configStore.selectedClusterId == cluster.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }

                    Divider()

                    Button {
                        viewModel.showingAddSheet = true
                    } label: {
                        Label(l10n["cluster.add"], systemImage: "plus")
                    }

                    if let cluster = appState.configStore.selectedCluster {
                        Button {
                            viewModel.editingCluster = cluster
                            viewModel.showingEditSheet = true
                        } label: {
                            Label(l10n["cluster.edit"], systemImage: "pencil")
                        }

                        Button(role: .destructive) {
                            Task {
                                await viewModel.deleteCluster(cluster.id, from: appState)
                            }
                        } label: {
                            Label(l10n["cluster.delete"], systemImage: "trash")
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        ConnectionStatusBadge(status: appState.connectionStatus)
                        Text(appState.configStore.selectedCluster?.name ?? l10n["cluster.none"])
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $viewModel.showingAddSheet) {
            ClusterFormView(mode: .add) { cluster, password in
                viewModel.addCluster(cluster, password: password, to: appState)
                Task {
                    await viewModel.selectCluster(cluster.id, appState: appState)
                }
            }
            .environment(appState)
        }
        .sheet(isPresented: $viewModel.showingEditSheet) {
            if let cluster = viewModel.editingCluster {
                ClusterFormView(mode: .edit(cluster)) { updated, password in
                    viewModel.updateCluster(updated, password: password, in: appState)
                }
                .environment(appState)
            }
        }
    }
}
