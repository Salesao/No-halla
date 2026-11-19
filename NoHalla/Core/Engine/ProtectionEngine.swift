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
import Darwin
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
    /// R55: end a manual-resume bypass early and re-check immediately.
    case resumeProtection
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
    private var checkRetryTimer: DispatchSourceTimer?
    private var pendingChecks = 0
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
        // R5: honor a persisted disabled protection at startup (D27); do not
        // run checking → grace → freeze against a master switch that is off.
        if !config.protection.enabled {
            await applyEvent(.protectionDisabled)
        }
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
        checkRetryTimer?.cancel()
        checkRetryTimer = nil
        pendingChecks = 0
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

    /// Startup recovery of stale frozen records (FR-6/42). Resumes directly
    /// from the persisted records: the controller's in-memory tracking is empty
    /// after a restart, so each state.json entry is identity-checked (pid +
    /// start time) and sent SIGCONT here, then the state is cleared. A reused
    /// or vanished pid is never signaled. This startup clear is safe: it runs
    /// before the controller is active (no concurrent queue writes).
    /// Unconfirmed records (a pre-write whose STOP failed or whose rollback write
    /// did not reach disk) are treated safely: SIGCONT is a benign no-op on a
    /// still-running process, and an identity mismatch skips a reused pid — so a
    /// stale record never causes harm nor claims ownership of another's stop.
    /// D29 (spec-v2, owner-approved): identity-checked intent recovery — G1
    /// (FR-41/42) prioritized; the narrow G2 ownership window is an accepted
    /// residual risk (see DECISIONS.md D29 / README "Crash recovery").
    func recoverStaleFrozen() async {
        guard let state = stateStore.load(), !state.frozen.isEmpty else { return }
        AppLog.engine.info("Recovering \(state.frozen.count, privacy: .public) stale frozen records")
        for record in state.frozen {
            guard let start = ProcessEnumerator.startTime(of: record.pid),
                  start.sec == record.startTimeSec, start.usec == record.startTimeUsec else {
                continue
            }
            if kill(record.pid, SIGCONT) != 0 {
                AppLog.engine.warning("Recovery SIGCONT pid \(record.pid, privacy: .public) errno \(errno, privacy: .public)")
            }
        }
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
            requestImmediateCheck()
        case .addCurrentIP:
            await addCurrentIP()
        case .resumeProtection:
            // End the bypass window and force an immediate re-check (R55).
            await applyEvent(.bypassExpired)
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
        requestImmediateCheck()
    }

    // MARK: - Verification

    private func runCheck() async -> Bool {
        // VPN-tunnel mode: decide locally by the VPN interface — no external query.
        if config.protection.mode == .vpnInterface {
            return await runVPNInterfaceCheck()
        }
        // IP-whitelist mode: learn the current public IP via the endpoints.
        let online = monitor.isOnline
        guard let result = await verifier.check(config: config, online: online) else {
            // Throttled or backed off: keep current state.
            return false
        }
        lastCheck = Date()
        currentIPv4 = result.currentIPv4
        currentIPv6 = result.currentIPv6
        if case .verified = result.ipv6 { lastIPv6Verified = true } else { lastIPv6Verified = false }

        let verdict = composeVerdict(result)
        lastVerdictAllowed = (verdict == .allowed)

        // R2: an active manual-resume bypass suppresses freezing (FR-22). The
        // apps keep running until the window expires; only refresh IP/snapshot,
        // never feed a disallowed/unknown verdict into grace/freeze.
        if let bypassDeadline = bypassDeadline, bypassDeadline > Date() {
            publishSnapshot()
            return true
        }

        let event: ProtectionEvent
        switch verdict {
        case .allowed: event = .ipAllowed
        case .disallowed: event = .ipDisallowed
        case .unknown: event = .noQuorum
        }
        await applyEvent(event)
        return true
    }

    /// VPN-tunnel protection mode (owner-requested): the VPN interface presence
    /// is the trust signal — present → allowed, absent → disallowed. Purely local
    /// (getifaddrs), deterministic, no external query and no unknown state.
    private func runVPNInterfaceCheck() async -> Bool {
        let vpn = monitor.activeVPNInterface()
        lastCheck = Date()
        currentIPv4 = nil
        currentIPv6 = nil
        lastIPv6Verified = false
        lastVerdictAllowed = (vpn != nil)
        if let bypassDeadline = bypassDeadline, bypassDeadline > Date() {
            publishSnapshot()
            return true
        }
        await applyEvent(vpn != nil ? .ipAllowed : .ipDisallowed)
        return true
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
                // C2: no independent state write here. This effect always follows
                // .resumeAll, whose controller queue already persisted the emptied
                // journal; an actor-side clear could delete a newer record.
                frozenProcesses = []
            }
        }

        if machine.status == .unknown && previousStatus != .unknown {
            onNotification?(NotificationEvent(kind: .unknown, frozenCount: 0))
        }
        publishSnapshot()
        if needsCheck {
            requestImmediateCheck()
        }
    }

    // MARK: - Immediate check with retry (R6)

    /// Requests a check that must actually run. If the verifier is throttled or
    /// backed off (returns nil), retry after the 3 s minimum batch interval so a
    /// cancelled grace / bypass / pause never leaves a silent multi-second hole.
    /// R6: a counter, not a single flag — a request arriving while a batch is in
    /// flight increments the count and must survive that batch's completion.
    private func requestImmediateCheck() {
        pendingChecks += 1
        Task { await self.runPendingCheck() }
    }

    private func runPendingCheck() async {
        let ran = await runCheck()
        if ran {
            // One completed batch satisfies exactly one pending request. Only
            // stop retrying when no requests remain; otherwise re-plan so a
            // request made during the batch still gets a fresh verdict.
            pendingChecks = max(0, pendingChecks - 1)
            if pendingChecks == 0 {
                checkRetryTimer?.cancel()
                checkRetryTimer = nil
            } else {
                scheduleCheckRetry()
            }
        } else if pendingChecks > 0 {
            scheduleCheckRetry()
        }
    }

    private func scheduleCheckRetry() {
        checkRetryTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: timerQueue)
        timer.schedule(deadline: .now() + 3)
        timer.setEventHandler { [weak self] in
            Task { await self?.runPendingCheck() }
        }
        timer.resume()
        checkRetryTimer = timer
    }

    // MARK: - Freeze / resume (sequential on this actor)

    private func performFreeze(_ reason: FreezeReason) async {
        // C1: effect-boundary guard — never freeze while protection is inactive
        // (empty trusted list or master switch off), even if a stale effect arrives.
        guard !config.trustedAddresses.isEmpty, config.protection.enabled else { return }
        let apps = config.protectedApps.filter { $0.enabled }
        // User preference: minimize frozen apps' windows to the Dock so they do
        // not sit on screen looking hung. Window actions must precede SIGSTOP (a
        // frozen app cannot process them); prompt for Accessibility once (hide
        // fallback without it) and let the minimize settle before freezing.
        WindowMinimizer.promptAccessibilityOnce()
        for app in apps { WindowMinimizer.minimizeApp(bundleID: app.bundleID) }
        try? await Task.sleep(nanoseconds: 400_000_000)
        // C2: set metadata and configure durable per-process persistence BEFORE
        // the controller signals, so each stopped process is recorded first. The
        // controller's queue is the single journal owner; no engine save here.
        frozenSince = Date()
        freezeReason = reason
        configureControllerPersistence(reason: reason)
        let frozen = await controller.freeze(apps)
        frozenProcesses = frozen
        let count = Set(frozen.map { $0.bundleID }).count
        AppLog.engine.info("Froze \(count, privacy: .public) apps (reason \(reason.rawValue, privacy: .public))")
        onNotification?(NotificationEvent(kind: .frozen, frozenCount: count))
    }

    /// C2: give the concrete controller a persistence hook that writes the frozen
    /// set durably (synchronous atomic write) before each SIGSTOP. Metadata is
    /// captured by value so the hook is immutable once created; setPersist
    /// synchronizes installation (engine actor) with reads (controller queue).
    private func configureControllerPersistence(reason: FreezeReason?) {
        guard let processController = controller as? ProcessController else { return }
        let store = stateStore
        let since = frozenSince ?? Date()
        let ip = currentIPv4?.description
        let reasonValue = reason ?? freezeReason
        processController.setPersist { records in
            let state = PersistedState(
                schemaVersion: 1,
                frozen: records,
                frozenSince: since,
                reason: reasonValue,
                lastKnownIP: ip
            )
            do {
                try store.save(state)
                return true
            } catch {
                AppLog.engine.error("Failed to persist frozen state: \(error.localizedDescription, privacy: .public)")
                return false
            }
        }
    }

    private func performResumeAll() async {
        // C2: the controller persists the emptied journal on its queue; configure
        // the hook first and do not clear from the actor (avoids a stale overwrite).
        configureControllerPersistence(reason: freezeReason)
        let resumed = await controller.resumeAll()
        // User preference: restore minimized/hidden windows after SIGCONT.
        for record in resumed { WindowMinimizer.restoreApp(pid: record.pid) }
        frozenProcesses = []
        frozenSince = nil
        freezeReason = nil
        if !resumed.isEmpty {
            let count = Set(resumed.map { $0.bundleID }).count
            AppLog.engine.info("Resumed \(count, privacy: .public) apps")
            onNotification?(NotificationEvent(kind: .resumed, frozenCount: count))
        }
    }

    private func reconcile() async {
        // C1: never freeze new instances while the trusted list is empty (setup).
        guard machine.status == .frozen, !config.trustedAddresses.isEmpty else { return }
        let apps = config.protectedApps.filter { $0.enabled }
        // C2: controller queue owns the journal (persistNow after prune/freeze);
        // no engine save/clear here that could overwrite a newer record.
        configureControllerPersistence(reason: freezeReason)
        let frozen = await controller.reconcile(apps)
        frozenProcesses = frozen
        publishSnapshot()
    }

    // MARK: - Config

    private func configChanged(_ newConfig: AppConfig) async {
        let wasEnabled = config.protection.enabled
        config = newConfig
        startPeriodicTimer()
        // C1: an empty trusted list means INACTIVE protection (FR-10), not just a
        // different UI label. Resume our own processes, cancel any pending freeze
        // (grace/bypass/pause) and reset to checking so reconcile won't freeze new
        // instances. Adding an address later re-activates protection via a check.
        if newConfig.trustedAddresses.isEmpty {
            // C1: invalidate pending effects SYNCHRONOUSLY before the first await,
            // so an expired grace/bypass cannot issue a freeze during the resume
            // suspension. Reset the machine so stale grace/freeze effects are inert.
            cancelGrace()
            cancelBypass()
            cancelPause()
            machine = ProtectionStateMachine()
            // Resume our own processes; the controller queue orders this after any
            // already-issued freeze, so nothing is left paused in setup.
            await performResumeAll()
            await applyEvent(.appStarted(configValid: true))
            if !newConfig.protection.enabled {
                await applyEvent(.protectionDisabled)
            }
            publishSnapshot()
            return
        }
        if !newConfig.protection.enabled && wasEnabled {
            await applyEvent(.protectionDisabled)
        } else if newConfig.protection.enabled && !wasEnabled {
            await applyEvent(.protectionEnabled)
        } else {
            requestImmediateCheck()
        }
        publishSnapshot()
    }

    private func addCurrentIP() async {
        var ipv4 = currentIPv4
        var ipv6 = lastIPv6Verified ? currentIPv6 : nil
        // VPN-tunnel mode keeps no cached public IP (its checks are purely
        // local), and an IP-mode check may not have answered yet. "Add current
        // IP" is an explicit user request, so learn the address with a one-off
        // endpoint query instead of silently doing nothing. No verdict is fed
        // into the machine here: VPN mode stays local, IP mode re-checks below
        // with the updated trusted list.
        if ipv4 == nil && ipv6 == nil {
            if let result = await fetchCurrentIPOnDemand() {
                ipv4 = result.currentIPv4
                if case .verified = result.ipv6 { ipv6 = result.currentIPv6 }
            }
        }
        var changed = false
        if let ipv4 {
            let raw = ipv4.description
            if !config.trustedAddresses.contains(raw) {
                config.trustedAddresses.append(raw)
                changed = true
            }
        }
        if let ipv6 {
            let raw = ipv6.description
            if !config.trustedAddresses.contains(raw) {
                config.trustedAddresses.append(raw)
                changed = true
            }
        }
        if changed {
            try? configStore.save(config)
        }
        requestImmediateCheck()
    }

    /// One-off public-IP lookup for the explicit "Add current IP" action.
    /// Retries once past the verifier's 3 s minimum batch interval so a press
    /// right after a running or backed-off batch still resolves.
    private func fetchCurrentIPOnDemand() async -> IPVerificationResult? {
        if let result = await verifier.check(config: config, online: monitor.isOnline) {
            return result
        }
        try? await Task.sleep(nanoseconds: 3_100_000_000)
        return await verifier.check(config: config, online: monitor.isOnline)
    }

    // MARK: - Timers

    private func startPeriodicTimer() {
        periodicTimer?.cancel()
        let interval = TimeInterval(max(10, config.protection.checkIntervalSeconds))
        let timer = DispatchSource.makeTimerSource(queue: timerQueue)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in
            Task { _ = await self?.runCheck() }
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
        // R2: a bypass window must not coexist with a running grace countdown.
        cancelGrace()
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
        // Setup (empty trusted list) applies only to IP-whitelist mode; the
        // VPN-tunnel mode uses the interface presence, not a trusted IP list.
        if config.protection.mode == .ipWhitelist && config.trustedAddresses.isEmpty { return .setup }
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
            vpnInterface: monitor.activeVPNInterface(),
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