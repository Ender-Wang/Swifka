import Foundation

@Observable
final class AppState {
    let configStore: ConfigStore
    let kafkaService: KafkaService
    let l10n: L10n
    let refreshManager: RefreshManager
    let metricStore: MetricStore
    let metricDatabase: MetricDatabase?

    var connectionStatus: ConnectionStatus = .disconnected
    var brokers: [BrokerInfo] = []
    var topics: [TopicInfo] = []
    var consumerGroups: [ConsumerGroupInfo] = []
    var consumerGroupLags: [String: Int64] = [:]
    var topicLags: [String: Int64] = [:]
    /// Per-partition lag breakdown for each consumer group (group name → partitions).
    var partitionLags: [String: [PartitionLag]] = [:]
    /// Per-partition lag aggregated across all groups (key = "topic:partition", value = lag).
    var partitionLagDetail: [String: Int64] = [:]
    var selectedSidebarItem: SidebarItem? = .dashboard {
        didSet {
            UserDefaults.standard.set(selectedSidebarItem?.rawValue, forKey: "nav.sidebarItem")
        }
    }

    var expandedTopics: Set<String> = []

    // MARK: - Trends (session-scoped)

    var trendsMode: TrendsMode = .live
    let historyState = HistoryState()
    var trendSelectedTopics: [String] = []
    var trendSelectedGroups: [String] = []
    /// Per-session override for chart time window. nil = use chartTimeWindow setting.
    var trendTimeWindow: ChartTimeWindow?

    // MARK: - Sort Orders (session-scoped, reset on app restart)

    var brokersSortOrder = [KeyPathComparator(\BrokerInfo.id)]
    var consumerGroupsSortOrder = [KeyPathComparator(\ConsumerGroupInfo.name)]
    var messagesSortOrder = [KeyPathComparator(\KafkaMessageRecord.offset)]
    var partitionsSortOrder = [KeyPathComparator(\PartitionInfo.partitionId)]
    var lastError: String?
    var isLoading = false
    var pingMs: Int?

    var operationLevel: OperationLevel = .readonly {
        didSet {
            UserDefaults.standard.set(operationLevel.rawValue, forKey: "settings.operationLevel")
        }
    }

    var defaultRefreshMode: RefreshMode = .manual {
        didSet {
            if let data = try? JSONEncoder().encode(defaultRefreshMode) {
                UserDefaults.standard.set(data, forKey: "settings.refreshMode")
            }
        }
    }

    var appearanceMode: AppearanceMode = .system {
        didSet {
            UserDefaults.standard.set(appearanceMode.rawValue, forKey: "settings.appearanceMode")
        }
    }

    var rowDensity: RowDensity = .regular {
        didSet {
            UserDefaults.standard.set(rowDensity.rawValue, forKey: "settings.rowDensity")
        }
    }

    var retentionPolicy: DataRetentionPolicy = .sevenDays {
        didSet {
            UserDefaults.standard.set(retentionPolicy.rawValue, forKey: "settings.retentionPolicy")
        }
    }

    var chartTimeWindow: ChartTimeWindow = .fiveMinutes {
        didSet {
            UserDefaults.standard.set(chartTimeWindow.rawValue, forKey: "settings.chartTimeWindow")
        }
    }

    /// Effective chart time window: session override if set, else persisted setting.
    var effectiveTimeWindow: ChartTimeWindow {
        trendTimeWindow ?? chartTimeWindow
    }

    init(
        configStore: ConfigStore = ConfigStore(),
        kafkaService: KafkaService = KafkaService(),
        l10n: L10n = .shared,
        refreshManager: RefreshManager = RefreshManager(),
        metricStore: MetricStore = MetricStore(),
        metricDatabase: MetricDatabase? = nil,
    ) {
        self.configStore = configStore
        self.kafkaService = kafkaService
        self.l10n = l10n
        self.refreshManager = refreshManager
        self.metricStore = metricStore
        self.metricDatabase = metricDatabase ?? (try? MetricDatabase())

        // Restore persisted settings
        if let raw = UserDefaults.standard.string(forKey: "settings.operationLevel"),
           let level = OperationLevel(rawValue: raw)
        {
            operationLevel = level
        }
        if let data = UserDefaults.standard.data(forKey: "settings.refreshMode"),
           let mode = try? JSONDecoder().decode(RefreshMode.self, from: data)
        {
            defaultRefreshMode = mode
            refreshManager.updateMode(mode)
        }
        if let raw = UserDefaults.standard.string(forKey: "settings.appearanceMode"),
           let mode = AppearanceMode(rawValue: raw)
        {
            appearanceMode = mode
        }
        if let raw = UserDefaults.standard.string(forKey: "settings.rowDensity"),
           let density = RowDensity(rawValue: raw)
        {
            rowDensity = density
        }
        if let raw = UserDefaults.standard.string(forKey: "settings.retentionPolicy"),
           let policy = DataRetentionPolicy(rawValue: raw)
        {
            retentionPolicy = policy
        }
        if let raw = UserDefaults.standard.string(forKey: "settings.chartTimeWindow"),
           let window = ChartTimeWindow(rawValue: raw)
        {
            chartTimeWindow = window
        }
        if let raw = UserDefaults.standard.string(forKey: "nav.sidebarItem"),
           let item = SidebarItem(rawValue: raw)
        {
            selectedSidebarItem = item
        }

        self.refreshManager.onRefresh = { [weak self] in
            await self?.refreshAll()
        }

        // Prune old metrics on launch
        Task { [weak self] in
            await self?.pruneMetrics()
        }
    }

