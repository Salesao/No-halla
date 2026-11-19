//
//  ProcessController.swift
//  NoHalla
//
//  Real freeze/resume implementation (implementation brief §8.4, FR-15…24,
//  FR-45/46). Signals are SIGSTOP/SIGCONT from Darwin. Before EVERY signal the
//  pid + process start time are verified (PID-reuse guard, Review Focus 1);
//  the safety deny-list, uid and bundle-path prefix are enforced (Review Focus
//  2). Operations are idempotent (a tracked Set of pids) and serialized on a
//  private serial queue (FR-46). ESRCH drops the pid from tracking; EPERM is
//  skipped and logged. reconcile adds new instances/helpers and removes
//  finished processes (FR-24). Each method returns the current frozen list for
//  StateStore persistence.
//

import AppKit
import Darwin
import Foundation
import OSLog

/// Thread safety: all mutable state is confined to `queue` (the frozen journal
/// and journalNeedsSync) or guarded by `persistLock` (the persist hook); the
/// async methods bridge onto `queue`. Hence `@unchecked Sendable` is sound and
/// allows the queue closures to capture self without Sendable warnings.
final class ProcessController: ProcessControlling, @unchecked Sendable {
    private let queue = DispatchQueue(label: "dev.nohalla.NoHalla.process-controller")
    private let selfPID: Int32
    private let watchdogPIDProvider: () -> Int32?
    /// Tracked frozen processes keyed by pid (idempotence + identity records).
    private var frozen: [Int32: FrozenProcess] = [:]
    /// C2: set when a rollback write failed; the journal may hold a stale record
    /// until the next successful persistNow reconciles it. Queue-confined.
    private var journalNeedsSync = false
    /// C2: durable persistence hook. The controller's serial queue is the single
    /// serialized owner of the frozen journal; the hook is set by the engine
    /// (actor) and read on the queue, so access is lock-synchronized. Metadata is
    /// captured by value inside the hook (immutable once created).
    private var persistHandler: (([FrozenProcess]) -> Bool)?
    private let persistLock = NSLock()

    /// C2: install the journal writer (thread-safe; called from the engine actor).
    func setPersist(_ handler: @escaping ([FrozenProcess]) -> Bool) {
        persistLock.lock()
        persistHandler = handler
        persistLock.unlock()
    }

    init(selfPID: Int32 = getpid(), watchdogPIDProvider: @escaping () -> Int32?) {
        self.selfPID = selfPID
        self.watchdogPIDProvider = watchdogPIDProvider
    }

    // MARK: - ProcessControlling (async bridge onto the serial queue)

