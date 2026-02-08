import SwiftUI

struct MessageBrowserView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedTopicName: String?
    @State private var selectedPartition: Int32?
    @State private var maxMessages = Constants.defaultMaxMessages
    @State private var messages: [KafkaMessageRecord] = []
    @State private var isFetching = false
    @State private var fetchError: String?
    @State private var messageFormat: MessageFormat = .utf8
    @State private var selectedMessageId: UUID?

    var body: some View {
        let l10n = appState.l10n

        VStack(spacing: 0) {
            // Controls
            HStack(spacing: 12) {
                Picker(l10n["messages.topic"], selection: $selectedTopicName) {
                    Text("--").tag(nil as String?)
                    ForEach(userTopics, id: \.name) { topic in
                        Text(topic.name).tag(topic.name as String?)
                    }
                }
                .fixedSize()

                Picker(l10n["messages.partition"], selection: $selectedPartition) {
                    Text(l10n["messages.partition.all"]).tag(nil as Int32?)
                    if let topic = selectedTopic {
                        ForEach(topic.partitions) { partition in
                            Text("\(partition.partitionId)").tag(partition.partitionId as Int32?)
                        }
                    }
                }
                .fixedSize()

                Stepper(
                    "\(l10n["messages.fetch.count"]): \(maxMessages)",
                    value: $maxMessages,
                    in: 10 ... 500,
                    step: 10,
                )
                .fixedSize()

                Spacer()

                Picker(l10n["messages.format"], selection: $messageFormat) {
                    ForEach(MessageFormat.allCases) { format in
                        Text(format.rawValue).tag(format)
                    }
                }
                .fixedSize()

                Button {
                    fetchMessages()
                } label: {
                    if isFetching {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(l10n["messages.fetch"])
                    }
                }
                .disabled(selectedTopicName == nil || isFetching)
            }
            .padding(12)

            if let error = fetchError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text(error)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }

            if messages.isEmpty, !isFetching {
                ContentUnavailableView(
                    l10n["messages.empty"],
                    systemImage: "envelope",
                    description: Text(selectedTopicName == nil
                        ? l10n["messages.select.topic"]
                        : l10n["messages.empty.description"]),
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(messages, selection: $selectedMessageId) {
                    TableColumn(l10n["messages.offset"]) { message in
                        Text("\(message.offset)")
                            .monospacedDigit()
                    }
                    .width(min: 60, ideal: 80)

                    TableColumn(l10n["messages.partition"]) { message in
                        Text("\(message.partition)")
                    }
                    .width(min: 50, ideal: 70)

                    TableColumn(l10n["messages.key"]) { message in
                        Text(message.keyString(format: messageFormat))
                            .lineLimit(1)
                    }
                    .width(min: 80, ideal: 120)

                    TableColumn(l10n["messages.value"]) { message in
                        Text(message.valueString(format: messageFormat))
                            .lineLimit(1)
                    }

                    TableColumn(l10n["messages.timestamp"]) { message in
                        if let timestamp = message.timestamp {
                            Text(timestamp, style: .date)
                                + Text(" ")
                                + Text(timestamp, style: .time)
                        } else {
                            Text("-")
                        }
                    }
                    .width(min: 140, ideal: 180)
                }
            }
        }
        .overlay(alignment: .trailing) {
            if let message = selectedMessage {
                MessageDetailView(message: message, format: messageFormat)
                    .frame(width: 320)
                    .compositingGroup()
                    .background(Color(nsColor: .windowBackgroundColor))
                    .overlay(alignment: .leading) { Divider() }
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(.smooth(duration: 0.25), value: selectedMessageId)
        .navigationTitle(l10n["messages.title"])
    }

    private var userTopics: [TopicInfo] {
        appState.topics.filter { !$0.isInternal }
    }

    private var selectedTopic: TopicInfo? {
        guard let name = selectedTopicName else { return nil }
        return appState.topics.first { $0.name == name }
    }

    private var selectedMessage: KafkaMessageRecord? {
        guard let id = selectedMessageId else { return nil }
        return messages.first { $0.id == id }
    }

    private func fetchMessages() {
        guard let topicName = selectedTopicName else { return }
        isFetching = true
        fetchError = nil

        Task {
            do {
                messages = try await appState.fetchMessages(
                    topic: topicName,
                    partition: selectedPartition,
                    maxMessages: maxMessages,
                )
            } catch {
                fetchError = error.localizedDescription
            }
            isFetching = false
        }
    }
}

struct MessageDetailView: View {
    @Environment(AppState.self) private var appState
    let message: KafkaMessageRecord
    let format: MessageFormat

    var body: some View {
        let l10n = appState.l10n

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(l10n["messages.detail"])
                    .font(.headline)

                Group {
                    DetailRow(label: "Topic", value: message.topic)
                    DetailRow(label: l10n["messages.partition"], value: "\(message.partition)")
                    DetailRow(label: l10n["messages.offset"], value: "\(message.offset)")

                    if let ts = message.timestamp {
                        DetailRow(label: l10n["messages.timestamp"], value: ts.formatted())
                    }

                    Divider()

                    Text(l10n["messages.key"])
                        .font(.subheadline.bold())
                    Text(message.keyString(format: format))
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

                    Divider()

                    Text(l10n["messages.value"])
                        .font(.subheadline.bold())
                    Text(message.valueString(format: format))
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding()
        }
    }
}

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)
            Text(value)
                .textSelection(.enabled)
        }
    }
}
