//
//  NoHallaApp.swift
//  NoHalla
//
//  SwiftUI entry point. A MenuBarExtra agent (LSUIElement) whose template glyph
//  tracks the derived UI status (design/ICONS.md). S1 shows a placeholder
//  popover; S3 replaces it with the full design and adds Settings/onboarding
//  scenes.
//

import SwiftUI

@main
struct NoHallaApp: App {
    @NSApplicationDelegateAdaptor(NoHallaAppDelegate.self) private var appDelegate

    private var appState: AppState { appDelegate.appState }

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environmentObject(appState)
        } label: {
            Image(DesignTokens.menuBarImageName(for: appState.uiStatus))
                .renderingMode(.template)
                .accessibilityLabel(L10n.string(DesignTokens.menuBarAccessibilityKey(for: appState.uiStatus)))
        }
        .menuBarExtraStyle(.window)

        Settings {
            // S3 replaces this with SettingsRootView (four tabs).
            Text(L10n.string("brand.name"))
                .padding(24)
        }
    }
}