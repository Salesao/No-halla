//
//  NoHallaAppDelegate.swift
//  NoHalla
//
//  Application lifecycle (FR-1/4/5/6/43, spec D15/D20). Enforces a single
//  instance via flock, recovers stale frozen records on startup, supervises
//  the watchdog, and resumes frozen processes on quit (with confirmation)
//  and on SIGTERM/SIGINT.
//

import AppKit
import Darwin

@MainActor
final class NoHallaAppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()

    private let statePath = ConfigStore.defaultDirectory.appendingPathComponent("state.json")
    private var lockFileDescriptor: Int32 = -1
    private var isPrimaryInstance = false
    private var signalSources: [DispatchSourceSignal] = []
    /// Set when SIGTERM/SIGINT routes into the normal quit path. The frozen
    /// apps are resumed there, so no confirmation dialog is shown (D20).
    private var isSignalShutdown = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard acquireSingleInstanceLock() else {
            activateExistingInstance()
            NSApp.terminate(nil)
            return
        }
        isPrimaryInstance = true
        installTerminationSignalHandlers()

        Task { @MainActor in
            // FR-6 order: recover stale frozen -> watchdog -> engine. AppState
            // owns the launcher and installs the snapshot/notification callbacks
            // in start(); the coordinator is wired there (s2-wiring).
            await appState.engine.recoverStaleFrozen()
            appState.watchdogLauncher.start(parentPID: getpid(), statePath: statePath)
            appState.start()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // User requested a Dock icon: clicking it with no visible window opens
        // Settings (the popover lives in the menu bar extra).
        if !flag {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // A secondary instance never touched the engine or state; exit at once.
        guard isPrimaryInstance else { return .terminateNow }
        // R3: never block the main thread waiting on a MainActor Task (it would
        // deadlock). Confirm/resume asynchronously, then reply to terminate.
        Task { @MainActor in
            let frozenCount = appState.snapshot.frozenBundleIDs.count
            // D20: confirm only when apps are frozen. A signal-driven shutdown
            // resumes them on this same path, so it never prompts.
            if frozenCount > 0 && !isSignalShutdown {
                let confirmed = await QuitConfirmationAlert.confirm(frozenCount: frozenCount)
                guard confirmed else {
                    NSApp.reply(toApplicationShouldTerminate: false)
                    return
                }
            }
            // FR-4 order: resume all + clear state (engine.stop) -> watchdog.
            await appState.engine.stop()
            appState.watchdogLauncher.stop()
            cancelTerminationSignalHandlers()
            releaseSingleInstanceLock()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Backup cleanup; the resume already ran in applicationShouldTerminate.
        releaseSingleInstanceLock()
    }

    // MARK: - SIGTERM / SIGINT (FR-5)

    private func installTerminationSignalHandlers() {
        for signalNumber in [SIGTERM, SIGINT] {
            // Ignore the default disposition so the dispatch source receives it.
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler { [weak self] in
                Task { @MainActor in
                    self?.handleTerminationSignal()
                }
            }
            source.resume()
            signalSources.append(source)
        }
    }

    private func handleTerminationSignal() {
        // Route through the normal quit path so resume all + state clear +
        // watchdog stop run exactly once (FR-5). No confirmation (D20).
        isSignalShutdown = true
        NSApp.terminate(nil)
    }

    private func cancelTerminationSignalHandlers() {
        for source in signalSources {
            source.cancel()
        }
        signalSources.removeAll()
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
