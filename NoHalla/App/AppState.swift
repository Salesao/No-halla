//
//  AppState.swift
//  NoHalla
//
//  MainActor UI bridge (spec D7). Owns the engine, stores, watchdog launcher and
//  notification coordinator; republishes engine snapshots as observable state
//  and forwards user intents back to the engine. S2 wiring injects the real
//  ProcessController (watchdog pid provider reads the launcher) and routes
//  engine notifications to the coordinator.
//

import AppKit
import Combine
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var snapshot: EngineSnapshot
    @Published var config: AppConfig
    @Published var corruptConfigBanner: Bool
    @Published var notificationsDenied: Bool = false
    @Published var launchAtLoginError: String?

    let engine: ProtectionEngine
    let configStore: ConfigStore
    let stateStore: StateStore
    let watchdogLauncher: WatchdogLauncher
    let notificationCoordinator: NotificationCoordinator

    var uiStatus: UIStatus { snapshot.uiStatus }

    init() {
        let configStore = ConfigStore()
        let stateStore = StateStore()
        let watchdogLauncher = WatchdogLauncher()
        let notificationCoordinator = NotificationCoordinator()
        let loaded = configStore.load()
        // Real process control; the safety guard excludes the watchdog by pid.
        let controller = ProcessController(watchdogPIDProvider: { watchdogLauncher.watchdogPID })
        let verifier = IPVerifier()
        let monitor = NetworkMonitor()
        let engine = ProtectionEngine(
            configStore: configStore,
            stateStore: stateStore,
            controller: controller,
            verifier: verifier,
            monitor: monitor
        )
        self.configStore = configStore
        self.stateStore = stateStore
        self.watchdogLauncher = watchdogLauncher
        self.notificationCoordinator = notificationCoordinator
        self.engine = engine
        self.config = loaded
        self.corruptConfigBanner = configStore.lastLoadWasCorrupt
        self.snapshot = EngineSnapshot(
            status: .initializing,
            uiStatus: loaded.trustedAddresses.isEmpty ? .setup : .checking,
            currentIPv4: nil,
            currentIPv6: nil,
            vpnInterface: nil,
            trusted: false,
            graceRemaining: nil,
            bypassUntil: nil,
            pauseUntil: nil,
            frozenBundleIDs: [],
            runningBundleIDs: [],
            lastCheck: nil
        )
        notificationCoordinator.setEnabled(loaded.notifications)
        notificationCoordinator.onResumeAllAction = { [weak self] in
            self?.send(.resumeAll)
        }
    }

    /// Installs engine callbacks and starts the protection loop. The caller
    /// (AppDelegate) runs startup recovery and starts the watchdog first (FR-6).
    func start() {
        Task {
            await engine.setOnSnapshot { [weak self] snapshot in
                Task { @MainActor in
                    self?.snapshot = snapshot
                }
            }
            let coordinator = notificationCoordinator
            await engine.setOnNotification { event in
                coordinator.post(event)
            }
            await engine.start()
        }
    }

    /// Forwards a user intent to the engine.
    func send(_ action: UserAction) {
        Task { await engine.handle(action) }
    }

    /// Persists a config change and notifies the engine (FR-27/37).
    func setConfig(_ newConfig: AppConfig) {
        config = newConfig
        do {
            try configStore.save(newConfig)
        } catch {
            AppLog.ui.error("Failed to save config: \(error.localizedDescription, privacy: .public)")
        }
        notificationCoordinator.setEnabled(newConfig.notifications)
        Task { await engine.handle(.configChanged(newConfig)) }
    }

    /// Requests notification permission (after onboarding, FR-29) and reflects
    /// a denied status for the General settings banner.
    func requestNotificationPermission() {
        Task {
            await notificationCoordinator.requestPermission()
            let denied = await notificationCoordinator.isPermissionDenied()
            notificationsDenied = denied
        }
    }
}