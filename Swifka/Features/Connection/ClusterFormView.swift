import SwiftUI
import UniformTypeIdentifiers

struct ClusterFormView: View {
    enum Mode {
        case add
        case edit(ClusterConfig)
    }

    private enum KerberosFilePickerTarget {
        case keytab
        case krb5Conf
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
    @State private var kerberosPrincipal: String = ""
    @State private var kerberosServiceName: String = "kafka"
    @State private var kerberosKeytabPath: String = ""
    @State private var kerberosKrb5ConfPath: String = ""
    @State private var kerberosFilePickerTarget: KerberosFilePickerTarget?
    @State private var useTLS = false

    // Schema Registry
    @State private var schemaRegistryURL: String = ""
    @State private var isTestingRegistry = false
    @State private var registryTestResult: ConnectionViewModel.TestResult?

    @State private var isTesting = false
    @State private var testResult: ConnectionViewModel.TestResult?

    init(mode: Mode, onSave: @escaping (ClusterConfig, String?) -> Void) {
        self.mode = mode
        self.onSave = onSave
    }

    var body: some View {
        let l10n = appState.l10n
        let isEditing = if case .edit = mode {
            true
        } else {
            false
        }

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

                        if saslMechanism == .gssapi {
                            TextField(
                                l10n["cluster.kerberos.service.name"],
                                text: $kerberosServiceName,
                                prompt: Text("kafka"),
                            )
                            TextField(
                                l10n["cluster.kerberos.principal"],
                                text: $kerberosPrincipal,
                                prompt: Text("kafkaclient/host@REALM"),
                            )
                            HStack {
                                TextField(
                                    l10n["cluster.kerberos.keytab"],
                                    text: $kerberosKeytabPath,
                                    prompt: Text("/Users/you/.config/y2kexplorer/keytab.bin"),
                                )
                                Button(l10n["cluster.kerberos.keytab.browse"]) {
                                    kerberosFilePickerTarget = .keytab
                                }
                            }
                            HStack {
                                TextField(
                                    l10n["cluster.kerberos.krb5.conf"],
                                    text: $kerberosKrb5ConfPath,
                                    prompt: Text("/Users/you/.config/y2kexplorer/krb5.conf"),
                                )
                                Button(l10n["cluster.kerberos.keytab.browse"]) {
                                    kerberosFilePickerTarget = .krb5Conf
                                }
                            }
                            Text(l10n["cluster.kerberos.description"])
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            TextField("Username", text: $saslUsername)
                            SecureField("Password", text: $saslPassword)
                        }
                    }

                    Toggle("Use TLS", isOn: $useTLS)
                }

