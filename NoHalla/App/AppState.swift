//
//  AppState.swift
//  NoHalla
//
//  MainActor UI bridge (spec D7). Owns the engine and stores, republishes engine
//  snapshots as observable state and forwards user intents back to the engine.
//  S1 wires a LoggingProcessController seam; S2 replaces it with the real
//  ProcessController and connects notifications.
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

    var uiStatus: UIStatus { snapshot.uiStatus }

    init() {
        let configStore = ConfigStore()
        let stateStore = StateStore()
        let loaded = configStore.load()
        // S1 seam: logs intents only. Replaced by ProcessController in s2-wiring.
        let controller = LoggingProcessController()
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
    }

    /// Installs engine callbacks and starts the protection loop.
    func start() {
        Task {
            await engine.setOnSnapshot { [weak self] snapshot in
                Task { @MainActor in
                    self?.snapshot = snapshot
                }
            }
            await engine.setOnNotification { _ in
                // S2 wiring routes this to NotificationCoordinator.
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
        Task { await engine.handle(.configChanged(newConfig)) }
    }

    /// S2 wiring connects this to NotificationCoordinator.requestPermission.
    func requestNotificationPermission() {
        // Placeholder until s2-wiring installs the coordinator.
    }
}