    // MARK: - Connection

    func connect() async {
        guard let cluster = configStore.selectedCluster else { return }
        connectionStatus = .connecting
        lastError = nil

        do {
            let password = cluster.authType == .sasl
                ? KeychainManager.loadPassword(for: cluster.id)
                : nil
            try await kafkaService.connect(config: cluster, password: password)
            connectionStatus = .connected
            await loadHistoricalMetrics(for: cluster.id)
            await refreshAll()
            refreshManager.restart()
        } catch {
            connectionStatus = .error(error.localizedDescription)
            lastError = error.localizedDescription
        }
    }

    func disconnect() async {
        refreshManager.stop()
        connectionStatus = .disconnected
        isLoading = false
        pingMs = nil
        brokers = []
        topics = []
        consumerGroups = []
        consumerGroupLags = [:]
        topicLags = [:]
        partitionLags = [:]
        partitionLagDetail = [:]
        expandedTopics = []
        trendsMode = .live
        historyState.store.clear()
        metricStore.clear()
        await kafkaService.disconnect()
        await pruneMetrics()
    }

    func testConnection(config: ClusterConfig, password: String?) async -> Result<Bool, Error> {
        do {
            let result = try await kafkaService.testConnection(config: config, password: password)
            return .success(result)
        } catch {
            return .failure(error)
        }
    }

    func ping() async -> Int? {
        guard connectionStatus.isConnected else { return nil }
        return try? await kafkaService.ping()
    }

    // MARK: - Data Fetching

    func refreshAll() async {
        guard connectionStatus.isConnected else { return }
        isLoading = true
        let start = ContinuousClock.now

        do {
            let metadata = try await kafkaService.fetchMetadata()
            guard connectionStatus.isConnected else { isLoading = false; return }
            brokers = metadata.brokers
            topics = await kafkaService.fetchAllWatermarks(topics: metadata.topics)
            guard connectionStatus.isConnected else { isLoading = false; return }
            let currentNames = Set(topics.map(\.name))
            expandedTopics.formIntersection(currentNames)
        } catch {
            guard connectionStatus.isConnected else { isLoading = false; return }
            connectionStatus = .error(error.localizedDescription)
            lastError = error.localizedDescription
        }

        do {
            consumerGroups = try await kafkaService.fetchConsumerGroups()
        } catch {
            guard connectionStatus.isConnected else { isLoading = false; return }
            // Consumer groups might not be available; don't block on this
            print("Failed to fetch consumer groups: \(error)")
        }

        // Fetch committed offsets and compute lag per consumer group
        await fetchConsumerGroupLags()

        recordMetricSnapshot()

        // Ensure spinner is visible long enough to avoid flickering
        let elapsed = ContinuousClock.now - start
        if elapsed < .milliseconds(500) {
            try? await Task.sleep(for: .milliseconds(500) - elapsed)
        }
        isLoading = false
    }

    func fetchMessages(
        topic: String,
        partition: Int32?,
        maxMessages: Int,
        newestFirst: Bool = true,
        offsetFrom: Int64? = nil,
        offsetTo: Int64? = nil,
    ) async throws -> [KafkaMessageRecord] {
        guard let cluster = configStore.selectedCluster else {
            throw SwifkaError.notConnected
        }
        let password = cluster.authType == .sasl
            ? KeychainManager.loadPassword(for: cluster.id)
            : nil
        return try await kafkaService.browseMessages(
            config: cluster,
            topic: topic,
            partition: partition,
            maxMessages: maxMessages,
            newestFirst: newestFirst,
            offsetFrom: offsetFrom,
            offsetTo: offsetTo,
            password: password,
        )
    }

    // MARK: - Consumer Group Lag

