import SwiftUI

struct ConsumerGroupsView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedGroup: ConsumerGroupInfo?

    var body: some View {
        let l10n = appState.l10n

        HSplitView {
            // Group list
            Table(appState.consumerGroups, selection: Binding(
                get: { selectedGroup?.id },
                set: { id in selectedGroup = appState.consumerGroups.first { $0.id == id } },
            )) {
                TableColumn(l10n["groups.name"]) { group in
                    Text(group.name)
                        .fontWeight(.medium)
                        .padding(.vertical, appState.rowDensity.tablePadding)
                }

                TableColumn(l10n["groups.state"]) { group in
                    Text(group.state)
                        .foregroundStyle(stateColor(group.state))
                        .padding(.vertical, appState.rowDensity.tablePadding)
                }
                .width(min: 60, ideal: 100)

                TableColumn(l10n["groups.members"]) { group in
                    Text("\(group.members.count)")
                        .padding(.vertical, appState.rowDensity.tablePadding)
                }
                .width(min: 50, ideal: 80)

                TableColumn(l10n["groups.protocol.type"]) { group in
                    Text(group.protocolType)
                        .padding(.vertical, appState.rowDensity.tablePadding)
                }
                .width(min: 60, ideal: 100)
            }
            .font(.system(size: appState.rowDensity.fontSize))
            .frame(minWidth: 350)
            .overlay {
                if appState.consumerGroups.isEmpty {
                    ContentUnavailableView(
                        l10n["groups.empty"],
                        systemImage: "person.3",
                        description: Text(l10n["groups.empty.description"]),
                    )
                }
            }

            // Group detail
            if let group = selectedGroup {
                GroupDetailView(group: group)
                    .frame(minWidth: 300)
            }
        }
        .navigationTitle(l10n["groups.title"])
    }

    private func stateColor(_ state: String) -> Color {
        switch state.lowercased() {
        case "stable": .green
        case "empty": .orange
        case "dead": .red
        case "preparingrebalance", "completingrebalance": .yellow
        default: .secondary
        }
    }
}

struct GroupDetailView: View {
    @Environment(AppState.self) private var appState
    let group: ConsumerGroupInfo

    var body: some View {
        let l10n = appState.l10n

        VStack(alignment: .leading, spacing: 12) {
            Text(group.name)
                .font(.title2.bold())
                .padding(.horizontal)
                .padding(.top, 8)

            HStack(spacing: 16) {
                DetailRow(label: l10n["groups.state"], value: group.state)
                DetailRow(label: l10n["groups.protocol"], value: group.protocol)
                DetailRow(label: l10n["groups.protocol.type"], value: group.protocolType)
            }
            .padding(.horizontal)

            if group.members.isEmpty {
                ContentUnavailableView(
                    "No Members",
                    systemImage: "person.slash",
                    description: Text("This consumer group has no active members."),
                )
            } else {
                Table(group.members) {
                    TableColumn(l10n["groups.member.id"]) { member in
                        Text(member.memberId)
                            .lineLimit(1)
                            .padding(.vertical, appState.rowDensity.tablePadding)
                    }

                    TableColumn(l10n["groups.member.client.id"]) { member in
                        Text(member.clientId)
                            .padding(.vertical, appState.rowDensity.tablePadding)
                    }
                    .width(min: 80, ideal: 120)

                    TableColumn(l10n["groups.member.host"]) { member in
                        Text(member.clientHost)
                            .padding(.vertical, appState.rowDensity.tablePadding)
                    }
                    .width(min: 80, ideal: 120)
                }
                .font(.system(size: appState.rowDensity.fontSize))
            }
        }
    }
}
