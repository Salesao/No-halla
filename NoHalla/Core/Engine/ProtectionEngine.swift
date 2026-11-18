//
//  ProtectionEngine.swift
//  NoHalla
//
//  Actor orchestrating the protection loop (implementation brief §5.2,
//  FR-7…14, FR-20…25). It wires NetworkMonitor events and a periodic timer into
//  IPVerifier, composes the IPv4/IPv6 trust lattice (spec D28), feeds the pure
//  ProtectionStateMachine and executes its effects: grace/bypass/pause timers,
//  sequential freeze/resume through ProcessControlling, atomic state persistence
//  and snapshot publication. `setup` and `bypassing` are derived UI statuses.
//
//  All freeze/resume operations run sequentially on this actor (FR-46). The
//  state machine itself performs no I/O.
//

import AppKit
import Foundation
import OSLog

/// Immutable view of engine state for the UI bridge. IPs are full here (the UI
/// shows them to the user); only logs mask them (FR-39).
struct EngineSnapshot {
    let status: ProtectionStatus
    let uiStatus: UIStatus
    let currentIPv4: String?
    let currentIPv6: String?
    let vpnInterface: String?
    let trusted: Bool
    let graceRemaining: Int?
    let bypassUntil: Date?
    let pauseUntil: Date?
    let frozenBundleIDs: Set<String>
    let runningBundleIDs: Set<String>
    let lastCheck: Date?
}

/// User intents forwarded from the UI bridge.
enum UserAction {
    case freezeNow
    case cancelGrace
    case resumeAll
    case pause(PauseDuration)
    case turnOnNow
    case retryCheck
    case addCurrentIP
    case setProtectionEnabled(Bool)
    case configChanged(AppConfig)
}

/// Notification intent; throttling lives in the coordinator (S2).
struct NotificationEvent {
    let kind: NotificationKind
    let frozenCount: Int
}

enum NotificationKind {
    case frozen
    case resumed
    case unknown
}

