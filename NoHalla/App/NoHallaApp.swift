//
//  NoHallaApp.swift
//  NoHalla
//
//  SwiftUI entry point. A MenuBarExtra agent (LSUIElement) whose template glyph
//  tracks the derived UI status (design/ICONS.md) with a VoiceOver label
//  (design/ACCESSIBILITY.md). Scenes: the full popover, the four-tab Settings
//  window, and an onboarding window opened on first launch (FR-2).
//

import SwiftUI

@main
struct NoHallaApp: App {
    @NSApplicationDelegateAdaptor(NoHallaAppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow

    private var appState: AppState { appDelegate.appState }

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environmentObject(appState)
        } label: {
            Image(DesignTokens.menuBarImageName(for: appState.uiStatus))
                .renderingMode(.template)
                .accessibilityLabel(L10n.string(DesignTokens.menuBarAccessibilityKey(for: appState.uiStatus)))
                .task {
                    if !appState.config.onboardingCompleted {
                        openWindow(id: "onboarding")
                    }
                }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsRootView()
                .environmentObject(appState)
        }

        Window(L10n.string("brand.name"), id: "onboarding") {
            OnboardingContainerView()
                .environmentObject(appState)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}