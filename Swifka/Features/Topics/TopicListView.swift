import SwiftUI

struct TopicListView: View {
    @Environment(AppState.self) private var appState
    @State private var searchText = ""
    @AppStorage("topics.hideInternal") private var hideInternal = true

    var body: some View {
        let l10n = appState.l10n

        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(l10n["topics.search"], text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)

                Spacer()

                Toggle(isOn: $hideInternal) {
                    Text(l10n["topics.hide.internal"])
                }
                .toggleStyle(.checkbox)
            }
            .padding(12)

            List {
                ForEach(filteredTopics) { topic in
                    DisclosureGroup(isExpanded: Binding(
                        get: { appState.expandedTopics.contains(topic.name) },
                        set: { isExpanded in
                            if isExpanded {
                                appState.expandedTopics.insert(topic.name)
                            } else {
                                appState.expandedTopics.remove(topic.name)
                            }
                        },
                    )) {
                        TopicPartitionsView(topic: topic)
                    } label: {
                        HStack {
                            Text(topic.name)
                                .fontWeight(topic.isInternal ? .regular : .medium)
                                .foregroundStyle(topic.isInternal ? .secondary : .primary)
                            Spacer()
                            Text("\(topic.partitionCount) \(l10n["topics.partitions"])")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                            Text("·")
                                .foregroundStyle(.quaternary)
                            Text("\(topic.replicaCount) \(l10n["topics.replicas"])")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            withAnimation(.smooth(duration: 0.25)) {
                                if appState.expandedTopics.contains(topic.name) {
                                    appState.expandedTopics.remove(topic.name)
                                } else {
                                    appState.expandedTopics.insert(topic.name)
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
        .navigationTitle(l10n["topics.title"])
    }

    private var filteredTopics: [TopicInfo] {
        appState.topics.filter { topic in
            if hideInternal, topic.isInternal { return false }
            if searchText.isEmpty { return true }
            return topic.name.localizedCaseInsensitiveContains(searchText)
        }
    }
}

private struct TopicPartitionsView: View {
    @Environment(AppState.self) private var appState
    let topic: TopicInfo

    var body: some View {
        let l10n = appState.l10n

        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
            GridRow {
                Text(l10n["topic.detail.partition.id"]).foregroundStyle(.secondary)
                Text(l10n["topic.detail.leader"]).foregroundStyle(.secondary)
                Text(l10n["topic.detail.replicas"]).foregroundStyle(.secondary)
                Text(l10n["topic.detail.isr"]).foregroundStyle(.secondary)
                Text(l10n["topic.detail.low.watermark"]).foregroundStyle(.secondary)
                Text(l10n["topic.detail.high.watermark"]).foregroundStyle(.secondary)
                Text(l10n["topic.detail.messages"]).foregroundStyle(.secondary)
            }
            .font(.caption)

            Divider()

            ForEach(topic.partitions) { partition in
                GridRow {
                    Text("\(partition.partitionId)")
                    Text("\(partition.leader)")
                    Text(partition.replicas.map(String.init).joined(separator: ", "))
                    Text(partition.isr.map(String.init).joined(separator: ", "))
                    Text(partition.lowWatermark.map(String.init) ?? "-").monospacedDigit()
                    Text(partition.highWatermark.map(String.init) ?? "-").monospacedDigit()
                    Text(partition.messageCount.map(String.init) ?? "-").monospacedDigit().fontWeight(.medium)
                }
                .font(.callout)
            }
        }
        .padding(.vertical, 4)
        .padding(.leading, 4)
    }
}
