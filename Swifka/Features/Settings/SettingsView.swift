import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState

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

            // Appearance
            Section(l10n["settings.appearance"]) {
                Picker(l10n["settings.appearance"], selection: $state.appearanceMode) {
                    Text(l10n["settings.appearance.system"]).tag(AppearanceMode.system)
                    Text(l10n["settings.appearance.light"]).tag(AppearanceMode.light)
                    Text(l10n["settings.appearance.dark"]).tag(AppearanceMode.dark)
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
