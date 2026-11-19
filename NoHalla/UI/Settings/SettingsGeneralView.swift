//
//  SettingsGeneralView.swift
//  NoHalla
//
//  General settings tab (design §7.4, FR-3/27/29/33/38): launch at login with
//  inline SMAppService error, notifications toggle with a denied banner, language
//  selection applied in-process (D12), and the corrupt-config banner (FR-38).
//

import ServiceManagement
import SwiftUI

struct SettingsGeneralView: View {
    @EnvironmentObject var appState: AppState
    @State private var launchAtLogin = false
    @State private var selectedLanguage: AppLanguage = .system

    var body: some View {
        Form {
            if appState.corruptConfigBanner {
                Section {
                    VStack(alignment: .leading, spacing: DesignTokens.spacing1) {
                        Text(L10n.string("ui.corrupt-config-title"))
                            .font(.system(size: DesignTokens.typeBody, weight: .semibold))
                            .foregroundStyle(DesignTokens.orange)
                        Text(L10n.string("ui.corrupt-config-body"))
                            .font(.system(size: DesignTokens.typeSmall))
                            .foregroundStyle(DesignTokens.muted)
                    }
                }
            }

            Section(L10n.string("ui.startup")) {
                SettingRowView(label: L10n.string("ui.launch-at-login"), helper: appState.launchAtLoginError) {
                    Toggle("", isOn: $launchAtLogin)
                        .labelsHidden()
                        .onChange(of: launchAtLogin) { newValue in setLaunchAtLogin(newValue) }
                }
            }

            Section(L10n.string("ui.notifications")) {
                SettingRowView(label: L10n.string("ui.notifications")) {
                    Toggle("", isOn: Binding(
                        get: { appState.config.notifications },
                        set: { newValue in
                            var config = appState.config
                            config.notifications = newValue
                            appState.setConfig(config)
                        }
                    ))
                    .labelsHidden()
                }
                if appState.notificationsDenied {
                    VStack(alignment: .leading, spacing: DesignTokens.spacing1) {
                        Text(L10n.string("ui.notifications-are-off-in-system-settings"))
                            .font(.system(size: DesignTokens.typeSmall))
                            .foregroundStyle(DesignTokens.orange)
                        Button(L10n.string("ui.open-system-settings")) { openNotificationSettings() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
            }

            Section(L10n.string("ui.language")) {
                SettingRowView(label: L10n.string("ui.language")) {
                    Picker("", selection: $selectedLanguage) {
                        Text(L10n.string("ui.system")).tag(AppLanguage.system)
                        Text(L10n.string("ui.language-english")).tag(AppLanguage.en)
                        Text(L10n.string("ui.language-russian")).tag(AppLanguage.ru)
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }
                Button(L10n.string("ui.apply-language-change")) { applyLanguage() }
                    .buttonStyle(.bordered)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            selectedLanguage = appState.config.language
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        var config = appState.config
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            config.launchAtLogin = enabled
            appState.launchAtLoginError = nil
            appState.setConfig(config)
        } catch {
            appState.launchAtLoginError = L10n.string("ui.couldn-t-enable-launch-at-login-try-again")
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func applyLanguage() {
        L10n.current = selectedLanguage
        var config = appState.config
        config.language = selectedLanguage
        appState.setConfig(config)
        appState.objectWillChange.send()
    }

    private func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}

#Preview {
    SettingsGeneralView()
        .environmentObject(AppState())
        .frame(width: 680, height: 520)
}