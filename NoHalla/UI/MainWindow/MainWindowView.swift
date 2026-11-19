//
//  MainWindowView.swift
//  NoHalla
//
//  User-requested windowed experience (like a regular app): the main window
//  opened from the Dock / on launch. Shows the three-step onboarding until it is
//  completed, then the shared protection dashboard with a Settings toolbar
//  button. The menu bar shield remains for quick popover access.
//

import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if !appState.config.onboardingCompleted {
                OnboardingContainerView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                dashboard
            }
        }
        .frame(minWidth: 480, idealWidth: 520, minHeight: 540, idealHeight: 600)
        .background(DesignTokens.bg)
    }

    private var dashboard: some View {
        ScrollView {
            DashboardView()
                .padding(DesignTokens.spacing4)
                .frame(maxWidth: 960, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(DesignTokens.bg)
        .tint(DesignTokens.action)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                SettingsButton(iconOnly: true)
            }
        }
    }
}

#Preview("Main window") {
    MainWindowView()
        .environmentObject(AppState.preview(.protected))
}

#Preview("Main window onboarding") {
    MainWindowView()
        .environmentObject(AppState.preview(.setup, trustedAddresses: []))
}