import SwiftUI

struct MessageBrowserView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedTopicName: String? = UserDefaults.standard.string(forKey: "messages.selectedTopic")
    @State private var selectedPartition: Int32? = {
        let val = UserDefaults.standard.object(forKey: "messages.selectedPartition")
        return val != nil ? Int32(UserDefaults.standard.integer(forKey: "messages.selectedPartition")) : nil
    }()

    @AppStorage("messages.fetchLimit") private var maxMessages = Constants.defaultMaxMessages
    @AppStorage("messages.newestFirst") private var newestFirst = true
    @State private var offsetFromText = ""
    @State private var offsetToText = ""
    @FocusState private var fromFieldFocused: Bool
    @FocusState private var toFieldFocused: Bool
    @State private var messages: [KafkaMessageRecord] = []
    @State private var isFetching = false
    @State private var fetchError: String?
    @AppStorage("messages.format") private var messageFormat: MessageFormat = .utf8
    @State private var selectedMessageId: String?
    @State private var detailMessage: KafkaMessageRecord?
    @State private var detailPanelWidth: CGFloat = 320
    @State private var refreshRotation: Double = 0
    @State private var refreshHovered = false
    @State private var controlsOverflow = false
    @State private var controlsContentWidth: CGFloat = 0

    var body: some View {
        @Bindable var appState = appState
        let l10n = appState.l10n

        VStack(spacing: 0) {
            // Controls
            HStack(spacing: 12) {
                // Left group — scrollable when space is tight
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        Picker(l10n["messages.topic"], selection: validatedTopicBinding) {
                            Text("--").tag(nil as String?)
                            ForEach(userTopics, id: \.name) { topic in
                                Text(topic.name).tag(topic.name as String?)
                            }
                        }
                        .fixedSize()

                        Picker(l10n["messages.partition"], selection: validatedPartitionBinding) {
                            Text(l10n["messages.partition.all"]).tag(nil as Int32?)
                            if let topic = selectedTopic {
                                ForEach(topic.partitions) { partition in
                                    Text("\(partition.partitionId)").tag(partition.partitionId as Int32?)
                                }
                            }
                        }
                        .fixedSize()

                        HStack(spacing: 4) {
                            Text(l10n["messages.fetch.count"])
                            TextField("", value: $maxMessages, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(minWidth: 40)
                                .fixedSize()
                                .multilineTextAlignment(.center)
                            Stepper("", value: $maxMessages, in: 10 ... 500, step: 10)
                                .labelsHidden()
                        }
                        .fixedSize()

                        Picker(l10n["messages.direction"], selection: $newestFirst) {
                            Text(l10n["messages.direction.newest"]).tag(true)
                            Text(l10n["messages.direction.oldest"]).tag(false)
                        }
                        .fixedSize()

                        HStack(spacing: 4) {
                            Text(l10n["messages.offset.from"])
                            TextField(
                                "",
                                text: $offsetFromText,
                                prompt: Text(effectiveLowWatermark.map(String.init) ?? "")
                                    .foregroundStyle(.clear),
                            )
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 50)
                            .fixedSize()
                            .multilineTextAlignment(.center)
                            .focused($fromFieldFocused)
                            .overlay(alignment: .center) {
                                if offsetFromText.isEmpty, let wm = effectiveLowWatermark {
                                    Text(String(wm))
                                        .foregroundStyle(Color(.placeholderTextColor))
                                        .contentTransition(.numericText())
                                        .allowsHitTesting(false)
                                }
                            }
                            .onChange(of: offsetFromText) { _, newValue in
                                offsetFromText = newValue.filter(\.isNumber)
                            }
                            .onSubmit { clampOffsetFields() }
                            .onChange(of: fromFieldFocused) { _, focused in
                                if !focused { clampOffsetFields() }
                            }
                        }
                        .fixedSize()
                        .animation(.snappy, value: effectiveLowWatermark)
                        .disabled(selectedPartition == nil)
                        .opacity(selectedPartition == nil ? 0.5 : 1)

                        HStack(spacing: 4) {
                            Text(l10n["messages.offset.to"])
                            TextField(
                                "",
                                text: $offsetToText,
                                prompt: Text(effectiveHighWatermark.map(String.init) ?? "")
                                    .foregroundStyle(.clear),
                            )
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 50)
                            .fixedSize()
                            .multilineTextAlignment(.center)
                            .focused($toFieldFocused)
                            .overlay(alignment: .center) {
                                if offsetToText.isEmpty, let wm = effectiveHighWatermark {
                                    Text(String(wm))
                                        .foregroundStyle(Color(.placeholderTextColor))
                                        .contentTransition(.numericText())
                                        .allowsHitTesting(false)
                                }
                            }
                            .onChange(of: offsetToText) { _, newValue in
                                offsetToText = newValue.filter(\.isNumber)
                            }
                            .onSubmit { clampOffsetFields() }
                            .onChange(of: toFieldFocused) { _, focused in
                                if !focused { clampOffsetFields() }
                            }
                        }
                        .fixedSize()
                        .disabled(selectedPartition == nil)
                        .opacity(selectedPartition == nil ? 0.5 : 1)
                        .animation(.snappy, value: effectiveHighWatermark)

                        if appState.defaultRefreshMode == .manual {
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
                            .disabled(selectedTopicName == nil || isFetching || offsetRangeInvalid)
                        } else {
                            Button {
                                fetchMessages()
                                appState.refreshManager.restart()
                                withAnimation(.easeInOut(duration: 0.6)) {
                                    refreshRotation += 360
                                }
                            } label: {
                                Image(systemName: "arrow.trianglehead.2.clockwise")
                                    .rotationEffect(.degrees(refreshRotation))
                                    .padding(4)
                                    .background(
                                        refreshHovered ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
                                        in: RoundedRectangle(cornerRadius: 4),
                                    )
                            }
                            .buttonStyle(.plain)
                            .disabled(selectedTopicName == nil || isFetching || offsetRangeInvalid)
                            .onHover { refreshHovered = $0 }
                            .help(l10n["common.refresh"])
                        }
                    }
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.width
                    } action: { contentWidth in
                        controlsContentWidth = contentWidth
                    }
                }
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.width
                } action: { viewportWidth in
                    controlsOverflow = controlsContentWidth > viewportWidth
                }
                // Trailing fade overlay — only when content overflows
                .overlay(alignment: .trailing) {
                    LinearGradient(
                        colors: [.clear, Color(nsColor: .windowBackgroundColor)],
                        startPoint: .leading,
                        endPoint: .trailing,
                    )
                    .frame(width: 40)
                    .allowsHitTesting(false)
                    .opacity(controlsOverflow ? 1 : 0)
                }

                // Right group — sits naturally, no extra background
                Picker(l10n["messages.format"], selection: $messageFormat) {
                    ForEach(MessageFormat.allCases) { format in
                        Text(format.rawValue).tag(format)
                    }
                }
                .fixedSize()
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
                Table(sortedMessages, selection: Binding(
                    get: { selectedMessageId },
                    set: { newValue in
                        selectedMessageId = newValue
                        if let id = newValue, let msg = sortedMessages.first(where: { $0.id == id }) {
                            detailMessage = msg
                        } else if newValue == nil {
                            detailMessage = nil
                        }
                    },
                ), sortOrder: $appState.messagesSortOrder) {
                    TableColumn(l10n["messages.offset"], value: \.offset) { message in
                        Text("\(message.offset)")
                            .monospacedDigit()
                            .padding(.vertical, appState.rowDensity.tablePadding)
                    }
                    .width(min: 50, ideal: 70, max: 90)

                    TableColumn(l10n["messages.partition"], value: \.partition) { message in
                        Text("\(message.partition)")
                            .padding(.vertical, appState.rowDensity.tablePadding)
                    }
                    .width(min: 40, ideal: 55, max: 70)

                    TableColumn(l10n["messages.key"]) { message in
                        Text(message.keyString(format: messageFormat))
                            .lineLimit(1)
                            .padding(.vertical, appState.rowDensity.tablePadding)
                    }
                    .width(min: 60, ideal: 100, max: 150)

                    TableColumn(l10n["messages.value"]) { message in
                        Text(message.valueString(format: messageFormat))
                            .lineLimit(1)
                            .padding(.vertical, appState.rowDensity.tablePadding)
                    }

                    TableColumn(l10n["messages.timestamp"], value: \.timestamp) { message in
                        if let timestamp = message.timestamp {
                            (Text(timestamp, style: .date)
                                + Text(" ")
                                + Text(timestamp, style: .time))
                                .padding(.vertical, appState.rowDensity.tablePadding)
                        } else {
                            Text("-")
                                .padding(.vertical, appState.rowDensity.tablePadding)
                        }
                    }
                    .width(min: 140, ideal: 170, max: 200)
                }
                .font(.system(size: appState.rowDensity.fontSize))
            }
        }
        .overlay(alignment: .trailing) {
            if let message = detailMessage {
                HStack(spacing: 0) {
                    // Drag handle on left edge
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: 6)
                        .contentShape(Rectangle())
                        .onHover { hovering in
                            if hovering {
                                NSCursor.resizeLeftRight.push()
                            } else {
                                NSCursor.pop()
                            }
                        }
                        .gesture(
                            DragGesture(minimumDistance: 1)
                                .onChanged { value in
                                    let newWidth = detailPanelWidth - value.translation.width
                                    detailPanelWidth = min(600, max(240, newWidth))
                                },
                        )

                    MessageDetailView(message: message, format: messageFormat) {
                        selectedMessageId = nil
                        detailMessage = nil
                    }
                }
                .frame(width: detailPanelWidth)
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
        .animation(.smooth(duration: 0.25), value: detailMessage?.id)
        .onKeyPress(.escape) {
            if detailMessage != nil {
                selectedMessageId = nil
                detailMessage = nil
                return .handled
            }
            return .ignored
        }
        .onChange(of: selectedTopicName) {
            UserDefaults.standard.set(selectedTopicName, forKey: "messages.selectedTopic")
            selectedPartition = nil
            selectedMessageId = nil
            detailMessage = nil
            offsetFromText = ""
            offsetToText = ""
            if selectedTopicName != nil {
                fetchMessages()
            } else {
                messages = []
                fetchError = nil
            }
        }
        .onChange(of: selectedPartition) {
            if let p = selectedPartition {
                UserDefaults.standard.set(Int(p), forKey: "messages.selectedPartition")
            } else {
                UserDefaults.standard.removeObject(forKey: "messages.selectedPartition")
            }
            clampOffsetFields()
        }
        .onChange(of: appState.refreshManager.tick) {
            if selectedTopicName != nil {
                fetchMessages()
            }
            withAnimation(.easeInOut(duration: 0.6)) {
                refreshRotation += 360
            }
        }
        .onChange(of: appState.connectionStatus.isConnected) {
            if appState.connectionStatus.isConnected, selectedTopicName != nil, appState.refreshManager.isAutoRefresh {
                fetchMessages()
                appState.refreshManager.restart()
            }
        }
        .onChange(of: userTopics.map(\.name)) {
            // Reset selection if the previously selected topic no longer exists
            if let name = selectedTopicName, !userTopics.contains(where: { $0.name == name }) {
                selectedTopicName = nil
            }
        }
        .onAppear {
            if appState.connectionStatus.isConnected, selectedTopicName != nil, messages.isEmpty, appState.refreshManager.isAutoRefresh {
                fetchMessages()
                appState.refreshManager.restart()
            }
        }
        .navigationTitle(l10n["messages.title"])
    }

    private var sortedMessages: [KafkaMessageRecord] {
        messages.sorted(using: appState.messagesSortOrder)
    }

    /// Binding that returns nil when the stored topic isn't in the current list,
    /// preventing SwiftUI Picker "invalid selection" warnings during loading/cluster switch.
    private var validatedTopicBinding: Binding<String?> {
        Binding(
            get: {
                guard let name = selectedTopicName,
                      userTopics.contains(where: { $0.name == name })
                else { return nil }
                return name
            },
            set: { selectedTopicName = $0 },
        )
    }

    private var validatedPartitionBinding: Binding<Int32?> {
        Binding(
            get: {
                guard let id = selectedPartition,
                      selectedTopic?.partitions.contains(where: { $0.partitionId == id }) == true
                else { return nil }
                return id
            },
            set: { selectedPartition = $0 },
        )
    }

    private var userTopics: [TopicInfo] {
        appState.topics.filter { !$0.isInternal }
    }

    private var selectedTopic: TopicInfo? {
        guard let name = selectedTopicName else { return nil }
        return appState.topics.first { $0.name == name }
    }

    private var offsetRangeInvalid: Bool {
        guard let from = Int64(offsetFromText), let to = Int64(offsetToText) else { return false }
        return from > to
    }

    private var effectiveLowWatermark: Int64? {
        guard let topic = selectedTopic else { return nil }
        if let partId = selectedPartition {
            return topic.partitions.first { $0.partitionId == partId }?.lowWatermark
        }
        let lows = topic.partitions.compactMap(\.lowWatermark)
        return lows.isEmpty ? nil : lows.min()
    }

    /// Last readable offset (high watermark - 1), since high watermark is the next offset to be written.
    private var effectiveHighWatermark: Int64? {
        guard let topic = selectedTopic else { return nil }
        let raw: Int64?
        if let partId = selectedPartition {
            raw = topic.partitions.first { $0.partitionId == partId }?.highWatermark
        } else {
            let highs = topic.partitions.compactMap(\.highWatermark)
            raw = highs.isEmpty ? nil : highs.max()
        }
        guard let high = raw else { return nil }
        return max(0, high - 1)
    }

    private func clampOffsetFields() {
        if let value = Int64(offsetFromText), let low = effectiveLowWatermark, value < low {
            offsetFromText = String(low)
        }
        if let value = Int64(offsetToText), let high = effectiveHighWatermark, value > high {
            offsetToText = String(high)
        }
    }

    private func fetchMessages() {
        guard let topicName = selectedTopicName else { return }
        isFetching = true
        fetchError = nil

        Task {
            do {
                let parsedFrom = Int64(offsetFromText)
                let parsedTo = Int64(offsetToText)
                let newMessages = try await appState.fetchMessages(
                    topic: topicName,
                    partition: selectedPartition,
                    maxMessages: maxMessages,
                    newestFirst: newestFirst,
                    offsetFrom: parsedFrom,
                    offsetTo: parsedTo,
                )

                // Reconcile selection: stable IDs mean the same message keeps the same ID
                if let id = selectedMessageId {
                    if let msg = newMessages.first(where: { $0.id == id }) {
                        // Message still in results — keep highlight and update detail
                        detailMessage = msg
                    } else {
                        // Message gone — remove highlight but keep detail panel open
                        selectedMessageId = nil
                    }
                }

                messages = newMessages
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
    var onDismiss: () -> Void = {}
    @State private var keyCopied = false
    @State private var valueCopied = false
    @State private var wrapText = false

    var body: some View {
        let l10n = appState.l10n

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    PanelCloseButton(action: onDismiss)
                    Text(l10n["messages.detail"])
                        .font(.headline)
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { wrapText.toggle() }
                    } label: {
                        Label(wrapText ? "Wrap" : "Scroll", systemImage: wrapText ? "text.justify.left" : "scroll")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Group {
                    DetailRow(label: "Topic", value: message.topic)
                    DetailRow(label: l10n["messages.partition"], value: "\(message.partition)")
                    DetailRow(label: l10n["messages.offset"], value: "\(message.offset)")

                    if let ts = message.timestamp {
                        DetailRow(label: l10n["messages.timestamp"], value: ts.formatted())
                    }

                    HStack {
                        Text(l10n["messages.key"])
                            .font(.subheadline.bold())
                        Spacer()
                        CopyButton(text: message.keyPrettyString(format: format), copied: $keyCopied)
                    }
                    codeBlock(message.keyPrettyString(format: format))

                    HStack {
                        Text(l10n["messages.value"])
                            .font(.subheadline.bold())
                        Spacer()
                        CopyButton(text: message.valuePrettyString(format: format), copied: $valueCopied)
                    }
                    codeBlock(message.valuePrettyString(format: format))

                    if !message.headers.isEmpty {
                        Text(l10n["messages.headers"])
                            .font(.subheadline.bold())
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(message.headers.enumerated()), id: \.offset) { _, header in
                                HStack(alignment: .top, spacing: 8) {
                                    Text(header.0)
                                        .foregroundStyle(.blue)
                                    Text(String(data: header.1, encoding: .utf8) ?? header.1.map { String(format: "%02x", $0) }.joined(separator: " "))
                                        .foregroundStyle(.secondary)
                                }
                                .font(.system(.body, design: .monospaced))
                            }
                        }
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
            .padding()
        }
        .onChange(of: message.id) {
            keyCopied = false
            valueCopied = false
        }
    }

    @ViewBuilder
    private func codeBlock(_ text: String) -> some View {
        if wrapText {
            colorizedText(text)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        } else {
            ScrollView(.horizontal, showsIndicators: true) {
                colorizedText(text)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(nil)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private func colorizedText(_ string: String) -> Text {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{") || trimmed.hasPrefix("[") else {
            return Text(string)
        }
        return colorizeJSON(string)
    }

    private func colorizeJSON(_ json: String) -> Text {
        var result = Text("")
        var index = json.startIndex

        while index < json.endIndex {
            let char = json[index]

            if char == "\"" {
                let start = index
                index = json.index(after: index)
                while index < json.endIndex {
                    if json[index] == "\\" {
                        index = json.index(after: index)
                        if index < json.endIndex {
                            index = json.index(after: index)
                        }
                        continue
                    }
                    if json[index] == "\"" {
                        index = json.index(after: index)
                        break
                    }
                    index = json.index(after: index)
                }
                let token = String(json[start ..< index])
                let rest = json[index...].drop { $0 == " " }
                if rest.first == ":" {
                    result = result + Text(token).foregroundStyle(.blue)
                } else {
                    result = result + Text(token).foregroundStyle(.orange)
                }
            } else if char == "-" || char.isNumber {
                let start = index
                while index < json.endIndex, "0123456789.eE+-".contains(json[index]) {
                    index = json.index(after: index)
                }
                result = result + Text(String(json[start ..< index])).foregroundStyle(.purple)
            } else if json[index...].hasPrefix("true") {
                result = result + Text("true").foregroundStyle(.cyan)
                index = json.index(index, offsetBy: 4)
            } else if json[index...].hasPrefix("false") {
                result = result + Text("false").foregroundStyle(.cyan)
                index = json.index(index, offsetBy: 5)
            } else if json[index...].hasPrefix("null") {
                result = result + Text("null").foregroundStyle(.red)
                index = json.index(index, offsetBy: 4)
            } else {
                result = result + Text(String(char))
                index = json.index(after: index)
            }
        }

        return result
    }
}

private struct CopyButton: View {
    @Environment(AppState.self) private var appState
    let text: String
    @Binding var copied: Bool
    @State private var isHovered = false

    var body: some View {
        let l10n = appState.l10n
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                copied = false
            }
        } label: {
            Text(copied ? l10n["common.copied"] : l10n["common.copy"])
                .font(.caption)
                .foregroundStyle(copied ? .green : isHovered ? .primary : .secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(isHovered ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

struct PanelCloseButton: View {
    @Environment(AppState.self) private var appState
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isHovered ? Color.red : Color.secondary.opacity(0.2))
                    .frame(width: 14, height: 14)
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(isHovered ? .white : .secondary)
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(appState.l10n["common.close"])
    }
}

struct DetailRow: View {
    let label: String
    let value: String

    @State private var showCopied = false
    @State private var isHighlighted = false

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 100, alignment: .trailing)
            Text(showCopied ? "Copied" : value)
                .foregroundStyle(showCopied ? .green : .primary)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isHighlighted ? Color.accentColor.opacity(0.15) : .clear),
                )
                .contentTransition(.opacity)
                .onTapGesture {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(value, forType: .string)

                    withAnimation(.easeIn(duration: 0.1)) {
                        isHighlighted = true
                        showCopied = true
                    }
                    withAnimation(.easeOut(duration: 0.3).delay(0.8)) {
                        showCopied = false
                        isHighlighted = false
                    }
                }
        }
    }
}
