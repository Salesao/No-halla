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

final class ProcessController: ProcessControlling {
    private let queue = DispatchQueue(label: "dev.nohalla.NoHalla.process-controller")
    private let selfPID: Int32
    private let watchdogPIDProvider: () -> Int32?
    /// Tracked frozen processes keyed by pid (idempotence + identity records).
    private var frozen: [Int32: FrozenProcess] = [:]

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

        if kill(pid, SIGSTOP) == 0 {
            frozen[pid] = FrozenProcess(pid: pid, startTimeSec: start.sec, startTimeUsec: start.usec, bundleID: bundleID, path: path)
            AppLog.process.info("Froze pid \(pid, privacy: .public)")
        } else {
            handleSignalError(errno, pid: pid, action: "SIGSTOP")
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
        return resumed
    }

    // MARK: - Reconcile (FR-24)

    private func reconcileSync(_ apps: [ProtectedApp]) -> [FrozenProcess] {
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
        return Array(frozen.values)
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