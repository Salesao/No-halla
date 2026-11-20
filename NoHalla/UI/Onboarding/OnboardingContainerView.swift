//
//  OnboardingContainerView.swift
//  NoHalla
//
//  Three-step onboarding (design §7.3, FR-2/3/10, D36): intro, apps, trusted
//  realm (mode + IPs), with progress dots. Finish persists
//  onboardingCompleted, the selected apps and launch-at-login (SMAppService,
//  inline error on failure), then requests notification permission (FR-29).
//  Embedded in the main window, which switches to the dashboard once
//  onboardingCompleted becomes true.
//

import ServiceManagement
import SwiftUI

struct OnboardingContainerView: View {
    @EnvironmentObject var appState: AppState

    @State private var step = 0
    @State private var selectedApps: [ProtectedApp] = []
    @State private var launchAtLogin = true

    var body: some View {
        VStack(spacing: 0) {
            progressDots
                .padding(.top, DesignTokens.spacing3)
            Group {
                switch step {
                case 0:
                    OnboardingIntroView(
                        onContinue: { step = 1 },
                        onSkip: { finish(includeApps: false) }
                    )
                case 1:
                    OnboardingAppsView(
                        selectedApps: $selectedApps,
                        onBack: { step = 0 },
                        onContinue: { step = 2 }
                    )
                default:
                    OnboardingTrustedRealmView(
                        launchAtLogin: $launchAtLogin,
                        onBack: { step = 1 },
                        onContinue: { finish(includeApps: true) }
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.bg)
    }

    private var progressDots: some View {
        HStack(spacing: DesignTokens.spacing2) {
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(index == step ? DesignTokens.action : DesignTokens.line)
                    .frame(width: index == step ? 28 : 18, height: 4)
            }
        }
        .accessibilityLabel(L10n.string("onboarding.step", step + 1))
    }

    private func finish(includeApps: Bool) {
        // R53: read the freshest persisted config — "Trust this IP" on step 3
        // writes via the engine (addCurrentIP), so a stale appState.config would
        // drop the trusted IP and leave protection in setup.
        var config = appState.configStore.load()
        config.onboardingCompleted = true
        if includeApps {
            for app in selectedApps where !config.protectedApps.contains(where: { $0.bundleID == app.bundleID }) {
                config.protectedApps.append(app)
            }
        }
        // Launch at login via SMAppService; on failure show inline and do not
        // silently keep the toggle on (FR-3, brief §8.7).
        if launchAtLogin {
            do {
                try SMAppService.mainApp.register()
                config.launchAtLogin = true
                appState.launchAtLoginError = nil
            } catch {
                config.launchAtLogin = false
                appState.launchAtLoginError = L10n.string("ui.couldn-t-enable-launch-at-login-try-again")
            }
        } else {
            try? SMAppService.mainApp.unregister()
            config.launchAtLogin = false
        }
        appState.setConfig(config)
        appState.requestNotificationPermission()
        // No dismiss: the enclosing main window reactively shows the dashboard
        // once onboardingCompleted is true.
    }
}

#Preview {
    OnboardingContainerView()
        .environmentObject(AppState())
}