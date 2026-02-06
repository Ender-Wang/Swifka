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
    var selectedSidebarItem: SidebarItem? = .dashboard
    var lastError: String?
    var isLoading = false

    var operationLevel: OperationLevel = .readonly
    var defaultRefreshMode: RefreshMode = .manual

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
            return l10n.t(
                "status.connected",
                cluster.bootstrapServers,
                "\(topics.count(where: { !$0.isInternal }))",
            )
        case .connecting:
            return l10n["status.connecting"]
        case .disconnected, .error:
            return l10n["status.disconnected"]
        }
    }

    var totalPartitions: Int {
        topics.reduce(0) { $0 + $1.partitionCount }
    }
}
