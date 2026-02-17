import Foundation
import UserNotifications

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

    /// Broker statistics derived from partition metadata (leader count, replica count).
    var brokerStats: [BrokerStats] {
        var leaderCounts: [Int32: Int] = [:]
        var replicaCounts: [Int32: Int] = [:]

        for topic in topics where !topic.isInternal {
            for partition in topic.partitions {
                leaderCounts[partition.leader, default: 0] += 1
                for replica in partition.replicas {
                    replicaCounts[replica, default: 0] += 1
                }
            }
        }

        return brokers.map { broker in
            BrokerStats(
                id: broker.id,
                host: broker.host,
                port: broker.port,
                leaderCount: leaderCounts[broker.id] ?? 0,
                replicaCount: replicaCounts[broker.id] ?? 0,
            )
        }.sorted { $0.id < $1.id }
    }

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

    // MARK: - Lag page (session-scoped)

    var lagMode: TrendsMode = .live
    let lagHistoryState = HistoryState()
    var lagSelectedTopics: [String] = []
    var lagSelectedGroups: [String] = []
    /// Per-session override for lag chart time window. nil = use chartTimeWindow setting.
    var lagTimeWindow: ChartTimeWindow?

    /// Effective lag chart time window: session override if set, else persisted setting.
    var effectiveLagTimeWindow: ChartTimeWindow {
        lagTimeWindow ?? chartTimeWindow
    }

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

    var isrAlertsEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isrAlertsEnabled, forKey: "settings.isrAlerts.enabled")
            if !isrAlertsEnabled {
                activeISRAlertState = nil
                isrAlertDismissed = false
                previousISRSeverity = nil
            }
        }
    }

    var minInsyncReplicas: Int = 2 {
        didSet {
            UserDefaults.standard.set(minInsyncReplicas, forKey: "settings.isrAlerts.minISR")
        }
    }

    var desktopNotificationsEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(desktopNotificationsEnabled, forKey: "settings.desktopNotifications.enabled")
            if desktopNotificationsEnabled {
                requestNotificationPermission()
            }
        }
    }

    /// Tracks the notification permission state for display in Settings.
    var notificationPermissionGranted: Bool = false

    // MARK: - ISR Alerts (session-scoped)

    /// Active ISR alert state, nil when all partitions are healthy.
    var activeISRAlertState: ISRAlertState?

    /// Whether the user has manually dismissed the current alert.
    var isrAlertDismissed: Bool = false

    @ObservationIgnored
    private var previousISRSeverity: ISRAlertSeverity?

    /// Prevents overlapping refreshAll() calls (e.g. timer fires while previous refresh still blocking).
    @ObservationIgnored
    private var isRefreshing = false

    /// Consecutive refresh failures — stops auto-refresh after 3 to avoid crashing librdkafka.
    @ObservationIgnored
    private var consecutiveRefreshErrors = 0

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
        if UserDefaults.standard.object(forKey: "settings.isrAlerts.enabled") != nil {
            isrAlertsEnabled = UserDefaults.standard.bool(forKey: "settings.isrAlerts.enabled")
        }
        let storedMinISR = UserDefaults.standard.integer(forKey: "settings.isrAlerts.minISR")
        if storedMinISR > 0 {
            minInsyncReplicas = storedMinISR
        }
        if UserDefaults.standard.object(forKey: "settings.desktopNotifications.enabled") != nil {
            desktopNotificationsEnabled = UserDefaults.standard.bool(forKey: "settings.desktopNotifications.enabled")
        }
        checkNotificationPermission()
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
            // Don't update lastConnectedAt here - only update on disconnect
            await loadHistoricalMetrics(for: cluster.id)
            await refreshAll()
            refreshManager.restart()
        } catch {
            connectionStatus = .error(error.localizedDescription)
            lastError = error.localizedDescription
        }
    }

    func disconnect() async {
        // Update lastConnectedAt timestamp if we were connected
        if connectionStatus.isConnected, let clusterId = configStore.selectedClusterId {
            configStore.updateLastConnected(for: clusterId)
        }

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
        lagMode = .live
        activeISRAlertState = nil
        isrAlertDismissed = false
        previousISRSeverity = nil
        consecutiveRefreshErrors = 0
        historyState.store.clear()
        lagHistoryState.store.clear()
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
        guard connectionStatus.isConnected, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        isLoading = true
        let start = ContinuousClock.now
        var metadataFailed = false

        do {
            let metadata = try await kafkaService.fetchMetadata()
            guard connectionStatus.isConnected else { isLoading = false; return }
            brokers = metadata.brokers
            topics = await kafkaService.fetchAllWatermarks(topics: metadata.topics)
            guard connectionStatus.isConnected else { isLoading = false; return }
            let currentNames = Set(topics.map(\.name))
            expandedTopics.formIntersection(currentNames)
            consecutiveRefreshErrors = 0
        } catch {
            guard connectionStatus.isConnected else { isLoading = false; return }
            metadataFailed = true
            consecutiveRefreshErrors += 1
            lastError = error.localizedDescription

            // Circuit breaker: stop auto-refresh after 3 consecutive failures
            // to avoid hammering librdkafka while brokers are down
            if consecutiveRefreshErrors >= 3 {
                // Update lastConnectedAt since connection is failing
                if let clusterId = configStore.selectedClusterId {
                    configStore.updateLastConnected(for: clusterId)
                }
                refreshManager.stop()
                connectionStatus = .error(error.localizedDescription)
                isLoading = false
                return
            }
        }

        // Skip downstream calls if metadata fetch failed — no fresh data to work with
        guard !metadataFailed else {
            isLoading = false
            return
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
        checkISRHealth()

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
        let aliveBrokerIds = Set(brokers.map(\.id))
        for topic in topics where !topic.isInternal {
            var total: Int64 = 0
            for partition in topic.partitions {
                total += partition.highWatermark ?? 0
                totalPartitionCount += 1
                let effectiveISR = partition.isr.count(where: { aliveBrokerIds.contains($0) })
                if effectiveISR < partition.replicas.count {
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

    private func checkISRHealth() {
        guard isrAlertsEnabled, connectionStatus.isConnected else {
            activeISRAlertState = nil
            previousISRSeverity = nil
            return
        }

        var details: [ISRAlertDetail] = []
        var totalPartitionCount = 0

        // Redpanda (Raft-based) may not shrink ISR when a broker goes down —
        // it keeps reporting the dead broker in the ISR list. Cross-reference
        // ISR broker IDs against alive brokers from the metadata response.
        let aliveBrokerIds = Set(brokers.map(\.id))

        for topic in topics where !topic.isInternal {
            for partition in topic.partitions {
                totalPartitionCount += 1
                let replicaCount = partition.replicas.count

                // Effective ISR = reported ISR filtered to only alive brokers
                let effectiveISRCount = partition.isr.count(where: { aliveBrokerIds.contains($0) })

                guard effectiveISRCount < replicaCount else { continue }

                let severity: ISRAlertSeverity = if effectiveISRCount < minInsyncReplicas {
                    .danger
                } else if effectiveISRCount == 1 {
                    .critical
                } else {
                    .warning
                }

                details.append(ISRAlertDetail(
                    topic: topic.name,
                    partition: partition.partitionId,
                    isrCount: effectiveISRCount,
                    replicaCount: replicaCount,
                    severity: severity,
                ))
            }
        }

        if details.isEmpty {
            if activeISRAlertState != nil {
                activeISRAlertState = nil
                isrAlertDismissed = false
            }
            previousISRSeverity = nil
            return
        }

        let maxSeverity = details.map(\.severity).max() ?? .warning
        let criticalCount = details.count(where: { $0.severity == .critical })
        let belowMinCount = details.count(where: { $0.severity == .danger })

        let newState = ISRAlertState(
            severity: maxSeverity,
            timestamp: Date(),
            affectedPartitions: details,
            totalPartitions: totalPartitionCount,
            underReplicatedCount: details.count,
            criticalCount: criticalCount,
            belowMinISRCount: belowMinCount,
        )

        // Reset dismiss flag and send notification when severity escalates or affected partitions change
        let isNewOrEscalated = maxSeverity != previousISRSeverity
            || activeISRAlertState?.affectedPartitions != newState.affectedPartitions

        if isNewOrEscalated {
            isrAlertDismissed = false
            sendISRNotification(state: newState)
        }

        activeISRAlertState = newState
        previousISRSeverity = maxSeverity
    }

    // MARK: - Desktop Notifications

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            Task { @MainActor in
                self.notificationPermissionGranted = granted
            }
        }
    }

    private func checkNotificationPermission() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            Task { @MainActor in
                self.notificationPermissionGranted = settings.authorizationStatus == .authorized
            }
        }
    }

    private func sendISRNotification(state: ISRAlertState) {
        guard desktopNotificationsEnabled, notificationPermissionGranted else { return }

        let content = UNMutableNotificationContent()

        let severityLabel: String
        let summary: String
        switch state.severity {
        case .warning:
            severityLabel = l10n["alert.isr.severity.warning"]
            summary = l10n.t("alert.isr.summary.warning", "\(state.underReplicatedCount)", "\(state.totalPartitions)")
        case .critical:
            severityLabel = l10n["alert.isr.severity.critical"]
            summary = l10n.t("alert.isr.summary.critical", "\(state.criticalCount)", "\(state.totalPartitions)")
        case .danger:
            severityLabel = l10n["alert.isr.severity.danger"]
            summary = l10n.t("alert.isr.summary.danger", "\(state.belowMinISRCount)", "\(state.totalPartitions)")
        }

        content.title = "Swifka — \(severityLabel)"
        content.body = summary
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "isr-alert",
            content: content,
            trigger: nil,
        )
        UNUserNotificationCenter.current().add(request)
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
