import SwiftUI

struct TopicListView: View {
    @Environment(AppState.self) private var appState
    @State private var searchText = ""
    @State private var selectedTopicId: String?
    @State private var hideInternal = true

    var body: some View {
        let l10n = appState.l10n

        Table(filteredTopics, selection: $selectedTopicId) {
            TableColumn(l10n["topics.name"]) { topic in
                Text(topic.name)
                    .fontWeight(topic.isInternal ? .regular : .medium)
                    .foregroundStyle(topic.isInternal ? .secondary : .primary)
            }

            TableColumn(l10n["topics.partitions"]) { topic in
                Text("\(topic.partitionCount)")
            }
            .width(min: 60, ideal: 90)

            TableColumn(l10n["topics.replicas"]) { topic in
                Text("\(topic.replicaCount)")
            }
            .width(min: 60, ideal: 90)
        }
        .searchable(text: $searchText, prompt: Text(l10n["topics.search"]))
        .overlay(alignment: .trailing) {
            if let topic = selectedTopic {
                TopicDetailView(topic: topic)
                    .scrollContentBackground(.hidden)
                    .frame(width: 450)
                    .compositingGroup()
                    .background(Color(nsColor: .windowBackgroundColor))
                    .overlay(alignment: .leading) { Divider() }
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(.smooth(duration: 0.25), value: selectedTopicId)
        .navigationTitle(l10n["topics.title"])
        .toolbar {
            ToolbarItem {
                Toggle(isOn: $hideInternal) {
                    Text(l10n["topics.hide.internal"])
                }
                .toggleStyle(.checkbox)
            }
        }
    }

    private var filteredTopics: [TopicInfo] {
        appState.topics.filter { topic in
            if hideInternal, topic.isInternal { return false }
            if searchText.isEmpty { return true }
            return topic.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var selectedTopic: TopicInfo? {
        guard let id = selectedTopicId else { return nil }
        return filteredTopics.first { $0.id == id }
    }
}
