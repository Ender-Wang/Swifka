import Foundation

@Observable
final class AppState {
    let configStore: ConfigStore
    let kafkaService: KafkaService
    let l10n: L10n
    let refreshManager: RefreshManager

    var connectionStatus: ConnectionStatus = .disconnected
    var brokers: [BrokerInfo] = []
    var topics: [TopicInfo] = []
    var consumerGroups: [ConsumerGroupInfo] = []
    var selectedSidebarItem: SidebarItem? = .dashboard {
        didSet {
            UserDefaults.standard.set(selectedSidebarItem?.rawValue, forKey: "nav.sidebarItem")
        }
    }

    var expandedTopics: Set<String> = []
    var lastError: String?
    var isLoading = false

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

    init(
        configStore: ConfigStore = ConfigStore(),
        kafkaService: KafkaService = KafkaService(),
        l10n: L10n = .shared,
        refreshManager: RefreshManager = RefreshManager(),
    ) {
        self.configStore = configStore
        self.kafkaService = kafkaService
        self.l10n = l10n
        self.refreshManager = refreshManager

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
        if let raw = UserDefaults.standard.string(forKey: "nav.sidebarItem"),
           let item = SidebarItem(rawValue: raw)
        {
            selectedSidebarItem = item
        }

        self.refreshManager.onRefresh = { [weak self] in
            await self?.refreshAll()
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
            await refreshAll()
        } catch {
            connectionStatus = .error(error.localizedDescription)
            lastError = error.localizedDescription
        }
    }

    func disconnect() async {
        await kafkaService.disconnect()
        connectionStatus = .disconnected
        brokers = []
        topics = []
        consumerGroups = []
        expandedTopics = []
    }

    func testConnection(config: ClusterConfig, password: String?) async -> Result<Bool, Error> {
        do {
            let result = try await kafkaService.testConnection(config: config, password: password)
            return .success(result)
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Data Fetching

    func refreshAll() async {
        guard connectionStatus.isConnected else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let metadata = try await kafkaService.fetchMetadata()
            brokers = metadata.brokers
            topics = await kafkaService.fetchAllWatermarks(topics: metadata.topics)
            let currentNames = Set(topics.map(\.name))
            expandedTopics.formIntersection(currentNames)
        } catch {
            lastError = error.localizedDescription
        }

        do {
            consumerGroups = try await kafkaService.fetchConsumerGroups()
        } catch {
            // Consumer groups might not be available; don't block on this
            print("Failed to fetch consumer groups: \(error)")
        }
    }

    func fetchMessages(
        topic: String,
        partition: Int32?,
        maxMessages: Int,
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
            password: password,
        )
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
