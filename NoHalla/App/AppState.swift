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
        // C4: apply the persisted language from launch (D12), not only on Apply.
        L10n.current = loaded.language
    }

    /// Installs engine callbacks and starts the protection loop. The caller
    /// (AppDelegate) runs startup recovery and starts the watchdog first (FR-6).
    func start() {
        Task { [weak self] in
            guard let self = self else { return }
            await self.engine.setOnSnapshot { [weak self] snapshot in
                Task { @MainActor [weak self] in
                    self?.snapshot = snapshot
                }
            }
            let coordinator = self.notificationCoordinator
            await self.engine.setOnNotification { event in
                coordinator.post(event)
            }
            await self.engine.start()
        }
    }

    /// Forwards a user intent to the engine.
    func send(_ action: UserAction) {
        Task {
            await engine.handle(action)
            // R53: actions that mutate the engine config directly (addCurrentIP,
            // setProtectionEnabled) persist to disk but not to this bridge;
            // reload so the UI and onboarding finish() see the fresh config.
            switch action {
            case .addCurrentIP, .setProtectionEnabled, .resumeProtection:
                self.config = configStore.load()
            default:
                break
            }
        }
    }

    /// Persists a config change and notifies the engine (FR-27/37).
    func setConfig(_ newConfig: AppConfig) {
        config = newConfig
        // C4: keep localization in sync with the accepted config (Apply, reset).
        L10n.current = newConfig.language
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

    /// Mock bridge for SwiftUI previews (R61): an inert AppState (engine not
    /// started) with an injected snapshot/config so every UI state renders.
    static func preview(
        _ status: UIStatus,
        ipv4: String? = "203.0.113.5",
        ipv6: String? = nil,
        vpn: String? = "utun3",
        trusted: Bool = true,
        graceRemaining: Int? = nil,
        bypassUntil: Date? = nil,
        pauseUntil: Date? = nil,
        frozen: Set<String> = [],
        running: Set<String> = ["com.anthropic.claudefordesktop", "com.todesktop.230313mzl4w4u92"],
        trustedAddresses: [String] = ["203.0.113.5"],
        apps: [ProtectedApp] = [
            ProtectedApp(bundleID: "com.anthropic.claudefordesktop", name: "Claude", enabled: true),
            ProtectedApp(bundleID: "com.todesktop.230313mzl4w4u92", name: "Cursor", enabled: true),
            ProtectedApp(bundleID: "com.openai.chat", name: "ChatGPT", enabled: true)
        ]
    ) -> AppState {
        let state = AppState()
        var config = AppConfig.defaults
        config.onboardingCompleted = true
        config.trustedAddresses = trustedAddresses
        config.protectedApps = apps
        state.config = config
        let machineStatus: ProtectionStatus
        switch status {
        case .setup, .checking: machineStatus = .checking
        case .protected, .bypassing: machineStatus = .protected
        case .grace: machineStatus = .grace
        case .frozen: machineStatus = .frozen
        case .unknown: machineStatus = .unknown
        case .paused: machineStatus = .paused
        case .disabled: machineStatus = .disabled
        }
        state.snapshot = EngineSnapshot(
            status: machineStatus,
            uiStatus: status,
            currentIPv4: ipv4,
            currentIPv6: ipv6,
            vpnInterface: vpn,
            trusted: trusted,
            graceRemaining: graceRemaining,
            bypassUntil: bypassUntil,
            pauseUntil: pauseUntil,
            frozenBundleIDs: frozen,
            runningBundleIDs: running,
            lastCheck: Date()
        )
        return state
    }
}