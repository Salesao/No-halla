//
//  SettingsProtectionView.swift
//  NoHalla
//
//  Protection settings tab (design §7.4, FR-10/13/14/21/27, spec D19/D24/D27/D31):
//  grace slider 0–120 (D24), check interval 10–120 (D19), freeze-when-unknown /
//  require-VPN toggles, trusted IPs (add/remove/edit + Add current IP) and
//  protected apps (add/remove via the app picker). D31: the master Protection
//  switch lives on the dashboard only; editing the trusted list restarts
//  protection immediately. Changes apply to config/engine right away.
//

import SwiftUI

struct SettingsProtectionView: View {
    @EnvironmentObject var appState: AppState

    private struct AddressEdit: Identifiable {
        let id = UUID()
        let original: String?
    }

    @State private var editingAddress: AddressEdit?

    private var protection: ProtectionSettings { appState.config.protection }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.spacing3) {
                SettingsSection(L10n.string("ui.protection-mode")) {
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

                SettingsSection(L10n.string("ui.trusted-ips")) {
                    ForEach(appState.config.trustedAddresses, id: \.self) { address in
                        HStack {
                            Text(address)
                                .font(.system(size: DesignTokens.typeBody, design: .monospaced))
                                .foregroundStyle(DesignTokens.text)
                            Spacer()
                            Button(L10n.string("ui.edit")) { editingAddress = AddressEdit(original: address) }
                                .buttonStyle(.borderless)
                                .tint(DesignTokens.blue)
                                .accessibilityLabel("\(L10n.string("ui.edit")): \(address)")
                            Button(L10n.string("ui.remove")) { removeAddress(address) }
                                .buttonStyle(.borderless)
                                .foregroundStyle(DesignTokens.red)
                                .accessibilityLabel("\(L10n.string("ui.remove")): \(address)")
                        }
                    }
                    HStack {
                        Button(L10n.string("ui.add")) { editingAddress = AddressEdit(original: nil) }
                            .buttonStyle(.bordered)
                            .tint(DesignTokens.blue)
                        Button(L10n.string("network.addCurrentIP")) { appState.send(.addCurrentIP) }
                            .buttonStyle(.bordered)
                            .tint(DesignTokens.blue)
                    }
                }

                SettingsSection(L10n.string("ui.preferences")) {
                    VStack(alignment: .leading, spacing: DesignTokens.spacing1) {
                        Text(L10n.string("ui.grace-period"))
                            .font(.system(size: DesignTokens.typeBody))
                            .foregroundStyle(DesignTokens.text)
                        Text(L10n.string("ui.apps-freeze-after-this-delay-when-the-ip-changes"))
                            .font(.system(size: DesignTokens.typeSmall))
                            .foregroundStyle(DesignTokens.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Slider(value: Binding(
                                get: { Double(protection.graceSeconds) },
                                set: { newValue in
                                    let seconds = Int(newValue.rounded())
                                    guard seconds != protection.graceSeconds else { return }
                                    updateProtection { $0.graceSeconds = seconds }
                                }
                            ), in: 0...120)
                            .accessibilityLabel(L10n.string("ui.grace-period"))
                            Text("\(protection.graceSeconds) \(L10n.string("ui.unit-seconds"))")
                                .font(.system(size: DesignTokens.typeSmall))
                                .foregroundStyle(DesignTokens.muted)
                                .frame(width: 48, alignment: .trailing)
                        }
                    }
                    Divider().overlay(DesignTokens.line)
                    VStack(alignment: .leading, spacing: DesignTokens.spacing1) {
                        Text(L10n.string("ui.check-interval"))
                            .font(.system(size: DesignTokens.typeBody))
                            .foregroundStyle(DesignTokens.text)
                        HStack {
                            Slider(value: Binding(
                                get: { Double(protection.checkIntervalSeconds) },
                                set: { newValue in
                                    let seconds = Int(newValue.rounded())
                                    guard seconds != protection.checkIntervalSeconds else { return }
                                    updateProtection { $0.checkIntervalSeconds = seconds }
                                }
                            ), in: 10...120)
                            .accessibilityLabel(L10n.string("ui.check-interval"))
                            Text("\(protection.checkIntervalSeconds) \(L10n.string("ui.unit-seconds"))")
                                .font(.system(size: DesignTokens.typeSmall))
                                .foregroundStyle(DesignTokens.muted)
                                .frame(width: 48, alignment: .trailing)
                        }
                    }
                    Divider().overlay(DesignTokens.line)
                    SettingRowView(label: L10n.string("ui.freeze-when-ip-can-t-be-verified")) {
                        Toggle("", isOn: Binding(
                            get: { protection.freezeWhenUnknown },
                            set: { newValue in updateProtection { $0.freezeWhenUnknown = newValue } }
                        ))
                        .labelsHidden()
                        .accessibilityLabel(L10n.string("ui.freeze-when-ip-can-t-be-verified"))
                    }
                    SettingRowView(label: L10n.string("ui.require-active-vpn-interface"), helper: L10n.string("ui.protection-requires-an-active-tunnel-when-this-is-on")) {
                        Toggle("", isOn: Binding(
                            get: { protection.requireVPNInterface },
                            set: { newValue in updateProtection { $0.requireVPNInterface = newValue } }
                        ))
                        .labelsHidden()
                        .accessibilityLabel(L10n.string("ui.require-active-vpn-interface"))

                    }
                }
            }
            .padding(DesignTokens.spacing5)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(DesignTokens.bg)
        .tint(DesignTokens.action)
        .toggleStyle(.switch)
        .sheet(item: $editingAddress) { edit in
            TrustedAddressEditor(
                original: edit.original,
                onSave: { value in saveAddress(value, original: edit.original); editingAddress = nil },
                onCancel: { editingAddress = nil }
            )
        }
    }

    private func updateProtection(_ mutate: (inout ProtectionSettings) -> Void) {
        var config = appState.config
        mutate(&config.protection)
        appState.setConfig(config)
    }

    private func saveAddress(_ value: String, original: String?) {
        var config = appState.config
        if let original = original, let index = config.trustedAddresses.firstIndex(of: original) {
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
}

#Preview {
    SettingsProtectionView()
        .environmentObject(AppState())
        .frame(width: 680, height: 520)
}