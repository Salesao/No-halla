//
//  OnboardingTrustedRealmView.swift
//  NoHalla
//
//  Onboarding step 3 of 3 (design §7.3): the current IP shown large, Trust this
//  IP / Add manually with inline CIDR validation, a Launch-at-login toggle
//  (default on, SMAppService), Back / Finish.
//

import SwiftUI

struct OnboardingTrustedRealmView: View {
    @EnvironmentObject var appState: AppState
    @Binding var launchAtLogin: Bool
    let onBack: () -> Void
    let onFinish: () -> Void

    @State private var manualIP = ""
    @State private var manualError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacing3) {
            Text(L10n.string("onboarding.3.title"))
                .font(.system(size: DesignTokens.typeTitle, weight: .semibold))
                .foregroundStyle(DesignTokens.text)
            Text(L10n.string("onboarding.3.body"))
                .font(.system(size: DesignTokens.typeBody))
                .foregroundStyle(DesignTokens.muted)
                .fixedSize(horizontal: false, vertical: true)

            Text(appState.snapshot.currentIPv4 ?? "—")
                .font(.system(size: 28, design: .monospaced))
                .foregroundStyle(DesignTokens.text)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, DesignTokens.spacing2)

            Button(L10n.string("ui.trust-this-ip")) { appState.send(.addCurrentIP) }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: DesignTokens.spacing1) {
                TextField(L10n.string("ui.enter-an-ipv4-ipv6-or-cidr-address"), text: $manualIP)
                    .textFieldStyle(.roundedBorder)
                if let manualError = manualError {
                    Text(manualError)
                        .font(.system(size: DesignTokens.typeSmall))
                        .foregroundStyle(DesignTokens.red)
                }
                Button(L10n.string("ui.add-manually"), action: addManual)
                    .buttonStyle(.bordered)
            }

            Toggle(L10n.string("onboarding.launchAtLogin"), isOn: $launchAtLogin)
                .toggleStyle(.switch)
            if let loginError = appState.launchAtLoginError {
                Text(loginError)
                    .font(.system(size: DesignTokens.typeSmall))
                    .foregroundStyle(DesignTokens.red)
            }

            Spacer(minLength: DesignTokens.spacing2)
            HStack {
                Button(L10n.string("ui.back"), action: onBack)
                    .buttonStyle(.bordered)
                Spacer()
                Button(L10n.string("ui.finish"), action: onFinish)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(DesignTokens.spacing5)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func addManual() {
        let trimmed = manualIP.trimmingCharacters(in: .whitespacesAndNewlines)
        guard CIDRRange(trimmed) != nil else {
            manualError = L10n.string("ui.enter-a-valid-ipv4-ipv6-or-cidr-address")
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
    OnboardingTrustedRealmView(launchAtLogin: .constant(true), onBack: {}, onFinish: {})
        .environmentObject(AppState())
        .frame(width: 560, height: 420)
}