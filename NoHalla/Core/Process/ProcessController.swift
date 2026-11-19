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
            let (candidates, bundlePath) = targetPIDs(for: app)
            guard !bundlePath.isEmpty else { continue }
            for pid in candidates {
                freezeOne(pid: pid, bundleID: app.bundleID, bundlePath: bundlePath)
            }
        }
        return Array(frozen.values)
    }

    private func freezeOne(pid: Int32, bundleID: String, bundlePath: String) {
        guard pid > 0, frozen[pid] == nil else { return }

        let path = ProcessEnumerator.path(of: pid) ?? ""
        if SafetyGuard.isDenied(pid: pid, path: path, bundleID: bundleID, selfPID: selfPID, watchdogPID: watchdogPIDProvider()) {
            AppLog.process.info("Skip denied pid \(pid, privacy: .public)")
            return
        }
        guard SafetyGuard.isInsideBundle(path: path, bundlePath: bundlePath) else {
            AppLog.process.info("Skip pid outside bundle \(pid, privacy: .public)")
            return
        }
        // Identity snapshot taken before the signal (PID-reuse guard).
        guard let start = ProcessEnumerator.startTime(of: pid) else { return }

        // C2: record the process durably BEFORE stopping it, so a crash between
        // SIGSTOP and publication still leaves it recoverable by the watchdog /
        // next launch. If the record cannot be persisted, do not stop it. A crash
        // after this write but before the signal leaves an "incomplete intent":
        // recovery sends an identity-checked SIGCONT, which is a benign no-op on
        // a still-running process — never a claim of owning someone else's stop.
        let record = FrozenProcess(pid: pid, startTimeSec: start.sec, startTimeUsec: start.usec, bundleID: bundleID, path: path)
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
        let activeBundleIDs = Set(apps.filter { $0.enabled }.map { $0.bundleID })
        // Resume processes of apps removed or disabled from protection (FR-24):
        // they must not stay SIGSTOP until a full Resume all.
        for pid in Array(frozen.keys) {
            guard let record = frozen[pid] else { continue }
            if !activeBundleIDs.contains(record.bundleID) {
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
        // Freeze newly launched instances and helpers of enabled apps.
        for app in apps where app.enabled {
            let (candidates, bundlePath) = targetPIDs(for: app)
            guard !bundlePath.isEmpty else { continue }
            for pid in candidates {
                freezeOne(pid: pid, bundleID: app.bundleID, bundlePath: bundlePath)
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

    /// Candidate pid set for an app: main instances + their children + every
    /// process whose path lies inside the app bundle (FR-16).
    private func targetPIDs(for app: ProtectedApp) -> (Set<Int32>, String) {
        let instances = ProcessEnumerator.instances(of: app.bundleID)
        let bundlePath = instances.first?.bundlePath
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID)?.path
            ?? ""
        var candidates = Set<Int32>()
        for instance in instances {
            candidates.insert(instance.pid)
            for child in ProcessEnumerator.childPIDs(of: instance.pid) {
                candidates.insert(child)
            }
        }
        if !bundlePath.isEmpty {
            for pid in ProcessEnumerator.processes(insideBundleAt: bundlePath) {
                candidates.insert(pid)
            }
        }
        return (candidates, bundlePath)
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