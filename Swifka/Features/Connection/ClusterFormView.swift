import SwiftUI

struct ClusterFormView: View {
    enum Mode {
        case add
        case edit(ClusterConfig)
    }

    let mode: Mode
    let onSave: (ClusterConfig, String?) -> Void

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var host: String = ""
    @State private var port: String = ""
    @State private var authType: AuthType = .none
    @State private var saslMechanism: SASLMechanism = .plain
    @State private var saslUsername: String = ""
    @State private var saslPassword: String = ""
    @State private var useTLS = false

    @State private var isTesting = false
    @State private var testResult: ConnectionViewModel.TestResult?

    init(mode: Mode, onSave: @escaping (ClusterConfig, String?) -> Void) {
        self.mode = mode
        self.onSave = onSave
    }

    var body: some View {
        let l10n = appState.l10n
        let isEditing = if case .edit = mode { true } else { false }

        VStack(spacing: 0) {
            Text(isEditing ? l10n["cluster.edit"] : l10n["cluster.add"])
                .font(.headline)
                .padding()

            Form {
                Section {
                    TextField(l10n["cluster.name"], text: $name)
                    TextField(l10n["cluster.host"], text: $host, prompt: Text("localhost"))
                    TextField(l10n["cluster.port"], text: $port, prompt: Text("9092"))
                }

                Section {
                    Picker("Auth", selection: $authType) {
                        Text("None").tag(AuthType.none)
                        Text("SASL").tag(AuthType.sasl)
                    }
                    .pickerStyle(.segmented)

                    if authType == .sasl {
                        Picker("Mechanism", selection: $saslMechanism) {
                            ForEach(SASLMechanism.allCases, id: \.self) { mechanism in
                                Text(mechanism.rawValue).tag(mechanism)
                            }
                        }
                        TextField("Username", text: $saslUsername)
                        SecureField("Password", text: $saslPassword)
                    }

                    Toggle("Use TLS", isOn: $useTLS)
                }

                if let testResult {
                    Section {
                        switch testResult {
                        case .success:
                            Label(l10n["connection.test.success"], systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        case let .failure(msg):
                            Label(msg, systemImage: "xmark.circle.fill")
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Button(l10n["connection.test"]) {
                    testConnection()
                }
                .disabled(name.isEmpty || host.isEmpty || port.isEmpty || isTesting)

                Spacer()

                Button(l10n["common.cancel"]) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(l10n["common.save"]) {
                    saveCluster()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty || host.isEmpty || port.isEmpty)
            }
            .padding()
        }
        .frame(width: 450, height: 420)
        .onAppear {
            if case let .edit(cluster) = mode {
                name = cluster.name
                host = cluster.host
                port = String(cluster.port)
                authType = cluster.authType
                saslMechanism = cluster.saslMechanism ?? .plain
                saslUsername = cluster.saslUsername ?? ""
                useTLS = cluster.useTLS
                if let pwd = KeychainManager.loadPassword(for: cluster.id) {
                    saslPassword = pwd
                }
            }
        }
    }

    private func saveCluster() {
        let existingId: UUID? = if case let .edit(cluster) = mode { cluster.id } else { nil }
        guard let portNum = Int(port), portNum > 0, portNum <= 65535 else { return }

        let cluster = ClusterConfig(
            id: existingId ?? UUID(),
            name: name,
            host: host,
            port: portNum,
            authType: authType,
            saslMechanism: authType == .sasl ? saslMechanism : nil,
            saslUsername: authType == .sasl ? saslUsername : nil,
            useTLS: useTLS,
        )

        let password: String? = authType == .sasl && !saslPassword.isEmpty ? saslPassword : nil
        onSave(cluster, password)
        dismiss()
    }

    private func testConnection() {
        isTesting = true
        testResult = nil

        guard let portNum = Int(port), portNum > 0, portNum <= 65535 else {
            testResult = .failure("Invalid port number")
            isTesting = false
            return
        }

        let config = ClusterConfig(
            name: name,
            host: host,
            port: portNum,
            authType: authType,
            saslMechanism: authType == .sasl ? saslMechanism : nil,
            saslUsername: authType == .sasl ? saslUsername : nil,
            useTLS: useTLS,
        )
        let password: String? = authType == .sasl && !saslPassword.isEmpty ? saslPassword : nil

        Task {
            let result = await appState.testConnection(config: config, password: password)
            isTesting = false
            switch result {
            case .success:
                testResult = .success
            case let .failure(error):
                testResult = .failure(error.localizedDescription)
            }
        }
    }
}
