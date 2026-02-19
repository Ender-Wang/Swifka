import SwiftUI

struct TopicListView: View {
    @Environment(AppState.self) private var appState
    @State private var searchText = ""
    @AppStorage("topics.hideInternal") private var hideInternal = true

    var body: some View {
        let l10n = appState.l10n

        VStack(spacing: 0) {
            // Summary stat bar
            if !appState.topics.isEmpty {
                summaryBar(l10n: l10n)
            }

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
                                .font(.system(size: appState.rowDensity.fontSize))
                                .fontWeight(topic.isInternal ? .regular : .medium)
                                .foregroundStyle(topic.isInternal ? .secondary : .primary)
                            Spacer()
                            Text("\(topic.partitionCount) \(l10n["topics.partitions"])")
                                .foregroundStyle(.secondary)
                                .font(.system(size: appState.rowDensity.captionSize))
                            Text("·")
                                .foregroundStyle(.quaternary)
                            Text("\(topic.replicaCount) \(l10n["topics.replicas"])")
                                .foregroundStyle(.secondary)
                                .font(.system(size: appState.rowDensity.captionSize))
                        }
                        .padding(.vertical, appState.rowDensity.tablePadding)
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
            .overlay {
                if appState.topics.isEmpty {
                    ContentUnavailableView(
                        l10n["topics.empty"],
                        systemImage: "list.bullet.rectangle",
                        description: Text(l10n["topics.empty.description"]),
                    )
                } else if filteredTopics.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
        }
        .navigationTitle(l10n["topics.title"])
        .onAppear { expandFirstTopicIfNeeded() }
        .onChange(of: appState.topics) { expandFirstTopicIfNeeded() }
    }

    private func summaryBar(l10n: L10n) -> some View {
        let visibleTopics = filteredTopics
        let totalPartitions = visibleTopics.reduce(0) { $0 + $1.partitionCount }
        let totalMessages = visibleTopics.reduce(into: Int64(0)) { total, topic in
            total += topic.partitions.compactMap(\.messageCount).reduce(0, +)
        }

        return HStack(spacing: 16) {
            statPill(label: l10n["topics.summary.topics"], value: "\(visibleTopics.count)")
            statPill(label: l10n["topics.summary.partitions"], value: "\(totalPartitions)")
            if totalMessages > 0 {
                statPill(label: l10n["topics.summary.messages"], value: formatCount(totalMessages))
            }

            Spacer()

            Toggle(isOn: $hideInternal) {
                Text(l10n["topics.hide.internal"])
            }
            .toggleStyle(.checkbox)
            .font(.caption)

            searchField(prompt: l10n["topics.search"])
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func statPill(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(value)
                .fontWeight(.semibold)
                .monospacedDigit()
            Text(label)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }

    private func searchField(prompt: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.caption)
            TextField(prompt, text: $searchText)
                .textFieldStyle(.plain)
                .font(.caption)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
        .frame(width: 160)
    }

    private func expandFirstTopicIfNeeded() {
        if appState.expandedTopics.isEmpty, let first = filteredTopics.first {
            appState.expandedTopics.insert(first.name)
        }
    }

    private func formatCount(_ count: Int64) -> String {
        if count >= 1_000_000_000 { return String(format: "%.1fB", Double(count) / 1_000_000_000) }
        if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
        if count >= 1000 { return String(format: "%.1fK", Double(count) / 1000) }
        return "\(count)"
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

        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: appState.rowDensity.gridSpacing) {
            GridRow {
                Text(l10n["topic.detail.partition.id"]).foregroundStyle(.secondary)
                Text(l10n["topic.detail.leader"]).foregroundStyle(.secondary)
                Text(l10n["topic.detail.replicas"]).foregroundStyle(.secondary)
                Text(l10n["topic.detail.isr"]).foregroundStyle(.secondary)
                Text(l10n["topic.detail.low.watermark"]).foregroundStyle(.secondary)
                Text(l10n["topic.detail.high.watermark"]).foregroundStyle(.secondary)
                Text(l10n["topic.detail.messages"]).foregroundStyle(.secondary)
            }
            .font(.system(size: appState.rowDensity.captionSize))

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
                .font(.system(size: appState.rowDensity.fontSize))
            }
        }
        .padding(.vertical, appState.rowDensity.tablePadding)
        .padding(.leading, 4)
    }
}
