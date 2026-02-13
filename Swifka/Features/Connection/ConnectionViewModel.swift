import Foundation

@Observable
final class ConnectionViewModel {
    var showingAddSheet = false
    var showingEditSheet = false
    var editingCluster: ClusterConfig?

    var testResult: TestResult?
    var isTesting = false

    enum TestResult {
        case success
        case failure(String)
    }

    func addCluster(_ cluster: ClusterConfig, password: String?, to appState: AppState) {
        appState.configStore.addCluster(cluster)
        if let password, cluster.authType == .sasl {
            try? KeychainManager.save(password: password, for: cluster.id)
        }
    }

    func updateCluster(_ cluster: ClusterConfig, password: String?, in appState: AppState) {
        appState.configStore.updateCluster(cluster)
        if let password, cluster.authType == .sasl {
            try? KeychainManager.save(password: password, for: cluster.id)
        }
    }

    func deleteCluster(_ id: UUID, from appState: AppState) async {
        if appState.configStore.selectedClusterId == id,
           appState.connectionStatus.isConnected
        {
            await appState.disconnect()
        }
        KeychainManager.deletePassword(for: id)
        appState.configStore.deleteCluster(id)
        try? await appState.metricDatabase?.deleteClusterData(clusterId: id)
    }

    func testConnection(config: ClusterConfig, password: String?, appState: AppState) async {
        isTesting = true
        defer { isTesting = false }

        let result = await appState.testConnection(config: config, password: password)
        switch result {
        case .success:
            testResult = .success
        case let .failure(error):
            testResult = .failure(error.localizedDescription)
        }
    }

    func selectCluster(_ id: UUID, appState: AppState) async {
        if appState.connectionStatus.isConnected {
            await appState.disconnect()
        }
        appState.configStore.selectedClusterId = id
        await appState.connect()
    }
}
