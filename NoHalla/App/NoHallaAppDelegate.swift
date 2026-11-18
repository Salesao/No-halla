//
//  NoHallaAppDelegate.swift
//  NoHalla
//
//  Application lifecycle (S1 wiring). Enforces a single instance via flock
//  (FR-1/43, spec D15), starts the engine through AppState and resumes frozen
//  processes on exit. The full quit confirmation, SIGTERM/SIGINT handling and
//  watchdog coordination land in s2-lifecycle.
//

import AppKit
import Darwin

@MainActor
final class NoHallaAppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    private var lockFileDescriptor: Int32 = -1

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard acquireSingleInstanceLock() else {
            activateExistingInstance()
            NSApp.terminate(nil)
            return
        }
        appState.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Resume everything and clear state before exiting (FR-4). S2 adds the
        // confirmation dialog and watchdog stop.
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            await appState.engine.stop()
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 5)
        releaseSingleInstanceLock()
    }

    // MARK: - Single instance (flock)

    private func acquireSingleInstanceLock() -> Bool {
        let directory = ConfigStore.defaultDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let lockPath = directory.appendingPathComponent("nohalla.lock").path
        lockFileDescriptor = open(lockPath, O_CREAT | O_RDWR, 0o644)
        guard lockFileDescriptor >= 0 else { return false }
        if flock(lockFileDescriptor, LOCK_EX | LOCK_NB) != 0 {
            close(lockFileDescriptor)
            lockFileDescriptor = -1
            return false
        }
        return true
    }

    private func releaseSingleInstanceLock() {
        guard lockFileDescriptor >= 0 else { return }
        flock(lockFileDescriptor, LOCK_UN)
        close(lockFileDescriptor)
        lockFileDescriptor = -1
    }

    private func activateExistingInstance() {
        let bundleID = Bundle.main.bundleIdentifier ?? "dev.nohalla.NoHalla"
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        running.first?.activate(options: [.activateIgnoringOtherApps])
    }
}