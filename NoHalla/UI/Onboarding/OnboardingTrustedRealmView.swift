//
//  OnboardingTrustedRealmView.swift
//  NoHalla
//
//  Onboarding step 3 of 4 (design §7.3, D36): choose how trust is decided
//  (IP whitelist or VPN tunnel), detect/trust the current IP, see and remove
//  trusted addresses, add one manually, and toggle launch at login.
//

import SwiftUI

struct OnboardingTrustedRealmView: View {
    @EnvironmentObject var appState: AppState
    @Binding var launchAtLogin: Bool
    let onBack: () -> Void
    let onContinue: () -> Void

    @State private var manualIP = ""
    @State private var manualError: String?

    private var protection: ProtectionSettings { appState.config.protection }
    private var currentIP: String? { appState.snapshot.currentIPv4 }
    private var isCurrentTrusted: Bool {
        guard let ip = currentIP else { return false }
        return appState.config.trustedAddresses.contains(ip)
    }
    /// D36: VPN mode needs no address; IP mode needs at least one.
    private var canContinue: Bool {
        protection.mode == .vpnInterface || !appState.config.trustedAddresses.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.spacing3) {
                    Text(L10n.string("onboarding.3.title"))
                        .font(.system(size: DesignTokens.typeTitle, weight: .semibold))
                        .foregroundStyle(DesignTokens.text)
                    Text(L10n.string("onboarding.3.body"))
                        .font(.system(size: DesignTokens.typeBody))
                        .foregroundStyle(DesignTokens.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    // D36: the mode is a real choice, not a Settings-only setting.
                    VStack(alignment: .leading, spacing: DesignTokens.spacing1) {
                        Text(L10n.string("ui.protection-mode"))
                            .font(.system(size: DesignTokens.typeSmall, weight: .semibold))
                            .foregroundStyle(DesignTokens.muted)
                        Picker("", selection: Binding(
                            get: { protection.mode },
                            set: { newValue in updateProtection { $0.mode = newValue } }
                        )) {
                            Text(L10n.string("ui.mode-ip")).tag(ProtectionMode.ipWhitelist)
                            Text(L10n.string("ui.mode-vpn")).tag(ProtectionMode.vpnInterface)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        Text(protection.mode == .vpnInterface ? L10n.string("ui.mode-vpn-helper") : L10n.string("ui.mode-ip-helper"))
                            .font(.system(size: DesignTokens.typeSmall))
                            .foregroundStyle(DesignTokens.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(DesignTokens.spacing3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DesignTokens.surface, in: RoundedRectangle(cornerRadius: DesignTokens.radiusCard))
                    .overlay(RoundedRectangle(cornerRadius: DesignTokens.radiusCard).strokeBorder(DesignTokens.line, lineWidth: 0.5))

                    HStack(alignment: .center, spacing: DesignTokens.spacing3) {
                        VStack(alignment: .leading, spacing: DesignTokens.spacing1) {
                            Text(L10n.string("network.currentIP"))
                                .font(.system(size: DesignTokens.typeSmall))
                                .foregroundStyle(DesignTokens.muted)
                            Text(currentIP ?? "—")
                                .font(.system(size: 19, weight: .semibold, design: .monospaced))
                                .foregroundStyle(DesignTokens.text)
                            if appState.snapshot.isRefreshing {
                                HStack(spacing: 6) {
                                    ProgressView().controlSize(.small)
                                    Text(L10n.string("status.checking"))
                                        .font(.system(size: DesignTokens.typeSmall))
                                        .foregroundStyle(DesignTokens.muted)
                                }
                            } else if currentIP == nil {
                                Text(L10n.string("ui.couldn-t-detect-your-ip"))
                                    .font(.system(size: DesignTokens.typeSmall))
                                    .foregroundStyle(DesignTokens.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer()
                        Button {
                            appState.send(.detectCurrentIP)
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                        .disabled(appState.snapshot.isRefreshing)
                        .help(L10n.string("ui.detect-ip"))
                        .accessibilityLabel(L10n.string("ui.detect-ip"))
                        Button(isCurrentTrusted ? L10n.string("ui.trusted") : L10n.string("ui.trust-this-ip")) {
                            appState.send(.addCurrentIP)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(currentIP == nil || appState.snapshot.isRefreshing || isCurrentTrusted)
                    }
                    .padding(DesignTokens.spacing3)
                    .background(DesignTokens.surface, in: RoundedRectangle(cornerRadius: DesignTokens.radiusCard))
                    .overlay(RoundedRectangle(cornerRadius: DesignTokens.radiusCard).strokeBorder(DesignTokens.line, lineWidth: 0.5))

                    // D36: the list makes "Trust this IP" visibly take effect.
                    if !appState.config.trustedAddresses.isEmpty {
                        VStack(alignment: .leading, spacing: DesignTokens.spacing1) {
                            Text(L10n.string("ui.trusted-ips"))
                                .font(.system(size: DesignTokens.typeSmall, weight: .semibold))
                                .foregroundStyle(DesignTokens.muted)
                            ForEach(appState.config.trustedAddresses, id: \.self) { address in
                                HStack {
                                    Text(address)
                                        .font(.system(size: DesignTokens.typeBody, design: .monospaced))
                                        .foregroundStyle(DesignTokens.text)
                                    Spacer()
                                    Button(L10n.string("ui.remove")) { removeAddress(address) }
                                        .buttonStyle(.borderless)
                                        .foregroundStyle(DesignTokens.red)
                                }
                            }
                        }
                        .padding(DesignTokens.spacing3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(DesignTokens.surface, in: RoundedRectangle(cornerRadius: DesignTokens.radiusCard))
                        .overlay(RoundedRectangle(cornerRadius: DesignTokens.radiusCard).strokeBorder(DesignTokens.line, lineWidth: 0.5))
                    }

                    VStack(alignment: .leading, spacing: DesignTokens.spacing1) {
                        HStack {
                            TextField(L10n.string("ui.enter-an-ipv4-or-cidr-address"), text: $manualIP)
                                .textFieldStyle(.roundedBorder)
                            Button(L10n.string("ui.add-manually"), action: addManual)
                                .buttonStyle(.bordered)
                        }
                        if let manualError = manualError {
                            Text(manualError)
                                .font(.system(size: DesignTokens.typeSmall))
                                .foregroundStyle(DesignTokens.red)
                        }
                    }

                    Toggle(L10n.string("onboarding.launchAtLogin"), isOn: $launchAtLogin)
                        .toggleStyle(.switch)
                    if let loginError = appState.launchAtLoginError {
                        Text(loginError)
                            .font(.system(size: DesignTokens.typeSmall))
                            .foregroundStyle(DesignTokens.red)
                    }
                    if !canContinue {
                        Text(L10n.string("onboarding.3.need-ip"))
                            .font(.system(size: DesignTokens.typeSmall))
                            .foregroundStyle(DesignTokens.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(DesignTokens.spacing5)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Button(L10n.string("ui.back"), action: onBack)
                    .buttonStyle(.bordered)
                Spacer()
                Button(L10n.string("ui.finish"), action: onContinue)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canContinue)
            }
            .padding(.horizontal, DesignTokens.spacing5)
            .padding(.vertical, DesignTokens.spacing3)
            .background(DesignTokens.chrome)
        }
        .tint(DesignTokens.action)
        .task {
            // D35: detect on appearance so the step does not depend on the
            // periodic check (and works in VPN mode, where it never yields an IP).
            appState.send(.detectCurrentIP)
        }
    }

    private func updateProtection(_ mutate: (inout ProtectionSettings) -> Void) {
        var config = appState.config
        mutate(&config.protection)
        appState.setConfig(config)
    }

    private func removeAddress(_ address: String) {
        var config = appState.config
        config.trustedAddresses.removeAll { $0 == address }
        appState.setConfig(config)
    }

    private func addManual() {
        let trimmed = manualIP.trimmingCharacters(in: .whitespacesAndNewlines)
        guard CIDRRange(trimmed) != nil else {
            manualError = L10n.string("ui.enter-a-valid-ipv4-or-cidr-address")
            return
        }
        var config = appState.config
        if !config.trustedAddresses.contains(trimmed) {
            config.trustedAddresses.append(trimmed)
            appState.setConfig(config)
        }
        manualIP = ""
        manualError = nil
    }
}

#Preview {
    OnboardingTrustedRealmView(launchAtLogin: .constant(true), onBack: {}, onContinue: {})
        .environmentObject(AppState())
        .frame(width: 560, height: 460)
}