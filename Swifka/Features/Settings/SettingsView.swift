import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var showClearDataConfirm = false

    var body: some View {
        @Bindable var state = appState
        let l10n = appState.l10n

        Form {
            // Permissions
            Section(l10n["settings.permissions"]) {
                ForEach(OperationLevel.allCases) { level in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(permissionLabel(level, l10n: l10n))
                                .fontWeight(level == appState.operationLevel ? .bold : .regular)
                            Text(permissionDescription(level, l10n: l10n))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if level.isAvailable {
                            if level == appState.operationLevel {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.blue)
                            } else {
                                Button(l10n["common.save"]) {
                                    appState.operationLevel = level
                                }
                                .buttonStyle(.borderless)
                            }
                        } else {
                            Text(l10n["common.comingSoon"])
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            // Refresh
            Section(l10n["settings.refresh"]) {
                Picker(l10n["settings.refresh.mode"], selection: Binding(
                    get: { appState.defaultRefreshMode },
                    set: { newMode in
                        appState.defaultRefreshMode = newMode
                        appState.refreshManager.updateMode(newMode)
                    },
                )) {
                    ForEach(RefreshMode.presets) { mode in
                        Text(refreshModeLabel(mode, l10n: l10n)).tag(mode)
                    }
                }
            }

            // Charts
            Section(l10n["settings.charts"]) {
                Picker(l10n["settings.charts.time.window"], selection: $state.chartTimeWindow) {
                    ForEach(ChartTimeWindow.allCases) { window in
                        Text(window.rawValue).tag(window)
                    }
                }
            }

            // Alerts
            Section(l10n["settings.alerts"]) {
                Toggle(l10n["settings.alerts.isr.enabled"], isOn: $state.isrAlertsEnabled)

                if appState.isrAlertsEnabled {
                    Stepper(
                        value: $state.minInsyncReplicas,
                        in: 1 ... 10,
                    ) {
                        HStack {
                            Text(l10n["settings.alerts.min.isr"])
                            Spacer()
                            Text("\(appState.minInsyncReplicas)")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(l10n["settings.alerts.min.isr.description"])
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                Toggle(l10n["settings.alerts.desktop"], isOn: $state.desktopNotificationsEnabled)

                if appState.desktopNotificationsEnabled, !appState.notificationPermissionGranted {
                    Text(l10n["settings.alerts.desktop.denied"])
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            // Display
            Section(l10n["settings.display"]) {
                Picker(l10n["settings.display.density"], selection: $state.rowDensity) {
                    Text(l10n["settings.density.compact"]).tag(RowDensity.compact)
                    Text(l10n["settings.density.regular"]).tag(RowDensity.regular)
                    Text(l10n["settings.density.large"]).tag(RowDensity.large)
                }
            }

            // Appearance
            Section(l10n["settings.appearance"]) {
                Picker(l10n["settings.appearance"], selection: $state.appearanceMode) {
                    Text(l10n["settings.appearance.system"]).tag(AppearanceMode.system)
                    Text(l10n["settings.appearance.light"]).tag(AppearanceMode.light)
                    Text(l10n["settings.appearance.dark"]).tag(AppearanceMode.dark)
                }
            }

            // Data Retention
            Section(l10n["settings.data.retention"]) {
                Picker(l10n["settings.retention.policy"], selection: $state.retentionPolicy) {
                    Text(l10n["settings.retention.1d"]).tag(DataRetentionPolicy.oneDay)
                    Text(l10n["settings.retention.7d"]).tag(DataRetentionPolicy.sevenDays)
                    Text(l10n["settings.retention.30d"]).tag(DataRetentionPolicy.thirtyDays)
                    Text(l10n["settings.retention.90d"]).tag(DataRetentionPolicy.ninetyDays)
                    Text(l10n["settings.retention.unlimited"]).tag(DataRetentionPolicy.unlimited)
                }

                Button(role: .destructive) {
                    showClearDataConfirm = true
                } label: {
                    Text(l10n["settings.retention.clear"])
                }
                .confirmationDialog(
                    l10n["settings.retention.clear.confirm"],
                    isPresented: $showClearDataConfirm,
                    titleVisibility: .visible,
                ) {
                    Button(l10n["common.delete"], role: .destructive) {
                        Task {
                            await appState.clearAllMetricData()
                        }
                    }
                }
            }

            // Language
            Section(l10n["settings.language"]) {
                Picker(l10n["settings.language"], selection: Binding(
                    get: { appState.l10n.locale },
                    set: { appState.l10n.locale = $0 },
                )) {
                    Text(l10n["settings.language.system"]).tag("system")
                    Text(l10n["settings.language.en"]).tag("en")
                    Text(l10n["settings.language.zh"]).tag("zh-Hans")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(l10n["settings.title"])
    }

    private func permissionLabel(_ level: OperationLevel, l10n: L10n) -> String {
        switch level {
        case .readonly: l10n["settings.permission.readonly"]
        case .write: l10n["settings.permission.write"]
        case .admin: l10n["settings.permission.admin"]
        case .dangerous: l10n["settings.permission.dangerous"]
        }
    }

    private func permissionDescription(_ level: OperationLevel, l10n: L10n) -> String {
        switch level {
        case .readonly: l10n["settings.permission.readonly.description"]
        case .write: l10n["settings.permission.write.description"]
        case .admin: l10n["settings.permission.admin.description"]
        case .dangerous: l10n["settings.permission.dangerous.description"]
        }
    }

    private func refreshModeLabel(_ mode: RefreshMode, l10n: L10n) -> String {
        switch mode {
        case .manual: l10n["settings.refresh.manual"]
        case let .interval(seconds): l10n.t("settings.refresh.interval.seconds", "\(seconds)")
        }
    }
}
