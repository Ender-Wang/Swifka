import SwiftUI

struct ConsumerGroupsView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedGroup: ConsumerGroupInfo?

    var body: some View {
        @Bindable var appState = appState
        let l10n = appState.l10n

        Table(sortedGroups, selection: Binding(
            get: { selectedGroup?.id },
            set: { id in selectedGroup = sortedGroups.first { $0.id == id } },
        ), sortOrder: $appState.consumerGroupsSortOrder) {
            TableColumn(l10n["groups.name"], value: \.name) { group in
                Text(group.name)
                    .fontWeight(.medium)
                    .padding(.vertical, appState.rowDensity.tablePadding)
            }

            TableColumn(l10n["groups.state"], value: \.state) { group in
                Text(group.state)
                    .foregroundStyle(stateColor(group.state))
                    .padding(.vertical, appState.rowDensity.tablePadding)
            }
            .width(min: 60, ideal: 100)

            TableColumn(l10n["groups.members"], value: \.members.count) { group in
                Text("\(group.members.count)")
                    .padding(.vertical, appState.rowDensity.tablePadding)
            }
            .width(min: 50, ideal: 80)

            TableColumn(l10n["groups.lag"]) { group in
                let lag = appState.consumerGroupLags[group.name] ?? 0
                Text(formatLag(lag))
                    .foregroundStyle(lagColor(lag))
                    .padding(.vertical, appState.rowDensity.tablePadding)
            }
            .width(min: 60, ideal: 100)

            TableColumn(l10n["groups.protocol.type"], value: \.protocolType) { group in
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
                    systemImage: "person.2",
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

    private var sortedGroups: [ConsumerGroupInfo] {
        appState.consumerGroups.sorted(using: appState.consumerGroupsSortOrder)
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

    private func formatLag(_ lag: Int64) -> String {
        if lag >= 1_000_000 { return String(format: "%.1fM", Double(lag) / 1_000_000) }
        if lag >= 1000 { return String(format: "%.1fK", Double(lag) / 1000) }
        return "\(lag)"
    }

    private func lagColor(_ lag: Int64) -> Color {
        if lag == 0 { return .secondary }
        if lag > 10000 { return .red }
        return .orange
    }
}

struct GroupDetailView: View {
    @Environment(AppState.self) private var appState
    let group: ConsumerGroupInfo
    var onDismiss: () -> Void = {}
    @State private var nameCopied = false
    @State private var selectedTab: GroupDetailTab = .members

    private enum GroupDetailTab: String, CaseIterable {
        case members
        case partitionLag
    }

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

            Picker("", selection: $selectedTab) {
                Text(l10n["groups.tab.members"]).tag(GroupDetailTab.members)
                Text(l10n["groups.tab.partition.lag"]).tag(GroupDetailTab.partitionLag)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            switch selectedTab {
            case .members:
                membersTab(l10n: l10n)
            case .partitionLag:
                partitionLagTab(l10n: l10n)
            }
        }
    }

    @ViewBuilder
    private func membersTab(l10n: L10n) -> some View {
        if group.members.isEmpty {
            ContentUnavailableView(
                l10n["groups.no.members"],
                systemImage: "person.slash",
                description: Text(l10n["groups.no.members.description"]),
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else {
            Text("\(group.members.count) " + l10n["groups.members"])
                .font(.headline)
                .padding(.horizontal)
                .padding(.bottom, 4)

            List(group.members) { member in
                VStack(alignment: .leading, spacing: 6) {
                    DetailRow(label: l10n["groups.member.client.id"], value: member.clientId)
                    DetailRow(label: l10n["groups.member.id"], value: member.memberId)
                    DetailRow(label: l10n["groups.member.host"], value: member.clientHost)
                    if !member.assignments.isEmpty {
                        let partitionText = member.assignments
                            .map { "\($0.topic) [\($0.partitions.map(String.init).joined(separator: ","))]" }
                            .joined(separator: ", ")
                        DetailRow(label: l10n["groups.member.assignments"], value: partitionText)
                    }
                }
                .padding(.vertical, 4)
            }
            .listStyle(.plain)
        }
    }

    /// Build a reverse lookup: "topic:partition" → clientId from member assignments.
    private var partitionOwnerMap: [String: String] {
        var map: [String: String] = [:]
        for member in group.members {
            for assignment in member.assignments {
                for partition in assignment.partitions {
                    map["\(assignment.topic):\(partition)"] = member.clientId
                }
            }
        }
        return map
    }

    @ViewBuilder
    private func partitionLagTab(l10n: L10n) -> some View {
        let partitions = appState.partitionLags[group.name] ?? []
        if partitions.isEmpty {
            ContentUnavailableView(
                l10n["groups.no.partition.lag"],
                systemImage: "chart.bar",
                description: Text(l10n["groups.no.partition.lag.description"]),
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else {
            let byTopic = Dictionary(grouping: partitions, by: \.topic)
                .sorted { $0.key < $1.key }
            let owners = partitionOwnerMap

            List {
                ForEach(byTopic, id: \.key) { topic, topicPartitions in
                    let topicLag = topicPartitions.reduce(0) { $0 + $1.lag }
                    DisclosureGroup {
                        ForEach(topicPartitions.sorted(by: { $0.partition < $1.partition })) { p in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text("P\(p.partition)")
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                        .frame(width: 30, alignment: .leading)
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 4) {
                                            Text(l10n["groups.partition.committed"])
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                            Text("\(p.committedOffset)")
                                                .font(.caption.monospaced())
                                        }
                                        HStack(spacing: 4) {
                                            Text(l10n["groups.partition.watermark"])
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                            Text("\(p.highWatermark)")
                                                .font(.caption.monospaced())
                                        }
                                    }
                                    Spacer()
                                    Text(formatLag(p.lag))
                                        .font(.caption.monospaced().bold())
                                        .foregroundStyle(lagColor(p.lag))
                                }
                                if let owner = owners["\(p.topic):\(p.partition)"] {
                                    HStack(spacing: 4) {
                                        Image(systemName: "person.fill")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                        Text(owner)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.leading, 34)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    } label: {
                        HStack {
                            Text(topic)
                                .fontWeight(.medium)
                            Spacer()
                            Text(formatLag(topicLag))
                                .font(.caption.monospaced())
                                .foregroundStyle(lagColor(topicLag))
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    private func formatLag(_ lag: Int64) -> String {
        if lag >= 1_000_000 { return String(format: "%.1fM", Double(lag) / 1_000_000) }
        if lag >= 1000 { return String(format: "%.1fK", Double(lag) / 1000) }
        return "\(lag)"
    }

    private func lagColor(_ lag: Int64) -> Color {
        if lag == 0 { return .secondary }
        if lag > 10000 { return .red }
        return .orange
    }
}
