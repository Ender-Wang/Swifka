import SwiftUI
import UniformTypeIdentifiers

struct MessageBrowserView: View {
    @Environment(AppState.self) private var appState
    @State private var deserializerConfigStore = DeserializerConfigStore.shared
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
    @State private var fetchTask: Task<Void, Never>?
    @State private var messageFormat: MessageFormat = .utf8
    @State private var protoManager = ProtobufConfigManager.shared
    @State private var selectedProtoFileID: UUID?
    @State private var selectedProtoMessageType: String?
    @State private var isImportingProtoFile = false
    @State private var selectedMessageId: String?
    @State private var detailMessage: KafkaMessageRecord?
    @State private var detailPanelWidth: CGFloat = 320
    @State private var refreshRotation: Double = 0
    @State private var refreshHovered = false
    @State private var controlsOverflow = false
    @State private var controlsContentWidth: CGFloat = 0

    // Pagination
    @State private var currentPage = 0
    private let messagesPerPage = 500

    // Search
    @State private var searchQuery = ""
    @State private var searchScope: SearchScope = .both
    @State private var isRegex = false
    @State private var isCaseSensitive = false
    @State private var isJsonPath = false

    enum SearchScope: String, CaseIterable, Identifiable {
        case key, value, both
        var id: String {
            rawValue
        }
    }

    // Time Range Filter
    @State private var showTimeFilter = false
    @State private var timeRangeFrom: Date?
    @State private var timeRangeTo: Date?