actor ProtectionEngine {
    // MARK: - Dependencies

    private let configStore: ConfigStore
    private let stateStore: StateStore
    private let controller: ProcessControlling
    private let verifier: IPVerifier
    private let monitor: NetworkMonitor

    // MARK: - Published callbacks

    var onSnapshot: ((EngineSnapshot) -> Void)?
    var onNotification: ((NotificationEvent) -> Void)?

    /// Wiring setters: cross-actor mutation of the callback properties goes
    /// through these methods (the UI bridge installs them before `start`).
    func setOnSnapshot(_ handler: ((EngineSnapshot) -> Void)?) {
        onSnapshot = handler
    }

    func setOnNotification(_ handler: ((NotificationEvent) -> Void)?) {
        onNotification = handler
    }

    // MARK: - State

    private var config: AppConfig
    private var machine = ProtectionStateMachine()
    private var frozenProcesses: [FrozenProcess] = []
    private var frozenSince: Date?
    private var freezeReason: FreezeReason?
    private var currentIPv4: IPAddress?
    private var currentIPv6: IPAddress?
    private var lastIPv6Verified = false
    private var lastCheck: Date?
    private var lastVerdictAllowed = false

    private var graceDeadline: Date?
    private var graceTotal: Int = 0
    private var lastGraceRemaining: Int?
    private var bypassDeadline: Date?
    private var pauseDeadline: Date?

    private let timerQueue = DispatchQueue(label: "dev.nohalla.NoHalla.engine-timers")
    private var graceTimer: DispatchSourceTimer?
    private var bypassTimer: DispatchSourceTimer?
    private var pauseTimer: DispatchSourceTimer?
    private var periodicTimer: DispatchSourceTimer?
    private var reconcileTimer: DispatchSourceTimer?
    private var wakeObserver: NSObjectProtocol?
    private var launchObserver: NSObjectProtocol?
    private var started = false

    init(
        configStore: ConfigStore,
        stateStore: StateStore,
        controller: ProcessControlling,
        verifier: IPVerifier,
        monitor: NetworkMonitor
    ) {
        self.configStore = configStore
        self.stateStore = stateStore
        self.controller = controller
        self.verifier = verifier
        self.monitor = monitor
        self.config = configStore.load()
    }

    // MARK: - Lifecycle

    func start() async {
        guard !started else { return }
        started = true
        config = configStore.load()

        monitor.onEvent = { [weak self] in
            Task { await self?.networkChanged() }
        }
        monitor.start()

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: nil
        ) { [weak self] _ in
            Task { await self?.wake() }
        }
        launchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: nil
        ) { [weak self] _ in
            Task { await self?.reconcile() }
        }

        startPeriodicTimer()
        startReconcileTimer()

        await applyEvent(.appStarted(configValid: true))
        publishSnapshot()
    }

    /// Resumes everything and clears persisted state (normal exit, FR-4/5).
    func stop() async {
        started = false
        monitor.onEvent = nil
        monitor.stop()
        cancelGrace()
        cancelBypass()
        cancelPause()
        periodicTimer?.cancel()
        periodicTimer = nil
        reconcileTimer?.cancel()
        reconcileTimer = nil
        if let wakeObserver = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        if let launchObserver = launchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(launchObserver)
        }
        wakeObserver = nil
        launchObserver = nil
        await performResumeAll()
    }

    /// Startup recovery of stale frozen records (FR-6/42). The controller
    /// verifies pid + start time before each SIGCONT.
    func recoverStaleFrozen() async {
        guard let state = stateStore.load(), !state.frozen.isEmpty else { return }
        AppLog.engine.info("Recovering \(state.frozen.count, privacy: .public) stale frozen records")
        _ = await controller.resumeAll()
        frozenProcesses = []
        try? stateStore.clear()
    }

    // MARK: - User actions

    func handle(_ action: UserAction) async {
        switch action {
        case .freezeNow:
            await applyEvent(.freezeNowTapped)
        case .cancelGrace:
            await applyEvent(.cancelTapped)
        case .resumeAll:
            await applyEvent(.resumeAllTapped)
        case .pause(let duration):
            await applyEvent(.pauseRequested(duration))
        case .turnOnNow:
            await applyEvent(.turnOnNowTapped)
        case .retryCheck:
            await runCheck()
        case .addCurrentIP:
            await addCurrentIP()
        case .setProtectionEnabled(let enabled):
            config.protection.enabled = enabled
            try? configStore.save(config)
            await applyEvent(enabled ? .protectionEnabled : .protectionDisabled)
        case .configChanged(let newConfig):
            await configChanged(newConfig)
        }
    }

    // MARK: - Network / wake

    private func networkChanged() async {
        await applyEvent(.networkChanged)
    }

    private func wake() async {
        // FR-12: recreate timers (no catch-up) and check immediately.
        startPeriodicTimer()
        startReconcileTimer()
        await runCheck()
    }

    // MARK: - Verification

    private func runCheck() async {
        let online = monitor.isOnline
        guard let result = await verifier.check(config: config, online: online) else {
            // Throttled or backed off: keep current state.
            return
        }
        lastCheck = Date()
        currentIPv4 = result.currentIPv4
        currentIPv6 = result.currentIPv6
        if case .verified = result.ipv6 { lastIPv6Verified = true } else { lastIPv6Verified = false }

        let verdict = composeVerdict(result)
        lastVerdictAllowed = (verdict == .allowed)
        let event: ProtectionEvent
        switch verdict {
        case .allowed: event = .ipAllowed
        case .disallowed: event = .ipDisallowed
        case .unknown: event = .noQuorum
        }
        await applyEvent(event)
    }

    private enum Verdict { case allowed, disallowed, unknown }

    /// Trust lattice (spec D28): any disallowed → disallowed; else any unknown →
    /// unknown; else allowed. A required-but-absent VPN tunnel forces disallowed.
    private func composeVerdict(_ result: IPVerificationResult) -> Verdict {
        if config.protection.requireVPNInterface && monitor.vpnInterfaceName() == nil {
            return .disallowed
        }
        let trusted = config.trustedAddresses.compactMap { CIDRRange($0) }

        func familyVerdict(_ family: FamilyResult) -> Verdict? {
            switch family {
            case .verified(let address):
                return trusted.contains { $0.contains(address) } ? .allowed : .disallowed
            case .noQuorum:
                return .unknown
            case .notApplicable:
                return nil
            }
        }

        let verdicts = [familyVerdict(result.ipv4), familyVerdict(result.ipv6)].compactMap { $0 }
        if verdicts.contains(.disallowed) { return .disallowed }
        if verdicts.contains(.unknown) { return .unknown }
        if verdicts.isEmpty { return .unknown }
        return .allowed
    }

    // MARK: - State machine bridge

    private func applyEvent(_ event: ProtectionEvent) async {
        let previousStatus = machine.status
        let environment = ProtectionStateMachine.Environment(
            freezeWhenUnknown: config.protection.freezeWhenUnknown,
            graceSeconds: config.protection.graceSeconds,
            bypassMinutes: config.protection.manualResumeBypassMinutes,
            trustedEmpty: config.trustedAddresses.isEmpty
        )
        let effects = machine.reduce(event, env: environment)

        var needsCheck = false
        for effect in effects {
            switch effect {
            case .startGrace(let seconds):
                startGrace(seconds)
            case .cancelGrace:
                cancelGrace()
            case .freeze(let reason):
                await performFreeze(reason)
            case .resumeAll:
                await performResumeAll()
            case .startBypass(let minutes):
                startBypass(minutes)
            case .cancelBypass:
                cancelBypass()
            case .startPause(let duration):
                startPause(duration)
            case .cancelPause:
                cancelPause()
            case .immediateCheck:
                needsCheck = true
            case .clearFrozenState:
                frozenProcesses = []
                try? stateStore.clear()
            }
        }

        if machine.status == .unknown && previousStatus != .unknown {
            onNotification?(NotificationEvent(kind: .unknown, frozenCount: 0))
        }
        publishSnapshot()
        if needsCheck {
            Task { await self.runCheck() }
        }
    }

    // MARK: - Freeze / resume (sequential on this actor)

    private func performFreeze(_ reason: FreezeReason) async {
        let apps = config.protectedApps.filter { $0.enabled }
        let frozen = await controller.freeze(apps)
        frozenProcesses = frozen
        frozenSince = Date()
        freezeReason = reason
        let state = PersistedState(
            schemaVersion: 1,
            frozen: frozen,
            frozenSince: frozenSince,
            reason: reason,
            lastKnownIP: currentIPv4?.description
        )
        try? stateStore.save(state)
        let count = Set(frozen.map { $0.bundleID }).count
        AppLog.engine.info("Froze \(count, privacy: .public) apps (reason \(reason.rawValue, privacy: .public))")
        onNotification?(NotificationEvent(kind: .frozen, frozenCount: count))
    }

    private func performResumeAll() async {
        let resumed = await controller.resumeAll()
        frozenProcesses = []
        frozenSince = nil
        freezeReason = nil
        try? stateStore.clear()
        if !resumed.isEmpty {
            let count = Set(resumed.map { $0.bundleID }).count
            AppLog.engine.info("Resumed \(count, privacy: .public) apps")
            onNotification?(NotificationEvent(kind: .resumed, frozenCount: count))
        }
    }

    private func reconcile() async {
        guard machine.status == .frozen else { return }
        let apps = config.protectedApps.filter { $0.enabled }
        let frozen = await controller.reconcile(apps)
        frozenProcesses = frozen
        if frozen.isEmpty {
            try? stateStore.clear()
        } else {
            let state = PersistedState(
                schemaVersion: 1,
                frozen: frozen,
                frozenSince: frozenSince,
                reason: freezeReason,
                lastKnownIP: currentIPv4?.description
            )
            try? stateStore.save(state)
        }
        publishSnapshot()
    }

    // MARK: - Config

    private func configChanged(_ newConfig: AppConfig) async {
        let wasEnabled = config.protection.enabled
        config = newConfig
        startPeriodicTimer()
        if !newConfig.protection.enabled && wasEnabled {
            await applyEvent(.protectionDisabled)
        } else if newConfig.protection.enabled && !wasEnabled {
            await applyEvent(.protectionEnabled)
        } else {
            await runCheck()
        }
        publishSnapshot()
    }

    private func addCurrentIP() async {
        var changed = false
        if let ipv4 = currentIPv4 {
            let raw = ipv4.description
            if !config.trustedAddresses.contains(raw) {
                config.trustedAddresses.append(raw)
                changed = true
            }
        }
        if lastIPv6Verified, let ipv6 = currentIPv6 {
            let raw = ipv6.description
            if !config.trustedAddresses.contains(raw) {
                config.trustedAddresses.append(raw)
                changed = true
            }
        }
        if changed {
            try? configStore.save(config)
        }
        await runCheck()
    }

    // MARK: - Timers

    private func startPeriodicTimer() {
        periodicTimer?.cancel()
        let interval = TimeInterval(max(10, config.protection.checkIntervalSeconds))
        let timer = DispatchSource.makeTimerSource(queue: timerQueue)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in
            Task { await self?.runCheck() }
        }
        timer.resume()
        periodicTimer = timer
    }

    private func startReconcileTimer() {
        reconcileTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: timerQueue)
        timer.schedule(deadline: .now() + 5, repeating: 5)
        timer.setEventHandler { [weak self] in
            Task { await self?.reconcile() }
        }
        timer.resume()
        reconcileTimer = timer
    }

    private func startGrace(_ seconds: Int) {
        cancelGrace()
        graceTotal = seconds
        guard seconds > 0 else {
            Task { await self.applyEvent(.graceExpired) }
            return
        }
        graceDeadline = Date().addingTimeInterval(TimeInterval(seconds))
        lastGraceRemaining = seconds
        let timer = DispatchSource.makeTimerSource(queue: timerQueue)
        timer.schedule(deadline: .now(), repeating: 0.1)
        timer.setEventHandler { [weak self] in
            Task { await self?.graceTick() }
        }
        timer.resume()
        graceTimer = timer
    }

    private func graceTick() async {
        guard let deadline = graceDeadline else { return }
        let remaining = deadline.timeIntervalSinceNow
        if remaining <= 0 {
            cancelGrace()
            await applyEvent(.graceExpired)
        } else {
            let whole = Int(ceil(remaining))
            if whole != lastGraceRemaining {
                lastGraceRemaining = whole
                publishSnapshot()
            }
        }
    }

    private func cancelGrace() {
        graceTimer?.cancel()
        graceTimer = nil
        graceDeadline = nil
        lastGraceRemaining = nil
    }

    private func startBypass(_ minutes: Int) {
        cancelBypass()
        guard minutes > 0 else {
            Task { await self.applyEvent(.bypassExpired) }
            return
        }
        bypassDeadline = Date().addingTimeInterval(TimeInterval(minutes * 60))
        let timer = DispatchSource.makeTimerSource(queue: timerQueue)
        timer.schedule(deadline: .now() + TimeInterval(minutes * 60))
        timer.setEventHandler { [weak self] in
            Task { await self?.bypassFired() }
        }
        timer.resume()
        bypassTimer = timer
    }

    private func bypassFired() async {
        cancelBypass()
        await applyEvent(.bypassExpired)
    }

    private func cancelBypass() {
        bypassTimer?.cancel()
        bypassTimer = nil
        bypassDeadline = nil
    }

    private func startPause(_ duration: PauseDuration) {
        cancelPause()
        let seconds: Int?
        switch duration {
        case .minutes15: seconds = 15 * 60
        case .hour1: seconds = 60 * 60
        case .untilRelaunch: seconds = nil
        }
        guard let seconds = seconds else {
            // Until relaunch: no expiry timer.
            pauseDeadline = nil
            return
        }
        pauseDeadline = Date().addingTimeInterval(TimeInterval(seconds))
        let timer = DispatchSource.makeTimerSource(queue: timerQueue)
        timer.schedule(deadline: .now() + TimeInterval(seconds))
        timer.setEventHandler { [weak self] in
            Task { await self?.pauseFired() }
        }
        timer.resume()
        pauseTimer = timer
    }

    private func pauseFired() async {
        cancelPause()
        await applyEvent(.pauseExpired)
    }

    private func cancelPause() {
        pauseTimer?.cancel()
        pauseTimer = nil
        pauseDeadline = nil
    }

    // MARK: - Snapshot

    private func deriveUIStatus() -> UIStatus {
        if config.trustedAddresses.isEmpty { return .setup }
        if let bypassDeadline = bypassDeadline, bypassDeadline > Date() { return .bypassing }
        switch machine.status {
        case .initializing, .checking: return .checking
        case .protected: return .protected
        case .grace: return .grace
        case .frozen: return .frozen
        case .unknown: return .unknown
        case .paused: return .paused
        case .disabled: return .disabled
        }
    }

    private func graceRemaining() -> Int? {
        guard let deadline = graceDeadline else { return nil }
        return max(0, Int(ceil(deadline.timeIntervalSinceNow)))
    }

    private func runningBundleIDs() -> Set<String> {
        let protectedIDs = Set(config.protectedApps.map { $0.bundleID })
        let running = NSWorkspace.shared.runningApplications
        return Set(running.compactMap { $0.bundleIdentifier }.filter { protectedIDs.contains($0) })
    }

    private func publishSnapshot() {
        let snapshot = EngineSnapshot(
            status: machine.status,
            uiStatus: deriveUIStatus(),
            currentIPv4: currentIPv4?.description,
            currentIPv6: currentIPv6?.description,
            vpnInterface: monitor.vpnInterfaceName(),
            trusted: lastVerdictAllowed,
            graceRemaining: graceRemaining(),
            bypassUntil: bypassDeadline,
            pauseUntil: pauseDeadline,
            frozenBundleIDs: Set(frozenProcesses.map { $0.bundleID }),
            runningBundleIDs: runningBundleIDs(),
            lastCheck: lastCheck
        )
        onSnapshot?(snapshot)
    }
}