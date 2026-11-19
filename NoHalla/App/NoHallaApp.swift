//
//  NoHallaApp.swift
//  NoHalla
//
//  SwiftUI entry point. User-requested windowed experience: a main WindowGroup
//  (opened on launch / from the Dock, like a regular app) shows onboarding then
//  the protection dashboard. A MenuBarExtra shield remains for quick popover
//  access, and Settings opens as its own window. The Dock icon is enabled
//  (LSUIElement=false); the menu bar glyph tracks the derived UI status.
//

import SwiftUI

@main
struct NoHallaApp: App {
    @NSApplicationDelegateAdaptor(NoHallaAppDelegate.self) private var appDelegate

    private var appState: AppState { appDelegate.appState }

    var body: some Scene {
        WindowGroup(L10n.string("brand.name")) {
            MainWindowView()
                .environmentObject(appState)
        }
        .windowResizability(.contentSize)

        MenuBarExtra {
            PopoverView()
                .environmentObject(appState)
        } label: {
            MenuBarLabelView(appState: appState)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsRootView()
                .environmentObject(appState)
        }
    }
}