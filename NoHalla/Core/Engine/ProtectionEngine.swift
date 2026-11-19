//
//  ProtectionEngine.swift
//  NoHalla
//
//  Actor orchestrating the protection loop (implementation brief §5.2,
//  FR-7…14, FR-20…25). It wires NetworkMonitor events and a periodic timer into
//  IPVerifier, composes the IPv4 trust verdict (spec D28), feeds the pure
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
    let vpnInterface: String?
    let trusted: Bool
    let graceRemaining: Int?
    let bypassUntil: Date?
    let pauseUntil: Date?
    let frozenBundleIDs: Set<String>
    let runningBundleIDs: Set<String>
    let lastCheck: Date?
    /// True while a user-requested IP refresh is still pending (the verifier
    /// may be throttled/backed off), so the network card can show progress.
    let isRefreshing: Bool
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
    /// D35: fetch the public IPv4 for display (onboarding "trust this IP")
    /// without feeding a verdict into the state machine.
    case detectCurrentIP
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
    /// D32: publishes the block/allow state the root helper applies to hosts.
    private let domainGuard: DomainGuardWriting

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
    /// Every address observed by the last batch, used by "Add current IP" so
    /// split-tunnel hosts can trust all of their egress addresses at once.
    private var lastIPv4Answers: [IPAddress] = []
    private var lastCheck: Date?
    private var lastVerdictAllowed = false
    /// True from an explicit refresh tap until the next check actually runs.
    private var manualRefreshInFlight = false

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
        monitor: NetworkMonitor,
        domainGuard: DomainGuardWriting? = nil
    ) {
        self.configStore = configStore
        self.stateStore = stateStore
        self.controller = controller
        self.verifier = verifier
        self.monitor = monitor
        self.domainGuard = domainGuard ?? DomainGuardWriter(directory: configStore.directoryURL)
        self.config = configStore.load()
    }

    /// D36: "setup" means the IP-whitelist mode has no trusted address yet.
    /// VPN-tunnel mode is configured by the interface itself and must keep
    /// protecting without any IP entry.
    private var setupIncomplete: Bool {
        config.protection.mode == .ipWhitelist && config.trustedAddresses.isEmpty
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
        // D32: a graceful quit must not leave sites blocked. A crash keeps the
        // last state (fail-closed) until the next launch republishes it.
        domainGuard.update(active: false, domains: config.effectiveDomainBlocklist)
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
    /// residual risk (see project memory D29 / README "Crash recovery").
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
            // Visible feedback: the request may wait behind the 3 s throttle or
            // endpoint backoff, so publish the in-progress state immediately.
            manualRefreshInFlight = true
            requestImmediateCheck()
            publishSnapshot()
        case .addCurrentIP:
            await addCurrentIP()
        case .detectCurrentIP:
            await detectCurrentIP()
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
        manualRefreshInFlight = false
        currentIPv4 = result.currentIPv4
        lastIPv4Answers = result.allIPv4

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
        manualRefreshInFlight = false
        // D35: keep any explicitly detected public IPv4 for display. The VPN
        // verdict is local, so the address is informational only — but
        // onboarding polls it right after a detect, and clearing it here made
        // the "trust this IP" step flicker back to "—".
        lastVerdictAllowed = (vpn != nil)
        if let bypassDeadline = bypassDeadline, bypassDeadline > Date() {
            publishSnapshot()
            return true
        }
        await applyEvent(vpn != nil ? .ipAllowed : .ipDisallowed)
        return true
    }

    private enum Verdict { case allowed, disallowed, unknown }

    /// Trust verdict (spec D28): every observed IPv4 address must be trusted;
    /// any untrusted observation → disallowed, no answers → unknown. A
    /// required-but-absent VPN tunnel forces disallowed.
    private func composeVerdict(_ result: IPVerificationResult) -> Verdict {
        if config.protection.requireVPNInterface && monitor.vpnInterfaceName() == nil {
            return .disallowed
        }
        switch result.ipv4 {
        case .answers(let addresses):
            guard !addresses.isEmpty else { return .unknown }
            let trusted = config.trustedAddresses.compactMap { CIDRRange($0) }
            let allTrusted = addresses.allSatisfy { address in
                trusted.contains { $0.contains(address) }
            }
            return allTrusted ? .allowed : .disallowed
        case .noQuorum:
            return .unknown
        }
    }

    // MARK: - State machine bridge

    private func applyEvent(_ event: ProtectionEvent) async {
        let previousStatus = machine.status
        let environment = ProtectionStateMachine.Environment(
            freezeWhenUnknown: config.protection.freezeWhenUnknown,
            graceSeconds: config.protection.graceSeconds,
            bypassMinutes: config.protection.manualResumeBypassMinutes,
            trustedEmpty: setupIncomplete
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
        // (setup in IP mode or master switch off), even if a stale effect arrives.
        guard config.protection.enabled, !setupIncomplete else { return }
        let apps = config.protectedApps.filter { $0.enabled }
        // User preference: minimize frozen apps' windows to the Dock so they do
        // not sit on screen looking hung. Window actions must precede SIGSTOP (a
        // frozen app cannot process them); prompt for Accessibility once (hide
        // fallback without it) and let the minimize settle before freezing.
        // D30: an app frozen only at agent-terminal scope keeps its window —
        // the app itself is never stopped.
        WindowMinimizer.promptAccessibilityOnce()
        for app in apps where app.freezeScope == .app { WindowMinimizer.minimizeApp(bundleID: app.bundleID) }
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
        guard machine.status == .frozen, !setupIncomplete else { return }
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
        // D31: a trusted-list edit restarts protection from the new
        // configuration instead of waiting for the next timer tick.
        let trustedListChanged = newConfig.trustedAddresses != config.trustedAddresses
        config = newConfig
        startPeriodicTimer()
        // C1: an empty trusted list means INACTIVE protection (FR-10), not just a
        // different UI label. Resume our own processes, cancel any pending freeze
        // (grace/bypass/pause) and reset to checking so reconcile won't freeze new
        // instances. Adding an address later re-activates protection via a check.
        if newConfig.protection.mode == .ipWhitelist && newConfig.trustedAddresses.isEmpty {
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
        if trustedListChanged {
            // D31: drop grace/bypass, re-check now, keep a frozen set until the
            // verdict. The empty-list case above already reset everything.
            await applyEvent(.trustedListChanged)
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

    /// D35: explicit detection for the UI (onboarding "trust this IP"). It never
    /// feeds a verdict into the machine: IP mode's periodic check still decides
    /// trust, and VPN mode remains local. Only the displayed address changes.
    private func detectCurrentIP() async {
        manualRefreshInFlight = true
        publishSnapshot()
        if let result = await fetchCurrentIPOnDemand() {
            currentIPv4 = result.currentIPv4
            lastIPv4Answers = result.allIPv4
        }
        manualRefreshInFlight = false
        publishSnapshot()
    }

    private func addCurrentIP() async {
        var addresses = lastIPv4Answers
        // VPN-tunnel mode keeps no cached public IP (its checks are purely
        // local), and an IP-mode check may not have answered yet. "Add current
        // IP" is an explicit user request, so learn the address with a one-off
        // endpoint query instead of silently doing nothing. No verdict is fed
        // into the machine here: VPN mode stays local, IP mode re-checks below
        // with the updated trusted list.
        if addresses.isEmpty {
            if let result = await fetchCurrentIPOnDemand() {
                addresses = result.allIPv4
            }
        }
        var changed = false
        // Split-tunnel hosts can expose several current public IPs; trust every
        // one the last batch observed so the next check does not fail on a
        // legitimate egress address that simply was not added yet.
        for address in addresses {
            let raw = address.description
            if !config.trustedAddresses.contains(raw) {
                config.trustedAddresses.append(raw)
                changed = true
            }
        }
        if changed {
            try? configStore.save(config)
            // D31: the list just changed, so restart evaluation immediately.
            await applyEvent(.trustedListChanged)
        } else {
            requestImmediateCheck()
        }
    }

    /// One-off public-IP lookup for the explicit "Add current IP" action.
    /// Retries once past the verifier's 3 s minimum batch interval so a press
    /// right after a running or backed-off batch still resolves.
    private func fetchCurrentIPOnDemand() async -> IPVerificationResult? {
        if let result = await verifier.check(config: config, online: monitor.isOnline, force: true) {
            return result
        }
        // Only an in-flight batch can refuse a forced request; wait it out once.
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        return await verifier.check(config: config, online: monitor.isOnline, force: true)
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

    /// D32: the guard blocks whenever protection is on, whatever the IP
    /// verdict. Only an explicit pause or the master switch releases it.
    private var domainGuardActive: Bool {
        guard config.protection.enabled, !setupIncomplete else { return false }
        switch machine.status {
        case .paused, .disabled:
            return false
        case .initializing, .checking, .grace, .frozen, .unknown, .protected:
            return true
        }
    }

    private func publishSnapshot() {
        // D32: block while protection is on, independently of IP trust. Pause
        // and the master switch are explicit user overrides; setup (empty
        // trusted list) is inactive (FR-10).
        domainGuard.update(active: domainGuardActive, domains: config.effectiveDomainBlocklist)
        let snapshot = EngineSnapshot(
            status: machine.status,
            uiStatus: deriveUIStatus(),
            currentIPv4: currentIPv4?.description,
            vpnInterface: monitor.activeVPNInterface(),
            trusted: lastVerdictAllowed,
            graceRemaining: graceRemaining(),
            bypassUntil: bypassDeadline,
            pauseUntil: pauseDeadline,
            frozenBundleIDs: Set(frozenProcesses.map { $0.bundleID }),
            runningBundleIDs: runningBundleIDs(),
            lastCheck: lastCheck,
            isRefreshing: manualRefreshInFlight
        )
        onSnapshot?(snapshot)
    }
}