                Section {
                    HStack {
                        TextField(
                            l10n["cluster.schema.registry.url"],
                            text: $schemaRegistryURL,
                            prompt: Text("http://localhost:8081"),
                        )

                        ZStack {
                            ProgressView()
                                .controlSize(.small)
                                .opacity(isTestingRegistry ? 1 : 0)

                            Button(l10n["connection.test"]) {
                                testSchemaRegistry()
                            }
                            .disabled(schemaRegistryURL.isEmpty || isTestingRegistry)
                            .opacity(isTestingRegistry ? 0 : 1)
                        }
                    }

                    Group {
                        switch registryTestResult {
                        case .success:
                            Label(
                                l10n["cluster.schema.registry.test.success"],
                                systemImage: "checkmark.circle.fill",
                            )
                            .foregroundStyle(.green)
                        case let .failure(msg):
                            Label(msg, systemImage: "xmark.circle.fill")
                                .foregroundStyle(.red)
                        case .none:
                            Label(" ", systemImage: "circle")
                                .foregroundStyle(.clear)
                        }
                    }
                    .opacity(registryTestResult != nil ? 1 : 0)

                    Text(l10n["cluster.schema.registry.description"])
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                } header: {
                    Text(l10n["cluster.schema.registry"] + " (" + l10n["cluster.schema.registry.optional"] + ")")
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
        .frame(width: 450, height: formHeight)
        .fileImporter(
            isPresented: Binding(
                get: { kerberosFilePickerTarget != nil },
                set: {
                    if !$0 {
                        kerberosFilePickerTarget = nil
                    }
                },
            ),
            allowedContentTypes: kerberosFilePickerContentTypes,
            allowsMultipleSelection: false,
        ) { result in
            let target = kerberosFilePickerTarget
            kerberosFilePickerTarget = nil
            switch result {
            case let .success(urls):
                guard let url = urls.first else { return }
                let gotAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if gotAccess {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                switch target {
                case .keytab:
                    kerberosKeytabPath = url.path
                case .krb5Conf:
                    kerberosKrb5ConfPath = url.path
                case .none:
                    break
                }
            case .failure:
                break
            }
        }
        .onAppear {
            if case let .edit(cluster) = mode {
                name = cluster.name
                host = cluster.host
                port = String(cluster.port)
                authType = cluster.authType
                saslMechanism = cluster.saslMechanism ?? .plain
                saslUsername = cluster.saslUsername ?? ""
                kerberosPrincipal = cluster.saslKerberosPrincipal ?? ""
                kerberosServiceName = cluster.saslKerberosServiceName ?? "kafka"
                kerberosKeytabPath = cluster.saslKerberosKeytabPath ?? ""
                kerberosKrb5ConfPath = cluster.saslKerberosKrb5ConfPath ?? ""
                useTLS = cluster.useTLS
                schemaRegistryURL = cluster.schemaRegistryURL ?? ""
                if let pwd = KeychainManager.loadPassword(for: cluster.id) {
                    saslPassword = pwd
                }
            }
        }
    }

    private func saveCluster() {
        let existing: ClusterConfig? = if case let .edit(cluster) = mode {
            cluster
        } else {
            nil
        }
        guard let portNum = Int(port), portNum > 0, portNum <= 65535 else { return }

        let cluster = ClusterConfig(
            id: existing?.id ?? UUID(),
            name: name,
            host: host,
            port: portNum,
            authType: authType,
            saslMechanism: authType == .sasl ? saslMechanism : nil,
            saslUsername: authType == .sasl && saslMechanism != .gssapi ? saslUsername : nil,
            saslKerberosPrincipal: authType == .sasl && saslMechanism == .gssapi ? kerberosPrincipal.nilIfBlank : nil,
            saslKerberosServiceName: authType == .sasl && saslMechanism == .gssapi ? kerberosServiceName.nilIfBlank : nil,
            saslKerberosKeytabPath: authType == .sasl && saslMechanism == .gssapi ? kerberosKeytabPath.nilIfBlank : nil,
            saslKerberosKrb5ConfPath: authType == .sasl && saslMechanism == .gssapi ? kerberosKrb5ConfPath.nilIfBlank : nil,
            useTLS: useTLS,
            schemaRegistryURL: schemaRegistryURL.isEmpty ? nil : schemaRegistryURL,
            createdAt: existing?.createdAt ?? Date(),
            isPinned: existing?.isPinned ?? false,
            lastConnectedAt: existing?.lastConnectedAt,
            sortOrder: existing?.sortOrder ?? 0,
        )

        let password: String? = authType == .sasl && saslMechanism.usesPassword && !saslPassword.isEmpty
            ? saslPassword
            : nil
        onSave(cluster, password)
        dismiss()
    }

    private func testSchemaRegistry() {
        isTestingRegistry = true
        registryTestResult = nil

        Task {
            do {
                guard let url = URL(string: schemaRegistryURL.trimmingCharacters(in: .whitespacesAndNewlines)),
                      let subjectsURL = URL(string: "\(url.absoluteString)/subjects")
                else {
                    registryTestResult = .failure("Invalid URL")
                    isTestingRegistry = false
                    return
                }
                let (_, response) = try await URLSession.shared.data(from: subjectsURL)
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    registryTestResult = .success
                } else {
                    registryTestResult = .failure("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                }
            } catch {
                registryTestResult = .failure(error.localizedDescription)
            }
            isTestingRegistry = false
        }
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
            saslUsername: authType == .sasl && saslMechanism != .gssapi ? saslUsername : nil,
            saslKerberosPrincipal: authType == .sasl && saslMechanism == .gssapi ? kerberosPrincipal.nilIfBlank : nil,
            saslKerberosServiceName: authType == .sasl && saslMechanism == .gssapi ? kerberosServiceName.nilIfBlank : nil,
            saslKerberosKeytabPath: authType == .sasl && saslMechanism == .gssapi ? kerberosKeytabPath.nilIfBlank : nil,
            saslKerberosKrb5ConfPath: authType == .sasl && saslMechanism == .gssapi ? kerberosKrb5ConfPath.nilIfBlank : nil,
            useTLS: useTLS,
        )
        let password: String? = authType == .sasl && saslMechanism.usesPassword && !saslPassword.isEmpty
            ? saslPassword
            : nil

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

    private var formHeight: CGFloat {
        if authType == .sasl, saslMechanism == .gssapi {
            680
        } else {
            520
        }
    }

    private var kerberosFilePickerContentTypes: [UTType] {
        switch kerberosFilePickerTarget {
        case .keytab:
            Self.keytabContentTypes
        case .krb5Conf:
            [.plainText, .text, .data, .item]
        case .none:
            [.item]
        }
    }

    private static let keytabContentTypes: [UTType] = {
        var types: [UTType] = [.item, .data]
        if let keytab = UTType(filenameExtension: "keytab") {
            types.append(keytab)
        }
        if let bin = UTType(filenameExtension: "bin") {
            types.append(bin)
        }
        if let appleKeytab = UTType("com.apple.kerberos.keytab") {
            types.append(appleKeytab)
        }
        return types
    }()
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
