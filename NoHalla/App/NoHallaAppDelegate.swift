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
    private var isPrimaryInstance = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard acquireSingleInstanceLock() else {
            activateExistingInstance()
            NSApp.terminate(nil)
            return
        }
        isPrimaryInstance = true
        appState.start()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // A secondary instance never touched the engine or state; exit at once.
        guard isPrimaryInstance else { return .terminateNow }
        // R3: never block the main thread waiting on a MainActor Task (it would
        // deadlock). Resume asynchronously, then reply to complete termination.
        // s2-lifecycle reuses this path for the quit confirmation + watchdog.
        Task { @MainActor in
            await appState.engine.stop()
            releaseSingleInstanceLock()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Backup cleanup; the resume already ran in applicationShouldTerminate.
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