    private func fetchConsumerGroupLags() async {
        guard connectionStatus.isConnected, !consumerGroups.isEmpty else {
            consumerGroupLags = [:]
            return
        }

        let allPartitions: [(topic: String, partition: Int32)] = topics
            .filter { !$0.isInternal }
            .flatMap { topic in
                topic.partitions.map { (topic: topic.name, partition: $0.partitionId) }
            }
        guard !allPartitions.isEmpty else {
            consumerGroupLags = [:]
            return
        }

        var lags: [String: Int64] = [:]
        var allTopicLags: [String: Int64] = [:]
        var allPartitionLags: [String: [PartitionLag]] = [:]
        var allPartitionLagDetail: [String: Int64] = [:]
        for group in consumerGroups {
            guard connectionStatus.isConnected else { break }
            guard let offsets = try? await kafkaService.fetchCommittedOffsets(
                group: group.name, partitions: allPartitions,
            ) else { continue }

            var groupLag: Int64 = 0
            var groupPartitions: [PartitionLag] = []
            for (topic, partition, committedOffset) in offsets {
                if let topicInfo = topics.first(where: { $0.name == topic }),
                   let partInfo = topicInfo.partitions.first(where: { $0.partitionId == partition }),
                   let highWatermark = partInfo.highWatermark
                {
                    let lag = max(0, highWatermark - committedOffset)
                    groupLag += lag
                    allTopicLags[topic, default: 0] += lag
                    allPartitionLagDetail["\(topic):\(partition)", default: 0] += lag
                    groupPartitions.append(PartitionLag(
                        topic: topic,
                        partition: partition,
                        committedOffset: committedOffset,
                        highWatermark: highWatermark,
                        lag: lag,
                    ))
                }
            }
            lags[group.name] = groupLag
            allPartitionLags[group.name] = groupPartitions
        }
        consumerGroupLags = lags
        topicLags = allTopicLags
        partitionLags = allPartitionLags
        partitionLagDetail = allPartitionLagDetail
    }

    // MARK: - Metrics

    private func recordMetricSnapshot() {
        var topicWatermarks: [String: Int64] = [:]
        var underReplicated = 0
        var totalPartitionCount = 0
        for topic in topics where !topic.isInternal {
            var total: Int64 = 0
            for partition in topic.partitions {
                total += partition.highWatermark ?? 0
                totalPartitionCount += 1
                if partition.isr.count < partition.replicas.count {
                    underReplicated += 1
                }
            }
            topicWatermarks[topic.name] = total
        }

        let granularity: TimeInterval = if case let .interval(seconds) = refreshManager.mode {
            TimeInterval(seconds)
        } else {
            0
        }

        let snapshot = MetricSnapshot(
            id: UUID(),
            timestamp: Date(),
            granularity: granularity,
            topicWatermarks: topicWatermarks,
            consumerGroupLags: consumerGroupLags,
            topicLags: topicLags,
            partitionLagDetail: partitionLagDetail,
            totalHighWatermark: topicWatermarks.values.reduce(0, +),
            totalLag: consumerGroupLags.values.reduce(0, +),
            underReplicatedPartitions: underReplicated,
            totalPartitions: totalPartitionCount,
            brokerCount: brokers.count,
            pingMs: pingMs,
        )
        metricStore.record(snapshot)

        // Persist to SQLite (fire-and-forget)
        if let db = metricDatabase, let clusterId = configStore.selectedCluster?.id {
            Task {
                try? await db.insert(snapshot, clusterId: clusterId)
            }
        }
    }

    private func loadHistoricalMetrics(for clusterId: UUID) async {
        guard let db = metricDatabase else { return }
        do {
            let historical = try await db.loadRecentSnapshots(clusterId: clusterId)
            if !historical.isEmpty {
                metricStore.loadHistorical(historical)
            }
        } catch {
            print("Failed to load historical metrics: \(error)")
        }
    }

    func clearAllMetricData() async {
        metricStore.clear()
        guard let db = metricDatabase else { return }
        do {
            let deleted = try await db.deleteAllData()
            print("Cleared \(deleted) metric snapshots")
        } catch {
            print("Failed to clear metric data: \(error)")
        }
    }

    private func pruneMetrics() async {
        guard let db = metricDatabase else { return }
        do {
            let deleted = try await db.pruneAllClusters(retentionPolicy: retentionPolicy)
            if deleted > 0 {
                print("Pruned \(deleted) old metric snapshots")
            }
        } catch {
            print("Failed to prune metrics: \(error)")
        }
    }

    // MARK: - Status

    var statusText: String {
        guard let cluster = configStore.selectedCluster else {
            return l10n["status.disconnected"]
        }
        switch connectionStatus {
        case .connected:
            let userTopics = topics.filter { !$0.isInternal }
            let b = brokers.count
            let t = userTopics.count
            let p = userTopics.reduce(0) { $0 + $1.partitionCount }
            return l10n.t(
                "status.connected",
                cluster.bootstrapServers,
                "\(b)", l10n[b == 1 ? "status.broker" : "status.brokers"],
                "\(t)", l10n[t == 1 ? "status.topic" : "status.topics"],
                "\(p)", l10n[p == 1 ? "status.partition" : "status.partitions"],
            )
        case .connecting:
            return l10n["status.connecting"]
        case .disconnected, .error:
            return l10n["status.disconnected"]
        }
    }

    var totalPartitions: Int {
        topics.filter { !$0.isInternal }.reduce(0) { $0 + $1.partitionCount }
    }
}
