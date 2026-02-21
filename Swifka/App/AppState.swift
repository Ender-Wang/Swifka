import Foundation
import OSLog
import UserNotifications

@Observable
final class AppState {
    let configStore: ConfigStore
    let kafkaService: KafkaService
    let l10n: L10n
    let refreshManager: RefreshManager
    let metricStore: MetricStore
    let metricDatabase: MetricDatabase?

    /// Schema Registry client, created on connect if cluster has a registry URL.
    var schemaRegistryClient: SchemaRegistryClient?

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

    // MARK: - Keyboard Navigation

    /// Bumped to a new UUID each time Cmd+F is pressed. Views observe this to focus their search field.
    var focusSearchTrigger = UUID()

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
                activeAlerts.removeAll { $0.type == .isr }

                previousAlertTypes.remove(AlertRuleType.isr.rawValue)
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

    // MARK: - Alert Rules Settings

    var clusterLagAlertEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(clusterLagAlertEnabled, forKey: "settings.alerts.clusterLag.enabled")
        }
    }

    var clusterLagThreshold: Int = 10000 {
        didSet {
            UserDefaults.standard.set(clusterLagThreshold, forKey: "settings.alerts.clusterLag.threshold")
        }
    }

    var highLatencyAlertEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(highLatencyAlertEnabled, forKey: "settings.alerts.highLatency.enabled")
        }
    }

    var highLatencyThreshold: Int = 500 {
        didSet {
            UserDefaults.standard.set(highLatencyThreshold, forKey: "settings.alerts.highLatency.threshold")
        }
    }

    var brokerOfflineAlertEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(brokerOfflineAlertEnabled, forKey: "settings.alerts.brokerOffline.enabled")
        }
    }

    var expectedBrokerCount: Int = 3 {
        didSet {
            UserDefaults.standard.set(expectedBrokerCount, forKey: "settings.alerts.brokerOffline.expected")
        }
    }

    // MARK: - Alerts (session-scoped)

    var activeAlerts: [AlertRecord] = []

    @ObservationIgnored
    private var previousAlertTypes: Set<String> = []

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
        if let data = UserDefaults.standard.data(forKey: "settings.refreshMode"),
           let mode = try? JSONDecoder().decode(RefreshMode.self, from: data)
        {
            defaultRefreshMode = mode
            // Only remember the mode — don't start the timer.
            // Timer starts on successful connect() via refreshManager.restart().
            refreshManager.mode = mode
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
        // Alert rule settings
        if UserDefaults.standard.object(forKey: "settings.alerts.clusterLag.enabled") != nil {
            clusterLagAlertEnabled = UserDefaults.standard.bool(forKey: "settings.alerts.clusterLag.enabled")
        }
        let storedLagThreshold = UserDefaults.standard.integer(forKey: "settings.alerts.clusterLag.threshold")
        if storedLagThreshold > 0 { clusterLagThreshold = storedLagThreshold }
        if UserDefaults.standard.object(forKey: "settings.alerts.highLatency.enabled") != nil {
            highLatencyAlertEnabled = UserDefaults.standard.bool(forKey: "settings.alerts.highLatency.enabled")
        }
        let storedLatencyThreshold = UserDefaults.standard.integer(forKey: "settings.alerts.highLatency.threshold")
        if storedLatencyThreshold > 0 { highLatencyThreshold = storedLatencyThreshold }
        if UserDefaults.standard.object(forKey: "settings.alerts.brokerOffline.enabled") != nil {
            brokerOfflineAlertEnabled = UserDefaults.standard.bool(forKey: "settings.alerts.brokerOffline.enabled")
        }
        let storedBrokerCount = UserDefaults.standard.integer(forKey: "settings.alerts.brokerOffline.expected")
        if storedBrokerCount > 0 { expectedBrokerCount = storedBrokerCount }

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
            Log.app.info("[AppState] connect: established to \(cluster.bootstrapServers, privacy: .public)")

            // Create Schema Registry client if configured
            if let registryURL = cluster.schemaRegistryURL,
               let url = URL(string: registryURL)
            {
                schemaRegistryClient = SchemaRegistryClient(baseURL: url)
                Log.app.info("[AppState] connect: schema registry at \(registryURL, privacy: .public)")
            }

            // Don't update lastConnectedAt here - only update on disconnect
            await loadHistoricalMetrics(for: cluster.id)
            await refreshAll()
            refreshManager.restart()
        } catch {
            connectionStatus = .error(error.localizedDescription)
            lastError = error.localizedDescription
            Log.app.error("[AppState] connect: failed — \(error.localizedDescription, privacy: .public)")
        }
    }

    func disconnect() async {
        Log.app.info("[AppState] disconnect: tearing down connection")
        // Update lastConnectedAt timestamp if we were connected
        if connectionStatus.isConnected, let clusterId = configStore.selectedClusterId {
            configStore.updateLastConnected(for: clusterId)
        }

        refreshManager.stop()
        connectionStatus = .disconnected
        isLoading = false
        pingMs = nil
        schemaRegistryClient = nil
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
        activeAlerts = []
        previousAlertTypes = []
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
            Log.app.debug("[AppState] refresh: \(metadata.brokers.count) brokers, \(metadata.topics.count) topics")
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
                let errCount = consecutiveRefreshErrors
                Log.app.error("[AppState] refresh: circuit breaker tripped after \(errCount) failures")
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
            Log.app.error("[AppState] refresh: consumer groups failed — \(error.localizedDescription, privacy: .public)")
        }

        // Fetch committed offsets and compute lag per consumer group
        await fetchConsumerGroupLags()

        recordMetricSnapshot()
        checkAlertRules()

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

    // MARK: - Unified Alert Checks

    private func checkAlertRules() {
        guard connectionStatus.isConnected else {
            activeAlerts = []
            previousAlertTypes = []
            return
        }

        var alerts: [AlertRecord] = []

        // --- ISR Alert ---
        if isrAlertsEnabled {
            if let record = checkISRAlert() {
                alerts.append(record)
            }
        }

        // --- Cluster Lag Alert ---
        if clusterLagAlertEnabled {
            let totalLag = consumerGroupLags.values.reduce(0, +)
            if totalLag > Int64(clusterLagThreshold) {
                let severity: AlertSeverity = totalLag > Int64(clusterLagThreshold) * 2 ? .critical : .warning
                alerts.append(AlertRecord(
                    id: UUID(),
                    type: .clusterLag,
                    severity: severity,
                    timestamp: Date(),
                    title: l10n["alert.clusterLag.title"],
                    summary: l10n.t("alert.clusterLag.summary",
                                    formatLagNumber(totalLag),
                                    formatLagNumber(Int64(clusterLagThreshold))),
                ))
            }
        }

        // --- High Latency Alert ---
        if highLatencyAlertEnabled, let ping = pingMs, ping > highLatencyThreshold {
            let severity: AlertSeverity = ping > highLatencyThreshold * 2 ? .critical : .warning
            alerts.append(AlertRecord(
                id: UUID(),
                type: .highLatency,
                severity: severity,
                timestamp: Date(),
                title: l10n["alert.highLatency.title"],
                summary: l10n.t("alert.highLatency.summary", "\(ping)", "\(highLatencyThreshold)"),
            ))
        }

        // --- Broker Offline Alert ---
        if brokerOfflineAlertEnabled, brokers.count < expectedBrokerCount {
            alerts.append(AlertRecord(
                id: UUID(),
                type: .brokerOffline,
                severity: .critical,
                timestamp: Date(),
                title: l10n["alert.brokerOffline.title"],
                summary: l10n.t("alert.brokerOffline.summary", "\(brokers.count)", "\(expectedBrokerCount)"),
            ))
        }

        // Detect newly triggered alert types
        let currentTypes = Set(alerts.map(\.type.rawValue))
        let newlyTriggered = currentTypes.subtracting(previousAlertTypes)

        // Persist resolution for types that just resolved
        let resolvedTypes = previousAlertTypes.subtracting(currentTypes)
        for typeRaw in resolvedTypes {
            Log.alerts.info("[AppState] alerts: \(typeRaw, privacy: .public) resolved")
            persistAlertResolution(typeRaw)
        }

        // Send notifications and persist for newly triggered alerts
        for alert in alerts where newlyTriggered.contains(alert.type.rawValue) {
            Log.alerts.info("[AppState] alerts: \(alert.type.rawValue, privacy: .public) triggered — \(alert.severity == .critical ? "CRITICAL" : "warning", privacy: .public)")
            sendAlertNotification(alert)
            persistAlertRecord(alert)
        }

        activeAlerts = alerts
        previousAlertTypes = currentTypes
    }

    /// ISR-specific check logic — returns an AlertRecord if under-replicated partitions found.
    private func checkISRAlert() -> AlertRecord? {
        // Redpanda (Raft-based) may not shrink ISR when a broker goes down —
        // it keeps reporting the dead broker in the ISR list. Cross-reference
        // ISR broker IDs against alive brokers from the metadata response.
        let aliveBrokerIds = Set(brokers.map(\.id))

        var underReplicatedCount = 0
        var criticalCount = 0
        var belowMinCount = 0
        var totalPartitionCount = 0

        for topic in topics where !topic.isInternal {
            for partition in topic.partitions {
                totalPartitionCount += 1
                let replicaCount = partition.replicas.count
                let effectiveISRCount = partition.isr.count(where: { aliveBrokerIds.contains($0) })

                guard effectiveISRCount < replicaCount else { continue }
                underReplicatedCount += 1

                if effectiveISRCount < minInsyncReplicas {
                    belowMinCount += 1
                } else if effectiveISRCount == 1 {
                    criticalCount += 1
                }
            }
        }

        guard underReplicatedCount > 0 else { return nil }

        let severity: AlertSeverity
        let title: String
        let summary: String

        if belowMinCount > 0 {
            severity = .critical
            title = l10n["alert.isr.severity.danger"]
            summary = l10n.t("alert.isr.summary.danger", "\(belowMinCount)", "\(totalPartitionCount)")
        } else if criticalCount > 0 {
            severity = .critical
            title = l10n["alert.isr.severity.critical"]
            summary = l10n.t("alert.isr.summary.critical", "\(criticalCount)", "\(totalPartitionCount)")
        } else {
            severity = .warning
            title = l10n["alert.isr.severity.warning"]
            summary = l10n.t("alert.isr.summary.warning", "\(underReplicatedCount)", "\(totalPartitionCount)")
        }

        return AlertRecord(
            id: UUID(),
            type: .isr,
            severity: severity,
            timestamp: Date(),
            title: title,
            summary: summary,
        )
    }

    private func formatLagNumber(_ lag: Int64) -> String {
        if lag >= 1_000_000 {
            return String(format: "%.1fM", Double(lag) / 1_000_000)
        } else if lag >= 1000 {
            return String(format: "%.1fK", Double(lag) / 1000)
        }
        return "\(lag)"
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

    private func sendAlertNotification(_ alert: AlertRecord) {
        guard desktopNotificationsEnabled, notificationPermissionGranted else { return }

        let content = UNMutableNotificationContent()
        content.title = "Swifka — \(alert.title)"
        content.body = alert.summary
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "alert-\(alert.type.rawValue)",
            content: content,
            trigger: nil,
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func persistAlertRecord(_ alert: AlertRecord) {
        guard let db = metricDatabase, let clusterId = configStore.selectedCluster?.id else { return }
        Task {
            try? await db.insertAlert(alert, clusterId: clusterId)
        }
    }

    private func persistAlertResolution(_ typeRaw: String) {
        guard let db = metricDatabase, let clusterId = configStore.selectedCluster?.id else { return }
        Task {
            try? await db.resolveAlerts(type: typeRaw, clusterId: clusterId)
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
            Log.storage.error("[AppState] loadHistorical: failed — \(error.localizedDescription, privacy: .public)")
        }
    }

    func clearAllMetricData() async {
        metricStore.clear()
        guard let db = metricDatabase else { return }
        do {
            let deleted = try await db.deleteAllData()
            let deletedAlerts = try await db.deleteAllAlerts()
            Log.storage.info("[AppState] clearMetrics: \(deleted) snapshots, \(deletedAlerts) alert records")
        } catch {
            Log.storage.error("[AppState] clearMetrics: failed — \(error.localizedDescription, privacy: .public)")
        }
    }

    private func pruneMetrics() async {
        guard let db = metricDatabase else { return }
        do {
            let deleted = try await db.pruneAllClusters(retentionPolicy: retentionPolicy)
            let deletedAlerts = try await db.pruneAlerts(retentionPolicy: retentionPolicy)
            if deleted > 0 || deletedAlerts > 0 {
                Log.storage.info("[AppState] pruneMetrics: \(deleted) snapshots, \(deletedAlerts) alerts")
            }
        } catch {
            Log.storage.error("[AppState] pruneMetrics: failed — \(error.localizedDescription, privacy: .public)")
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
