import SwiftUI

struct ConsumerGroupsView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedGroup: ConsumerGroupInfo?

    var body: some View {
        let l10n = appState.l10n

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
        .overlay {
            if appState.consumerGroups.isEmpty {
                ContentUnavailableView(
                    l10n["groups.empty"],
                    systemImage: "person.3",
                    description: Text(l10n["groups.empty.description"]),
                )
            }
        }
        .overlay(alignment: .trailing) {
            if let group = selectedGroup {
                GroupDetailView(group: group) {
                    selectedGroup = nil
                }
                .frame(width: 320)
                .compositingGroup()
                .background(Color(nsColor: .windowBackgroundColor))
                .clipShape(.rect(topLeadingRadius: 10, bottomLeadingRadius: 10))
                .overlay {
                    UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 10)
                        .strokeBorder(.separator, lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.15), radius: 8, x: -2)
                .transition(.move(edge: .trailing))
            }
        }
        .animation(.smooth(duration: 0.25), value: selectedGroup?.id)
        .onKeyPress(.escape) {
            if selectedGroup != nil {
                selectedGroup = nil
                return .handled
            }
            return .ignored
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
    var onDismiss: () -> Void = {}
    @State private var nameCopied = false

    var body: some View {
        let l10n = appState.l10n

        VStack(alignment: .leading, spacing: 0) {
            HStack {
                PanelCloseButton(action: onDismiss)
                Text(nameCopied ? "Copied" : group.name)
                    .font(.title2.bold())
                    .foregroundStyle(nameCopied ? .green : .primary)
                    .contentTransition(.opacity)
                    .onTapGesture {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(group.name, forType: .string)
                        withAnimation(.easeIn(duration: 0.1)) { nameCopied = true }
                        withAnimation(.easeOut(duration: 0.3).delay(0.8)) { nameCopied = false }
                    }
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 12)

            VStack(alignment: .leading, spacing: 8) {
                DetailRow(label: l10n["groups.state"], value: group.state)
                DetailRow(label: l10n["groups.protocol"], value: group.protocol)
                DetailRow(label: l10n["groups.protocol.type"], value: group.protocolType)
            }
            .padding(.horizontal)
            .padding(.bottom, 12)

            Divider()

            if group.members.isEmpty {
                ContentUnavailableView(
                    "No Members",
                    systemImage: "person.slash",
                    description: Text("This consumer group has no active members."),
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                Text("\(group.members.count) " + l10n["groups.members"])
                    .font(.headline)
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                List(group.members) { member in
                    VStack(alignment: .leading, spacing: 6) {
                        DetailRow(label: l10n["groups.member.client.id"], value: member.clientId)
                        DetailRow(label: l10n["groups.member.id"], value: member.memberId)
                        DetailRow(label: l10n["groups.member.host"], value: member.clientHost)
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.plain)
            }
        }
    }
}