    @ViewBuilder
    private var mainContent: some View {
        let l10n = appState.l10n

        VStack(spacing: 0) {
            searchBar
            controlsBar

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
                messageTable

                if totalPages > 1 {
                    pageBar
                }
            }
        }
        .onChange(of: searchQuery) { _, _ in currentPage = 0 }
        .onChange(of: searchScope) { _, _ in currentPage = 0 }
        .onChange(of: isRegex) { _, _ in currentPage = 0 }
        .onChange(of: isCaseSensitive) { _, _ in currentPage = 0 }
        .onChange(of: isJsonPath) { _, _ in currentPage = 0 }
        .onChange(of: timeRangeFrom) { _, _ in currentPage = 0 }
        .onChange(of: timeRangeTo) { _, _ in currentPage = 0 }
    }

    var body: some View {
        let l10n = appState.l10n

        mainContent
            .overlay(alignment: .trailing) {
                if let message = detailMessage {
                    detailPanel(for: message)
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
                currentPage = 0
                searchQuery = ""
                timeRangeFrom = nil
                timeRangeTo = nil
                showTimeFilter = false
                loadFormatForTopic(selectedTopicName) // Restore saved format
                if messageFormat == .protobuf {
                    loadProtobufConfig()
                }
                if selectedTopicName != nil {
                    fetchMessages()
                } else {
                    messages = []
                    fetchError = nil
                }
            }
            .onChange(of: messageFormat) {
                saveFormatForTopic(messageFormat) // Save format when changed
            }
            .onAppear {
                loadFormatForTopic(selectedTopicName) // Load format on initial appear
            }
            .onChange(of: selectedPartition) {
                if let p = selectedPartition {
                    UserDefaults.standard.set(Int(p), forKey: "messages.selectedPartition")
                } else {
                    UserDefaults.standard.removeObject(forKey: "messages.selectedPartition")
                }
                currentPage = 0
                clampOffsetFields()
            }
            .onChange(of: newestFirst) {
                currentPage = 0
            }
            .onChange(of: appState.refreshManager.tick) {
                if selectedTopicName != nil, !isFetching {
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

    // MARK: - Search Bar

    @ViewBuilder
    private var searchBar: some View {
        let l10n = appState.l10n

        HStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    searchControls(l10n: l10n)
                }
            }

            Divider()
                .frame(height: 20)

            timeFilterSection(l10n: l10n)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private func searchControls(l10n: L10n) -> some View {
        searchTextField(l10n: l10n)
        searchScopePicker(l10n: l10n)
        searchOptions(l10n: l10n)

        if !searchQuery.isEmpty || hasActiveTimeFilter {
            filterResults(l10n: l10n)
        }
    }

    private func searchTextField(l10n: L10n) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 13))

            TextField(l10n["messages.search.placeholder"], text: $searchQuery)
                .textFieldStyle(.plain)

            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        .frame(minWidth: 200, idealWidth: 300)
    }

    private func searchScopePicker(l10n: L10n) -> some View {
        Picker(l10n["messages.search.scope"], selection: $searchScope) {
            Text(l10n["messages.search.scope.key"]).tag(SearchScope.key)
            Text(l10n["messages.search.scope.value"]).tag(SearchScope.value)
            Text(l10n["messages.search.scope.both"]).tag(SearchScope.both)
        }
        .fixedSize()
    }

    private func searchOptions(l10n: L10n) -> some View {
        Group {
            Toggle(isOn: Binding(
                get: { isRegex },
                set: { newValue in
                    isRegex = newValue
                    if newValue {
                        isJsonPath = false // Mutually exclusive
                    }
                },
            )) {
                Text(l10n["messages.search.regex"])
            }
            .toggleStyle(.checkbox)
            .disabled(isJsonPath)

            Toggle(isOn: $isCaseSensitive) {
                Text(l10n["messages.search.case.sensitive"])
            }
            .toggleStyle(.checkbox)

            Toggle(isOn: Binding(
                get: { isJsonPath },
                set: { newValue in
                    isJsonPath = newValue
                    if newValue {
                        isRegex = false // Mutually exclusive
                        searchScope = .value // Auto-set to Value
                    }
                },
            )) {
                Text(l10n["messages.search.jsonpath"])
            }
            .toggleStyle(.checkbox)
            .disabled(isRegex)
        }
    }

    @ViewBuilder
    private func timeFilterSection(l10n: L10n) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                showTimeFilter.toggle()
            }
            if !showTimeFilter {
                // Clear filter when hiding
                timeRangeFrom = nil
                timeRangeTo = nil
            }
        } label: {
            Image(systemName: showTimeFilter ? "clock.fill" : "clock")
                .foregroundStyle(hasActiveTimeFilter ? .blue : .secondary)
                .font(.system(size: 14))
        }
        .buttonStyle(.plain)
        .help(l10n["messages.time.filter.toggle"])
        .padding(.horizontal, 4)

        if showTimeFilter {
            timeFilterControls(l10n: l10n)
                .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private func timeFilterControls(l10n: L10n) -> some View {
        if let minTime = minTimestamp, let maxTime = maxTimestamp {
            HStack(spacing: 8) {
                DatePicker(
                    l10n["messages.time.filter.from"],
                    selection: Binding(
                        get: { timeRangeFrom ?? minTime },
                        set: { timeRangeFrom = $0 },
                    ),
                    in: minTime ... maxTime,
                    displayedComponents: [.date, .hourAndMinute],
                )
                .labelsHidden()
                .fixedSize()

                Text("–")
                    .foregroundStyle(.secondary)

                DatePicker(
                    l10n["messages.time.filter.to"],
                    selection: Binding(
                        get: { timeRangeTo ?? maxTime },
                        set: { timeRangeTo = $0 },
                    ),
                    in: minTime ... maxTime,
                    displayedComponents: [.date, .hourAndMinute],
                )
                .labelsHidden()
                .fixedSize()

                if hasActiveTimeFilter {
                    Button {
                        timeRangeFrom = nil
                        timeRangeTo = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.plain)
                    .help(l10n["messages.time.filter.clear"])
                }
            }
        }
    }

    private func filterResults(l10n: L10n) -> some View {
        Text(l10n.t("messages.search.results", String(filteredMessages.count), String(messages.count)))
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.leading, 8)
    }

    // MARK: - Controls Bar

    @ViewBuilder
    private var controlsBar: some View {
        let l10n = appState.l10n

        HStack(spacing: 12) {
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
                            .frame(minWidth: 50)
                            .fixedSize()
                            .multilineTextAlignment(.center)
                        Stepper("", value: $maxMessages, in: 10 ... Int.max, step: maxMessages >= 500 ? 100 : 10)
                            .labelsHidden()
                    }
                    .fixedSize()

                    Picker(l10n["messages.direction"], selection: $newestFirst) {
                        Text(l10n["messages.direction.newest"]).tag(true)
                        Text(l10n["messages.direction.oldest"]).tag(false)
                    }
                    .fixedSize()

                    offsetFromField
                    offsetToField
                    fetchButton
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

            Picker(l10n["messages.format"], selection: $messageFormat) {
                ForEach(MessageFormat.allCases) { format in
                    Text(format.rawValue).tag(format)
                }
            }
            .fixedSize()
            .onChange(of: messageFormat) { _, newFormat in
                if newFormat == .protobuf {
                    loadProtobufConfig()
                }
            }

            // Inline protobuf pickers (shown when Protobuf format is selected)
            if messageFormat == .protobuf {
                protobufInlinePickers
            }
        }
        .padding(12)
        .fileImporter(
            isPresented: $isImportingProtoFile,
            allowedContentTypes: [.init(filenameExtension: "proto")!],
            allowsMultipleSelection: false,
        ) { result in
            handleProtoFileImport(result)
        }
    }

    // MARK: - Protobuf Inline Pickers

    @ViewBuilder
    private var protobufInlinePickers: some View {
        let l10n = appState.l10n

        Divider()
            .frame(height: 16)

        if clusterProtoFiles.isEmpty {
            Button {
                isImportingProtoFile = true
            } label: {
                Label(l10n["protobuf.import.file"], systemImage: "doc.badge.plus")
            }
            .controlSize(.small)
        } else {
            // Proto file picker with delete menu
            Menu {
                ForEach(clusterProtoFiles) { protoFile in
                    Button {
                        selectedProtoFileID = protoFile.id
                        if let topicName = selectedTopicName {
                            selectedProtoMessageType = autoMatchMessageType(for: topicName)
                        } else {
                            selectedProtoMessageType = nil
                        }
                        saveProtobufConfigIfReady()
                        fetchMessages()
                    } label: {
                        HStack {
                            Text(protoFile.fileName)
                            if protoFile.id == selectedProtoFileID {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }

                Divider()

                Button {
                    isImportingProtoFile = true
                } label: {
                    Label(l10n["protobuf.import.file"], systemImage: "doc.badge.plus")
                }

                if let selectedID = selectedProtoFileID,
                   let file = clusterProtoFiles.first(where: { $0.id == selectedID })
                {
                    Button {
                        NSWorkspace.shared.selectFile(
                            file.filePath,
                            inFileViewerRootedAtPath: "",
                        )
                    } label: {
                        Label(
                            l10n["protobuf.reveal.in.finder"],
                            systemImage: "folder",
                        )
                    }

                    Button(role: .destructive) {
                        protoManager.removeProtoFile(selectedID)
                        selectedProtoFileID = clusterProtoFiles.first?.id
                        selectedProtoMessageType = nil
                        saveProtobufConfigIfReady()
                    } label: {
                        Label(
                            l10n.t("protobuf.delete.file", file.fileName),
                            systemImage: "trash",
                        )
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "doc.text")
                        .font(.caption2)
                    Text(selectedProtoFileName)
                        .lineLimit(1)
                }
            }
            .fixedSize()
            .help(l10n["protobuf.select.file"])

            // Message type picker (shown when a proto file is selected)
            if let selectedFileID = selectedProtoFileID,
               let protoFile = clusterProtoFiles.first(where: { $0.id == selectedFileID }),
               !protoFile.messageTypes.isEmpty
            {
                Picker(
                    l10n["protobuf.select.message"],
                    selection: Binding(
                        get: { selectedProtoMessageType },
                        set: { newValue in
                            if newValue != selectedProtoMessageType {
                                selectedProtoMessageType = newValue
                                saveProtobufConfigIfReady()
                                fetchMessages()
                            }
                        },
                    ),
                ) {
                    Text(l10n["protobuf.select.placeholder"]).tag(nil as String?)

                    ForEach(protoFile.messageTypes, id: \.self) { messageType in
                        Text(isAutoMatchedType && messageType == selectedProtoMessageType
                            ? "\(messageType) — auto" : messageType)
                            .tag(messageType as String?)
                    }
                }
                .fixedSize()
            }
        }
    }

    private var clusterProtoFiles: [ProtoFileInfo] {
        guard let clusterID = appState.configStore.selectedClusterId else { return [] }
        return protoManager.protoFiles(for: clusterID)
    }

    private var selectedProtoFileName: String {
        guard let id = selectedProtoFileID,
              let file = clusterProtoFiles.first(where: { $0.id == id })
        else {
            return appState.l10n["protobuf.select.placeholder"]
        }
        return file.fileName
    }

    /// Whether the current message type selection matches auto-match for the current topic
    private var isAutoMatchedType: Bool {
        guard let topicName = selectedTopicName,
              let currentType = selectedProtoMessageType
        else { return false }
        return autoMatchMessageType(for: topicName) == currentType
    }

    private func loadProtobufConfig() {
        guard let topicName = selectedTopicName else {
            selectedProtoFileID = clusterProtoFiles.first?.id
            selectedProtoMessageType = nil
            return
        }

        // Restore saved config if it exists
        if let config = deserializerConfigStore.config(for: topicName),
           let protoFile = clusterProtoFiles.first(where: { $0.filePath == config.protoFilePath })
        {
            selectedProtoFileID = protoFile.id
            selectedProtoMessageType = config.messageTypeName
            return
        }

        // No saved config — auto-select first proto file
        selectedProtoFileID = clusterProtoFiles.first?.id

        // Auto-match: try to find a message type matching the topic name
        // e.g. topic "protobuf-orders" or "orders" → message type "Order"
        selectedProtoMessageType = autoMatchMessageType(for: topicName)

        // Auto-save if we found a match
        if selectedProtoMessageType != nil {
            saveProtobufConfigIfReady()
        }
    }

    /// Try to match topic name to a proto message type using fuzzy matching.
    /// Picks the longest matching type to avoid "Order" matching before "OrderItem".
    private func autoMatchMessageType(for topicName: String) -> String? {
        guard let fileID = selectedProtoFileID,
              let protoFile = clusterProtoFiles.first(where: { $0.id == fileID })
        else { return nil }

        let normalizedTopic = topicName.lowercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")

        // Strip common format prefixes for better matching
        let strippedTopic = normalizedTopic
            .replacingOccurrences(of: "protobuf", with: "")
            .replacingOccurrences(of: "proto", with: "")
            .replacingOccurrences(of: "pb", with: "")

        // Collect all matches, pick the longest (most specific) one
        var bestMatch: String?
        var bestLength = 0

        for messageType in protoFile.messageTypes {
            let normalizedType = messageType.lowercased()
            var matched = false

            // Direct/exact match
            if normalizedTopic == normalizedType || strippedTopic == normalizedType {
                matched = true
            }
            // Topic contains type: "protobuforderitems" contains "orderitem"
            else if normalizedTopic.contains(normalizedType) {
                matched = true
            }
            // Stripped plural: "orderitems" == "orderitem" + "s"
            else if strippedTopic == normalizedType + "s" {
                matched = true
            }
            // Type contains stripped topic: "orderitem" contains "item"
            else if !strippedTopic.isEmpty, normalizedType.contains(strippedTopic) {
                matched = true
            }
            // Plural in topic: "orders" ↔ "order"
            else if normalizedTopic.contains(normalizedType + "s") ||
                normalizedType + "s" == normalizedTopic
            {
                matched = true
            }

            if matched, normalizedType.count > bestLength {
                bestMatch = messageType
                bestLength = normalizedType.count
            }
        }

        return bestMatch
    }

    private func saveProtobufConfigIfReady() {
        guard let topicName = selectedTopicName,
              let fileID = selectedProtoFileID,
              let protoFile = clusterProtoFiles.first(where: { $0.id == fileID }),
              let messageType = selectedProtoMessageType
        else {
            return
        }

        let config = TopicDeserializerConfig(
            topicName: topicName,
            keyDeserializerID: "protobuf",
            valueDeserializerID: "protobuf",
            protoFilePath: protoFile.filePath,
            messageTypeName: messageType,
        )
        deserializerConfigStore.setConfig(config)
    }

    private func handleProtoFileImport(_ result: Result<[URL], Error>) {
        guard let clusterID = appState.configStore.selectedClusterId else { return }
        do {
            let urls = try result.get()
            guard let url = urls.first else { return }

            let gotAccess = url.startAccessingSecurityScopedResource()
            defer {
                if gotAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            try protoManager.importProtoFile(from: url, clusterID: clusterID)

            // Auto-select the newly imported file
            if let newFile = clusterProtoFiles.last {
                selectedProtoFileID = newFile.id
                if let topicName = selectedTopicName {
                    selectedProtoMessageType = autoMatchMessageType(for: topicName)
                } else {
                    selectedProtoMessageType = nil
                }
            }
        } catch {
            fetchError = error.localizedDescription
        }
    }

    @ViewBuilder
    private var offsetFromField: some View {
        let l10n = appState.l10n
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
    }

    @ViewBuilder
    private var offsetToField: some View {
        let l10n = appState.l10n
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
    }

    @ViewBuilder
    private var fetchButton: some View {
        let l10n = appState.l10n
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

    // MARK: - Page Bar

    private var totalPages: Int {
        guard !filteredMessages.isEmpty else { return 0 }
        return (filteredMessages.count + messagesPerPage - 1) / messagesPerPage
    }

    private var minTimestamp: Date? {
        messages.compactMap(\.timestamp).min()
    }

    private var maxTimestamp: Date? {
        messages.compactMap(\.timestamp).max()
    }

    private var hasActiveTimeFilter: Bool {
        timeRangeFrom != nil || timeRangeTo != nil
    }

    private var filteredMessages: [KafkaMessageRecord] {
        var result = messages

        // Apply text search filter
        if !searchQuery.isEmpty {
            result = result.filter { message in
                matchesSearch(message: message, query: searchQuery)
            }
        }

        // Apply time range filter
        if let from = timeRangeFrom {
            result = result.filter { $0.timestamp >= from }
        }
        if let to = timeRangeTo {
            result = result.filter { $0.timestamp <= to }
        }

        return result
    }

    private var displayedMessages: [KafkaMessageRecord] {
        let sorted = sortedFilteredMessages
        let start = currentPage * messagesPerPage
        let end = min(start + messagesPerPage, sorted.count)
        guard start < sorted.count else { return sorted }
        return Array(sorted[start ..< end])
    }

    private var sortedFilteredMessages: [KafkaMessageRecord] {
        filteredMessages.sorted(using: appState.messagesSortOrder)
    }

    private func matchesSearch(message: KafkaMessageRecord, query: String) -> Bool {
        let keyString = message.keyString(format: messageFormat, protoContext: protoContext)
        let valueString = message.valueString(format: messageFormat, protoContext: protoContext)

        // JSON Path search
        if isJsonPath {
            return matchesJsonPath(valueString: valueString, query: query)
        }

        let searchIn: [String] = switch searchScope {
        case .key:
            [keyString]
        case .value:
            [valueString]
        case .both:
            [keyString, valueString]
        }

        if isRegex {
            guard let regex = try? NSRegularExpression(
                pattern: query,
                options: isCaseSensitive ? [] : .caseInsensitive,
            ) else {
                return false
            }

            return searchIn.contains { text in
                let range = NSRange(text.startIndex..., in: text)
                return regex.firstMatch(in: text, range: range) != nil
            }
        } else {
            let searchQuery = isCaseSensitive ? query : query.lowercased()
            return searchIn.contains { text in
                let searchText = isCaseSensitive ? text : text.lowercased()
                return searchText.contains(searchQuery)
            }
        }
    }

    private func matchesJsonPath(valueString: String, query: String) -> Bool {
        // Parse query: "path:value" or just "path"
        let components = query.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        let path = String(components[0])
        let searchValue = components.count > 1 ? String(components[1]) : nil

        // Parse JSON
        guard let data = valueString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data)
        else {
            return false
        }

        // Navigate to path
        guard let extractedValue = extractValueAtPath(from: json, path: path) else {
            return false
        }

        // If no search value specified, just check existence
        guard let searchValue else {
            return true
        }

        // Convert extracted value to string and search
        let extractedString = String(describing: extractedValue)
        let searchQuery = isCaseSensitive ? searchValue : searchValue.lowercased()
        let searchText = isCaseSensitive ? extractedString : extractedString.lowercased()
        return searchText.contains(searchQuery)
    }

    private func extractValueAtPath(from json: Any, path: String) -> Any? {
        var current: Any = json
        let pathComponents = parseJsonPath(path)

        for component in pathComponents {
            switch component {
            case let .key(key):
                guard let dict = current as? [String: Any],
                      let value = dict[key]
                else {
                    return nil
                }
                current = value

            case let .index(idx):
                guard let array = current as? [Any],
                      idx >= 0, idx < array.count
                else {
                    return nil
                }
                current = array[idx]
            }
        }

        return current
    }

    private enum JsonPathComponent {
        case key(String)
        case index(Int)
    }

    private func parseJsonPath(_ path: String) -> [JsonPathComponent] {
        var components: [JsonPathComponent] = []
        var currentKey = ""
        var i = path.startIndex

        while i < path.endIndex {
            let char = path[i]

            if char == "." {
                if !currentKey.isEmpty {
                    components.append(.key(currentKey))
                    currentKey = ""
                }
                i = path.index(after: i)
            } else if char == "[" {
                // Handle bracket notation: [0] or ["key"]
                if !currentKey.isEmpty {
                    components.append(.key(currentKey))
                    currentKey = ""
                }

                // Find closing bracket
                guard let closingBracket = path[i...].firstIndex(of: "]") else {
                    break
                }

                let bracketContent = path[path.index(after: i) ..< closingBracket]
                let content = String(bracketContent).trimmingCharacters(in: .whitespaces)

                // Check if it's an array index or string key
                if let index = Int(content) {
                    components.append(.index(index))
                } else {
                    // Remove quotes if present
                    let key = content.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    components.append(.key(key))
                }

                i = path.index(after: closingBracket)
            } else {
                currentKey.append(char)
                i = path.index(after: i)
            }
        }

        if !currentKey.isEmpty {
            components.append(.key(currentKey))
        }

        return components
    }

    @ViewBuilder
    private var pageBar: some View {
        let l10n = appState.l10n
        let pages = totalPages

        Divider()
        HStack(spacing: 8) {
            Button {
                currentPage = max(0, currentPage - 1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)
            .disabled(currentPage == 0)

            ForEach(0 ..< pages, id: \.self) { page in
                Button {
                    currentPage = page
                } label: {
                    Text("\(page + 1)")
                        .font(.caption)
                        .monospacedDigit()
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            page == currentPage
                                ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear),
                            in: RoundedRectangle(cornerRadius: 4),
                        )
                        .foregroundStyle(page == currentPage ? .white : .primary)
                }
                .buttonStyle(.plain)
            }

            Button {
                currentPage = min(pages - 1, currentPage + 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.plain)
            .disabled(currentPage >= pages - 1)

            Spacer()

            Text(l10n.t(
                "messages.page.info",
                String(displayedMessages.count),
                String(filteredMessages.count),
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Message Table

    @ViewBuilder
    private var messageTable: some View {
        @Bindable var state = appState
        let l10n = appState.l10n

        Table(displayedMessages, selection: Binding(
            get: { selectedMessageId },
            set: { newValue in
                selectedMessageId = newValue
                if let id = newValue, let msg = displayedMessages.first(where: { $0.id == id }) {
                    detailMessage = msg
                } else if newValue == nil {
                    detailMessage = nil
                }
            },
        ), sortOrder: $state.messagesSortOrder) {
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
                Text(message.keyString(format: messageFormat, protoContext: protoContext))
                    .lineLimit(1)
                    .padding(.vertical, appState.rowDensity.tablePadding)
            }
            .width(min: 60, ideal: 100, max: 150)

            TableColumn(l10n["messages.value"]) { message in
                Text(message.valueString(format: messageFormat, protoContext: protoContext))
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

    // MARK: - Detail Panel

    private func detailPanel(for message: KafkaMessageRecord) -> some View {
        HStack(spacing: 0) {
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

            MessageDetailView(message: message, format: messageFormat, protoContext: protoContext) {
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

    /// Schema context for protobuf decoding — nil when not configured
    private var protoContext: ProtobufContext? {
        guard messageFormat == .protobuf else { return nil }
        guard let fileID = selectedProtoFileID else { return nil }
        guard let schema = protoManager.schema(for: fileID) else { return nil }
        guard let messageType = selectedProtoMessageType else { return nil }
        return ProtobufContext(schema: schema, messageTypeName: messageType)
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

        // Cancel any in-flight fetch to prevent stale results
        fetchTask?.cancel()

        let partition = selectedPartition
        let limit = maxMessages
        let newest = newestFirst
        let parsedFrom = Int64(offsetFromText)
        let parsedTo = Int64(offsetToText)

        isFetching = true
        fetchError = nil

        fetchTask = Task {
            do {
                let newMessages = try await appState.fetchMessages(
                    topic: topicName,
                    partition: partition,
                    maxMessages: limit,
                    newestFirst: newest,
                    offsetFrom: parsedFrom,
                    offsetTo: parsedTo,
                )

                // Discard results if topic changed while we were fetching
                guard !Task.isCancelled, selectedTopicName == topicName else { return }

                // Reconcile selection
                if let id = selectedMessageId {
                    if let msg = newMessages.first(where: { $0.id == id }) {
                        detailMessage = msg
                    } else {
                        selectedMessageId = nil
                    }
                }

                messages = newMessages
                // Keep current page valid after refresh
                let pages = newMessages.isEmpty ? 0 : (newMessages.count + messagesPerPage - 1) / messagesPerPage
                if currentPage >= pages {
                    currentPage = max(0, pages - 1)
                }
            } catch is CancellationError {
                // Fetch was cancelled (e.g. topic changed)
            } catch {
                guard !Task.isCancelled, selectedTopicName == topicName else { return }
                fetchError = error.localizedDescription
            }
            if selectedTopicName == topicName {
                isFetching = false
            }
        }
    }

    // MARK: - Per-Topic Format Persistence

    private func loadFormatForTopic(_ topicName: String?) {
        guard let topicName else {
            // No topic selected, use default
            messageFormat = .utf8
            return
        }

        // Look up saved format for this topic
        if let config = deserializerConfigStore.config(for: topicName),
           let format = MessageFormat.allCases.first(where: { $0.deserializerID == config.valueDeserializerID })
        {
            messageFormat = format
        } else {
            // No saved config, use default
            messageFormat = .utf8
        }
    }

    private func saveFormatForTopic(_ format: MessageFormat) {
        guard let topicName = selectedTopicName else { return }

        // Save format for this topic
        let config = TopicDeserializerConfig(
            topicName: topicName,
            keyDeserializerID: format.deserializerID,
            valueDeserializerID: format.deserializerID,
        )
        deserializerConfigStore.setConfig(config)
    }
}

struct MessageDetailView: View {
    @Environment(AppState.self) private var appState
    let message: KafkaMessageRecord
    let format: MessageFormat
    var protoContext: ProtobufContext?
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
                        CopyButton(text: message.keyPrettyString(format: format, protoContext: protoContext), copied: $keyCopied)
                    }
                    codeBlock(message.keyPrettyString(format: format, protoContext: protoContext))

                    HStack {
                        Text(l10n["messages.value"])
                            .font(.subheadline.bold())
                        Spacer()
                        CopyButton(text: message.valuePrettyString(format: format, protoContext: protoContext), copied: $valueCopied)
                    }
                    codeBlock(message.valuePrettyString(format: format, protoContext: protoContext))

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