    func freeze(_ apps: [ProtectedApp]) async -> [FrozenProcess] {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.freezeSync(apps))
            }
        }
    }

    func resumeAll() async -> [FrozenProcess] {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.resumeAllSync())
            }
        }
    }

    func reconcile(_ apps: [ProtectedApp]) async -> [FrozenProcess] {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.reconcileSync(apps))
            }
        }
    }

    func currentFrozen() async -> [FrozenProcess] {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: Array(self.frozen.values))
            }
        }
    }

    // MARK: - Freeze

    private func freezeSync(_ apps: [ProtectedApp]) -> [FrozenProcess] {
        for app in apps where app.enabled {
            for target in targets(for: app) {
                freezeOne(
                    pid: target.pid,
                    bundleID: app.bundleID,
                    bundlePath: target.bundlePath,
                    terminalDescendant: target.terminalDescendant
                )
            }
        }
        return Array(frozen.values)
    }

    private func freezeOne(pid: Int32, bundleID: String, bundlePath: String, terminalDescendant: Bool) {
        guard pid > 0, frozen[pid] == nil else { return }

        let path = ProcessEnumerator.path(of: pid) ?? ""
        if SafetyGuard.isDenied(pid: pid, path: path, bundleID: bundleID, selfPID: selfPID, watchdogPID: watchdogPIDProvider()) {
            AppLog.process.info("Skip denied pid \(pid, privacy: .public)")
            return
        }
        // D30: a terminal descendant is authorized by its live process-tree edge
        // from an instance inside the selected .app, so its executable path is
        // intentionally outside the bundle (`/bin/zsh`, `~/.local/bin/claude`).
        // Everything else still must live inside the bundle (FR-45). The uid
        // check above and the start-time guard below apply to both.
        if !terminalDescendant {
            guard SafetyGuard.isInsideBundle(path: path, bundlePath: bundlePath) else {
                AppLog.process.info("Skip pid outside bundle \(pid, privacy: .public)")
                return
            }
        }
        // Identity snapshot taken before the signal (PID-reuse guard).
        guard let start = ProcessEnumerator.startTime(of: pid) else { return }

        // C2: record the process durably BEFORE stopping it, so a crash between
        // SIGSTOP and publication still leaves it recoverable by the watchdog /
        // next launch. If the record cannot be persisted, do not stop it. A crash
        // after this write but before the signal leaves an "incomplete intent":
        // recovery sends an identity-checked SIGCONT, which is a benign no-op on
        // a still-running process — never a claim of owning someone else's stop.
        let record = FrozenProcess(
            pid: pid,
            startTimeSec: start.sec,
            startTimeUsec: start.usec,
            bundleID: bundleID,
            path: path,
            terminalDescendant: terminalDescendant
        )
        frozen[pid] = record
        guard persistNow() else {
            frozen.removeValue(forKey: pid)
            AppLog.process.warning("Persist failed; not freezing pid \(pid, privacy: .public)")
            return
        }
        // C2: re-verify identity immediately before the signal, after the file
        // I/O above (the pid could have been reused during the write).
        guard let current = ProcessEnumerator.startTime(of: pid),
              current.sec == start.sec, current.usec == start.usec else {
            rollbackRecord(pid, context: "Identity changed before SIGSTOP; not freezing")
            return
        }
        if kill(pid, SIGSTOP) == 0 {
            AppLog.process.info("Froze pid \(pid, privacy: .public)")
        } else {
            // C2: a failed STOP (e.g. EPERM) means the process is NOT stopped;
            // roll back the pre-write in memory and journal so it is not treated
            // as our frozen process nor skipped on later attempts.
            rollbackRecord(pid, context: "SIGSTOP failed (errno \(errno)); not frozen")
        }
    }

    /// C2: remove a pre-written record and persist the rollback. If the journal
    /// write fails, mark it for re-sync (the next operation reconciles) and log
    /// the true status — never claim "rolled back" when the disk kept the stale
    /// record. An unconfirmed record is safe at recovery: identity-checked
    /// SIGCONT is a benign no-op on a still-running process, and a reused pid is
    /// skipped — never a claim of owning someone else's stop.
    private func rollbackRecord(_ pid: Int32, context: String) {
        frozen.removeValue(forKey: pid)
        if persistNow() {
            AppLog.process.warning("\(context, privacy: .public) pid \(pid, privacy: .public); rolled back")
        } else {
            journalNeedsSync = true
            AppLog.process.warning("\(context, privacy: .public) pid \(pid, privacy: .public); rollback NOT persisted, journal needs sync")
        }
    }

    // MARK: - Resume

    private func resumeAllSync() -> [FrozenProcess] {
        let snapshot = frozen
        frozen.removeAll()
        var resumed: [FrozenProcess] = []
        for (pid, record) in snapshot {
            // Identity check before SIGCONT; a reused pid is never signaled.
            guard let start = ProcessEnumerator.startTime(of: pid),
                  start.sec == record.startTimeSec, start.usec == record.startTimeUsec else {
                continue
            }
            if kill(pid, SIGCONT) == 0 {
                resumed.append(record)
                AppLog.process.info("Resumed pid \(pid, privacy: .public)")
            } else {
                handleSignalError(errno, pid: pid, action: "SIGCONT")
            }
        }
        _ = persistNow()
        return resumed
    }

    // MARK: - Reconcile (FR-24)

    private func reconcileSync(_ apps: [ProtectedApp]) -> [FrozenProcess] {
        let enabledApps = apps.filter { $0.enabled }
        let scopeByBundleID = Dictionary(
            enabledApps.map { ($0.bundleID, $0.freezeScope) },
            uniquingKeysWith: { first, _ in first }
        )
        // Resume records the current scope no longer covers (FR-24, D30):
        // removed/disabled apps entirely; at `.app` scope the agent-session
        // records; at `.agentTerminals` the app's own processes, so switching
        // to agent-only actually lets the app run again.
        for pid in Array(frozen.keys) {
            guard let record = frozen[pid] else { continue }
            let revoked: Bool
            switch scopeByBundleID[record.bundleID] {
            case .none:
                revoked = true
            case .some(.app):
                revoked = record.terminalDescendant
            case .some(.agentTerminals):
                revoked = !record.terminalDescendant
            }
            if revoked {
                resumeOne(pid: pid, record: record)
                frozen.removeValue(forKey: pid)
            }
        }
        // Drop processes that exited or whose pid was reused since freezing.
        for pid in Array(frozen.keys) {
            guard let record = frozen[pid] else { continue }
            guard let start = ProcessEnumerator.startTime(of: pid),
                  start.sec == record.startTimeSec, start.usec == record.startTimeUsec else {
                frozen.removeValue(forKey: pid)
                continue
            }
        }
        // Freeze newly launched instances, helpers and (D30) terminal
        // descendants of enabled apps.
        for app in enabledApps {
            for target in targets(for: app) {
                freezeOne(
                    pid: target.pid,
                    bundleID: app.bundleID,
                    bundlePath: target.bundlePath,
                    terminalDescendant: target.terminalDescendant
                )
            }
        }
        _ = persistNow()
        return Array(frozen.values)
    }

    /// Identity-checked SIGCONT for one tracked record (PID-reuse guard).
    private func resumeOne(pid: Int32, record: FrozenProcess) {
        guard let start = ProcessEnumerator.startTime(of: pid),
              start.sec == record.startTimeSec, start.usec == record.startTimeUsec else { return }
        if kill(pid, SIGCONT) != 0 {
            handleSignalError(errno, pid: pid, action: "SIGCONT")
        }
    }

    /// C2: durably record the current frozen set. Fail-safe: with no persistence
    /// configured, return false so a process is never stopped unrecoverably.
    /// The hook is read under the lock (set from the engine actor).
    private func persistNow() -> Bool {
        persistLock.lock()
        let handler = persistHandler
        persistLock.unlock()
        guard let handler = handler else { return false }
        let ok = handler(Array(frozen.values))
        if ok { journalNeedsSync = false }
        return ok
    }

    // MARK: - Helpers

    /// One process to signal, plus the authorization decision made when the
    /// target set was built.
    private struct FreezeTarget {
        let pid: Int32
        /// Bundle path the process was discovered under (journal + FR-45 gate).
        let bundlePath: String
        /// D30: frozen because it runs under the selected app's terminal, not
        /// because its executable lives in the bundle.
        let terminalDescendant: Bool
    }

    /// Targets for an app. `.app` freezes every bundle path the app occupies
    /// (FR-16). `.agentTerminals` leaves the app running and freezes only the
    /// shell subtrees that host a supported CLI agent (D30).
    private func targets(for app: ProtectedApp) -> [FreezeTarget] {
        // Roots are processes authorized by bundle membership: the main
        // instance, helpers/XPC inside its bundle, and same-identifier bundles
        // found by path scan.
        var roots: [(pid: Int32, bundlePath: String)] = []
        var seenRoots = Set<Int32>()
        func addRoot(pid: Int32, bundlePath: String) {
            guard pid > 0, !bundlePath.isEmpty, seenRoots.insert(pid).inserted else { return }
            roots.append((pid, bundlePath))
        }

        let instances = ProcessEnumerator.instances(of: app.bundleID)
        var bundlePaths = instances.map(\.bundlePath).filter { !$0.isEmpty }
        if let resolved = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID)?.path,
           !bundlePaths.contains(resolved) {
            bundlePaths.append(resolved)
        }
        for instance in instances {
            let path = instance.bundlePath.isEmpty ? (bundlePaths.first ?? "") : instance.bundlePath
            addRoot(pid: instance.pid, bundlePath: path)
        }
        for bundlePath in bundlePaths {
            for pid in ProcessEnumerator.processes(insideBundleAt: bundlePath) {
                addRoot(pid: pid, bundlePath: bundlePath)
            }
        }
        if app.freezeScope == .agentTerminals {
            // Same bundle identifier, different location: covers helper apps
            // such as Orca's terminal host that NSWorkspace never lists.
            for pid in ProcessEnumerator.processes(bundleID: app.bundleID) {
                guard let executable = ProcessEnumerator.path(of: pid),
                      let bundlePath = ProcessEnumerator.enclosingBundlePath(ofExecutableAt: executable) else { continue }
                addRoot(pid: pid, bundlePath: bundlePath)
            }
        }

        switch app.freezeScope {
        case .app:
            return appTargets(roots: roots)
        case .agentTerminals:
            return agentTerminalTargets(roots: roots)
        }
    }

    /// `.app`: the roots themselves plus anything that lives inside their
    /// bundles is frozen; the FR-45 path gate applies to every one of them.
    private func appTargets(roots: [(pid: Int32, bundlePath: String)]) -> [FreezeTarget] {
        roots.map { FreezeTarget(pid: $0.pid, bundlePath: $0.bundlePath, terminalDescendant: false) }
    }

    /// `.agentTerminals`: walk the app's tree, find agent CLIs attached to a
    /// tty, and freeze the shell session hosting each one — the tab becomes
    /// inert while the app and every non-agent terminal keep running.
    private func agentTerminalTargets(roots: [(pid: Int32, bundlePath: String)]) -> [FreezeTarget] {
        guard !roots.isEmpty else { return [] }
        let rootPIDs = Set(roots.map(\.pid))
        let bundlePath = roots.first?.bundlePath ?? ""
        let tree = ProcessEnumerator.tree(rootedAt: roots.map(\.pid))

        var targets: [FreezeTarget] = []
        var seen = Set<Int32>()
        for agent in tree.pids where AgentDetector.isAgent(pid: agent) {
            // Highest shell below the app: freezing it makes the whole tab
            // inert (host → login → zsh → agent). Without a shell ancestor
            // the agent itself is the session root.
            var sessionRoot = agent
            var cursor = tree.parent[agent]
            while let pid = cursor, pid > 1, !rootPIDs.contains(pid) {
                if AgentDetector.isShell(pid: pid) { sessionRoot = pid }
                cursor = tree.parent[pid]
            }
            guard seen.insert(sessionRoot).inserted else { continue }
            targets.append(FreezeTarget(pid: sessionRoot, bundlePath: bundlePath, terminalDescendant: true))
            for pid in tree.subtree(of: sessionRoot) where seen.insert(pid).inserted {
                targets.append(FreezeTarget(pid: pid, bundlePath: bundlePath, terminalDescendant: true))
            }
        }
        return targets
    }

    private func handleSignalError(_ err: Int32, pid: Int32, action: String) {
        switch err {
        case ESRCH:
            // Process is gone; drop it from tracking (FR-18/24).
            frozen.removeValue(forKey: pid)
        case EPERM:
            AppLog.process.warning("\(action, privacy: .public) EPERM for pid \(pid, privacy: .public); skipped")
        default:
            AppLog.process.warning("\(action, privacy: .public) failed for pid \(pid, privacy: .public) errno \(err, privacy: .public)")
        }
    }
}