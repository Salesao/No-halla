//
//  WatchdogLauncher.swift
//  NoHalla
//
//  Spawns and supervises the NoHallaWatchdog helper embedded in the app
//  bundle (brief §5.5/§8.9, FR-41). The watchdog resumes frozen processes
//  if the app dies unexpectedly; if the watchdog itself dies without being
//  stopped by us, it is restarted and the event is logged as an error.
//

import Foundation

/// Launches the embedded watchdog and keeps it alive until `stop()`.
/// Thread-safe: `start`/`stop` are called from the app lifecycle, while
/// `Process.terminationHandler` fires on a background queue.
final class WatchdogLauncher {
    /// PID of the running watchdog, consumed by the safety guard so the
    /// watchdog itself is never frozen (FR-17).
    private(set) var watchdogPID: Int32?

    private let lock = NSLock()
    private var process: Process?
    private var stopRequested = false
    private var parentPID: Int32?
    private var statePath: URL?

    deinit {
        stop()
    }

    /// Starts (or replaces) the watchdog watching `parentPID` with the
    /// recovery snapshot at `statePath`.
    func start(parentPID: Int32, statePath: URL) {
        lock.lock()
        stopRequested = false
        self.parentPID = parentPID
        self.statePath = statePath
        let previous = process
        process = nil
        watchdogPID = nil
        lock.unlock()

        // Retire a previous instance, if any. Clearing `process` first makes
        // its termination handler a no-op instead of triggering a restart.
        if let previous, previous.isRunning {
            previous.terminate()
            previous.waitUntilExit()
        }

        lock.lock()
        spawnLocked()
        lock.unlock()
    }

    /// Stops the watchdog for good (normal quit path, FR-4). No restart
    /// follows the termination.
    func stop() {
        lock.lock()
        stopRequested = true
        let current = process
        process = nil
        watchdogPID = nil
        lock.unlock()

        guard let current else { return }
        if current.isRunning {
            current.terminate()
        }
        current.waitUntilExit()
    }

    // MARK: - Spawn

    /// Must be called with `lock` held.
    private func spawnLocked() {
        guard let parentPID, let statePath else { return }

        let executableURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/NoHallaWatchdog")
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            AppLog.watchdog.error("Watchdog binary not executable at \(executableURL.path, privacy: .public)")
            return
        }

        let task = Process()
        task.executableURL = executableURL
        task.arguments = ["--parent", String(parentPID), "--state", statePath.path]
        task.terminationHandler = { [weak self] finished in
            self?.handleTermination(of: finished)
        }

        do {
            try task.run()
        } catch {
            AppLog.watchdog.error("Watchdog spawn failed: \(error.localizedDescription, privacy: .public)")
            return
        }

        process = task
        watchdogPID = task.processIdentifier
        AppLog.watchdog.info("Watchdog started with pid \(task.processIdentifier, privacy: .public)")
    }

    // MARK: - Supervision

    private func handleTermination(of finished: Process) {
        lock.lock()
        // Ignore stale handlers: a stopped launcher or a replaced process
        // must not trigger a restart.
        guard !stopRequested, process === finished else {
            lock.unlock()
            return
        }
        process = nil
        watchdogPID = nil
        lock.unlock()

        AppLog.watchdog.error("Watchdog exited unexpectedly (status \(finished.terminationStatus, privacy: .public)); restarting")

        // Brief delay so a persistently failing binary cannot produce a
        // tight respawn loop. Re-check under the lock: a concurrent stop()
        // or start() supersedes this restart.
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + .seconds(1)) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            defer { self.lock.unlock() }
            guard !self.stopRequested, self.process == nil else { return }
            self.spawnLocked()
        }
    }
}
