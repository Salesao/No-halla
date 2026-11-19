//
//  SettingsProtectionView.swift
//  NoHalla
//
//  Protection settings tab (design §7.4, FR-10/13/14/21/27, spec D19/D24/D27):
//  master Protection switch first (D27), grace slider 0–120 (D24), check
//  interval 10–120 (D19), freeze-when-unknown / check-IPv6 / require-VPN toggles,
//  trusted IPs (add/remove/edit + Add current IP) and protected apps
//  (add/remove via the app picker). Changes apply to config/engine immediately.
//

import SwiftUI

struct SettingsProtectionView: View {
    @EnvironmentObject var appState: AppState
    @State private var showAppPicker = false
    @State private var editingAddress: String?
    @State private var showAddressEditor = false

    private var protection: ProtectionSettings { appState.config.protection }

    var body: some View {
        Form {
            Section {
                SettingRowView(label: L10n.string("ui.protection"), helper: L10n.string("ui.protection-toggle-helper")) {
                    Toggle("", isOn: Binding(
                        get: { protection.enabled },
                        set: { newValue in updateProtection { $0.enabled = newValue } }
                    ))
                    .labelsHidden()
                }
            }

            Section(L10n.string("ui.protection-mode")) {
                Picker("", selection: Binding(
                    get: { protection.mode },
                    set: { newValue in updateProtection { $0.mode = newValue } }
                )) {
                    Text(L10n.string("ui.mode-vpn")).tag(ProtectionMode.vpnInterface)
                    Text(L10n.string("ui.mode-ip")).tag(ProtectionMode.ipWhitelist)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text(protection.mode == .vpnInterface ? L10n.string("ui.mode-vpn-helper") : L10n.string("ui.mode-ip-helper"))
                    .font(.system(size: DesignTokens.typeSmall))
                    .foregroundStyle(DesignTokens.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section(L10n.string("ui.preferences")) {
                SettingRowView(label: L10n.string("ui.grace-period"), helper: L10n.string("ui.apps-freeze-after-this-delay-when-the-ip-changes")) {
                    HStack {
                        Slider(value: Binding(
                            get: { Double(protection.graceSeconds) },
                            set: { newValue in updateProtection { $0.graceSeconds = Int(newValue) } }
                        ), in: 0...120, step: 1)
                        .frame(width: 160)
                        Text("\(protection.graceSeconds) \(L10n.string("ui.unit-seconds"))")
                            .font(.system(size: DesignTokens.typeSmall))
                            .foregroundStyle(DesignTokens.muted)
                            .frame(width: 48, alignment: .trailing)
                    }
                }
                SettingRowView(label: L10n.string("ui.check-interval")) {
                    HStack {
                        Slider(value: Binding(
                            get: { Double(protection.checkIntervalSeconds) },
                            set: { newValue in updateProtection { $0.checkIntervalSeconds = Int(newValue) } }
                        ), in: 10...120, step: 1)
                        .frame(width: 160)
                        Text("\(protection.checkIntervalSeconds) \(L10n.string("ui.unit-seconds"))")
                            .font(.system(size: DesignTokens.typeSmall))
                            .foregroundStyle(DesignTokens.muted)
                            .frame(width: 48, alignment: .trailing)
                    }
                }
                SettingRowView(label: L10n.string("ui.freeze-when-ip-can-t-be-verified")) {
                    Toggle("", isOn: Binding(
                        get: { protection.freezeWhenUnknown },
                        set: { newValue in updateProtection { $0.freezeWhenUnknown = newValue } }
                    ))
                    .labelsHidden()
                }
                SettingRowView(label: L10n.string("ui.check-ipv6")) {
                    Toggle("", isOn: Binding(
                        get: { protection.checkIPv6 },
                        set: { newValue in updateProtection { $0.checkIPv6 = newValue } }
                    ))
                    .labelsHidden()
                }
                SettingRowView(label: L10n.string("ui.require-active-vpn-interface"), helper: L10n.string("ui.protection-requires-an-active-tunnel-when-this-is-on")) {
                    Toggle("", isOn: Binding(
                        get: { protection.requireVPNInterface },
                        set: { newValue in updateProtection { $0.requireVPNInterface = newValue } }
                    ))
                    .labelsHidden()
                }
            }

            Section(L10n.string("ui.trusted-ips")) {
                ForEach(appState.config.trustedAddresses, id: \.self) { address in
                    HStack {
                        Text(address)
                            .font(.system(size: DesignTokens.typeBody, design: .monospaced))
                            .foregroundStyle(DesignTokens.text)
                        Spacer()
                        Button(L10n.string("ui.edit")) { editingAddress = address; showAddressEditor = true }
                            .buttonStyle(.borderless)
                        Button(L10n.string("ui.remove")) { removeAddress(address) }
                            .buttonStyle(.borderless)
                            .foregroundStyle(DesignTokens.red)
                    }
                }
                HStack {
                    Button(L10n.string("ui.add")) { editingAddress = nil; showAddressEditor = true }
                        .buttonStyle(.bordered)
                    Button(L10n.string("network.addCurrentIP")) { appState.send(.addCurrentIP) }
                        .buttonStyle(.bordered)
                }
            }

            Section(L10n.string("apps.title")) {
                ForEach(appState.config.protectedApps) { app in
                    HStack {
                        Text(app.name)
                            .font(.system(size: DesignTokens.typeBody))
                            .foregroundStyle(DesignTokens.text)
                        Spacer()
                        Text(appState.snapshot.runningBundleIDs.contains(app.bundleID) ? L10n.string("ui.running") : L10n.string("apps.notRunning"))
                            .font(.system(size: DesignTokens.typeSmall))
                            .foregroundStyle(DesignTokens.muted)
                        Button(L10n.string("ui.remove")) { removeApp(app) }
                            .buttonStyle(.borderless)
                            .foregroundStyle(DesignTokens.red)
                    }
                }
                Button(L10n.string("apps.add")) { showAppPicker = true }
                    .buttonStyle(.bordered)
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showAddressEditor) {
            TrustedAddressEditor(
                original: editingAddress,
                onSave: { value in saveAddress(value); showAddressEditor = false },
                onCancel: { showAddressEditor = false }
            )
        }
        .sheet(isPresented: $showAppPicker) {
            AppPickerSheet(
                existingBundleIDs: Set(appState.config.protectedApps.map { $0.bundleID }),
                onAdd: { newApps in
                    var config = appState.config
                    config.protectedApps.append(contentsOf: newApps)
                    appState.setConfig(config)
                    showAppPicker = false
                },
                onCancel: { showAppPicker = false }
            )
        }
    }

    private func updateProtection(_ mutate: (inout ProtectionSettings) -> Void) {
        var config = appState.config
        mutate(&config.protection)
        appState.setConfig(config)
    }

    private func saveAddress(_ value: String) {
        var config = appState.config
        if let original = editingAddress, let index = config.trustedAddresses.firstIndex(of: original) {
            config.trustedAddresses[index] = value
        } else if !config.trustedAddresses.contains(value) {
            config.trustedAddresses.append(value)
        }
        appState.setConfig(config)
    }

    private func removeAddress(_ address: String) {
        var config = appState.config
        config.trustedAddresses.removeAll { $0 == address }
        appState.setConfig(config)
    }

    private func removeApp(_ app: ProtectedApp) {
        var config = appState.config
        config.protectedApps.removeAll { $0.bundleID == app.bundleID }
        appState.setConfig(config)
    }
}

#Preview {
    SettingsProtectionView()
        .environmentObject(AppState())
        .frame(width: 680, height: 520)
}