import SwiftUI

struct ClusterPickerView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = ConnectionViewModel()
    @State private var showingDropdown = false

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
                Button {
                    showingDropdown.toggle()
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
                .popover(isPresented: $showingDropdown, arrowEdge: .bottom) {
                    ClusterDropdownContent(viewModel: $viewModel, showingDropdown: $showingDropdown)
                        .environment(appState)
                }
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

// MARK: - Custom Dropdown

private struct ClusterDropdownContent: View {
    @Environment(AppState.self) private var appState
    @Binding var viewModel: ConnectionViewModel
    @Binding var showingDropdown: Bool

    var body: some View {
        let l10n = appState.l10n

        VStack(alignment: .leading, spacing: 0) {
            ForEach(appState.configStore.clusters) { cluster in
                let isSelected = appState.configStore.selectedClusterId == cluster.id
                DropdownItem(
                    icon: isSelected ? "checkmark.circle.fill" : "circle",
                    label: cluster.name,
                    iconColor: isSelected ? .green : .secondary,
                ) {
                    showingDropdown = false
                    Task {
                        await viewModel.selectCluster(cluster.id, appState: appState)
                    }
                }
            }

            Divider()
                .padding(.horizontal, 10)
                .padding(.vertical, 4)

            DropdownItem(icon: "plus.circle", label: l10n["cluster.add"]) {
                showingDropdown = false
                viewModel.showingAddSheet = true
            }

            if let cluster = appState.configStore.selectedCluster {
                DropdownItem(icon: "pencil.circle", label: l10n["cluster.edit"]) {
                    showingDropdown = false
                    viewModel.editingCluster = cluster
                    viewModel.showingEditSheet = true
                }

                DropdownItem(icon: "trash.circle", label: l10n["cluster.delete"], iconColor: .red) {
                    showingDropdown = false
                    Task {
                        await viewModel.deleteCluster(cluster.id, from: appState)
                    }
                }
            }
        }
        .padding(.vertical, 5)
        .frame(width: 220)
    }
}

private struct DropdownItem: View {
    let icon: String
    let label: String
    var iconColor: Color = .secondary
    var action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(isHovered ? .white : iconColor)
                    .frame(width: 18, alignment: .center)
                Text(label)
                    .lineLimit(1)
                Spacer()
            }
            .font(.system(size: 13))
            .padding(.horizontal, 10)
            .frame(height: 24)
            .contentShape(Rectangle())
            .background(isHovered ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 5))
            .foregroundStyle(isHovered ? .white : .primary)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .padding(.horizontal, 5)
    }
}
