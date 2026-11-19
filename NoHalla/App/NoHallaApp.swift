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
import ServiceManagement

@main
struct NoHallaApp: App {
    @NSApplicationDelegateAdaptor(NoHallaAppDelegate.self) private var appDelegate

    private var appState: AppState { appDelegate.appState }

    init() {
        // SMAppService.mainApp must run inside the app bundle. The local reset
        // script uses this early exit before the normal application lifecycle.
        guard Array(CommandLine.arguments.dropFirst()) == ["--reset-login-item"] else { return }
        do {
            let service = SMAppService.mainApp
            if service.status == .enabled || service.status == .requiresApproval {
                try service.unregister()
            }
            print("NOHALLA_LOGIN_ITEM_RESET_OK")
            exit(EXIT_SUCCESS)
        } catch {
            fputs("No-halla could not disable launch at login: \(error.localizedDescription)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }

    var body: some Scene {
        WindowGroup(L10n.string("brand.name")) {
            MainWindowView()
                .environmentObject(appState)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 520, height: 600)

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
