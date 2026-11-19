//
//  SafetyGuard.swift
//  NoHalla
//
//  Pure safety policy for process freezing (FR-17, FR-28, FR-45, brief §8.5).
//  Decides which processes must never receive SIGSTOP/SIGCONT, validates that
//  a process path really lives inside the expected .app bundle, and produces
//  picker warning copy keys. No side effects and no signals are sent here.
//

import Darwin
import Foundation

/// Safety policy shared by the process controller and the app picker.
enum SafetyGuard {
    /// Executable names that must never be signalled (FR-17).
    static let deniedExecutableNames: Set<String> = [
        "kernel_task",
        "WindowServer",
        "Dock",
        "Finder",
        "loginwindow",
        "SystemUIServer",
        "ControlCenter",
        "launchd"
    ]

    /// Bundle IDs of the same system entities. Executable names are the
    /// primary check because system helpers may report no bundle ID at all.
    /// Stored lowercased for tolerant comparison.
    private static let deniedBundleIDs: Set<String> = [
        "com.apple.finder",
        "com.apple.dock",
        "com.apple.loginwindow",
        "com.apple.systemuiserver",
        "com.apple.controlcenter"
    ]

    private static let deniedExecutableNamesLowercased = Set(
        deniedExecutableNames.map { $0.lowercased() }
    )

    /// Terminal-like apps: freezing is allowed but may interrupt running
    /// commands, so the picker shows a warning instead of denying (FR-28).
    private static let terminalBundleIDs: Set<String> = [
        "com.apple.terminal",
        "com.googlecode.iterm2",
        "org.alacritty",
        "net.kovidgoyal.kitty",
        "com.github.wez.wezterm",
        "dev.warp.warp-stable",
        "co.zeit.hyper"
    ]

    // MARK: - Freeze deny policy (FR-17)

    /// True when the process must never be signalled: PID 0/1, self, the
    /// watchdog, a denied executable name or bundle ID, or a foreign uid.
    static func isDenied(
        pid: Int32,
        path: String,
        bundleID: String?,
        selfPID: Int32,
        watchdogPID: Int32?
    ) -> Bool {
        // PID 0 is kernel_task, PID 1 is launchd; negative PIDs are invalid.
        if pid <= 1 { return true }
        if pid == selfPID { return true }
        if let watchdogPID = watchdogPID, pid == watchdogPID { return true }

        let name = (path as NSString).lastPathComponent
        if deniedExecutableNamesLowercased.contains(name.lowercased()) {
            return true
        }

        if let bundleID = bundleID, deniedBundleIDs.contains(bundleID.lowercased()) {
            return true
        }

        // Fail closed: an unreadable owner means we cannot prove the process
        // belongs to the current user, so it must not be signalled.
        guard let owner = ProcessEnumerator.uid(of: pid) else { return true }
        return owner != getuid()
    }

    // MARK: - Bundle path validation (FR-45)

    /// True only when `path` lies strictly inside the `bundlePath` .app:
    /// normalized paths, a "<bundle>/" prefix and a non-empty remainder.
    /// Sibling paths such as "/Applications/Foo.app2/..." never match.
    static func isInsideBundle(path: String, bundlePath: String) -> Bool {
        let bundle = normalizedPath(bundlePath)
        let candidate = normalizedPath(path)
        guard !bundle.isEmpty, !candidate.isEmpty else { return false }
        guard bundle.lowercased().hasSuffix(".app") else { return false }

        let prefix = bundle + "/"
        guard candidate.hasPrefix(prefix) else { return false }
        return candidate.count > prefix.count
    }

    /// Standardizes ".", ".." and "~", then resolves symlinks so a spoofed
    /// or symlinked path cannot escape the expected bundle location.
    private static func normalizedPath(_ path: String) -> String {
        let standardized = (path as NSString).standardizingPath
        return (standardized as NSString).resolvingSymlinksInPath
    }

    // MARK: - Picker warnings (FR-28)

    /// Returns a `design/copy.json` key for the UI to localize via L10n, or
    /// nil when the app needs no warning. The key is returned, not the text.
    static func pickerWarning(for bundleID: String, name: String) -> String? {
        let loweredBundleID = bundleID.lowercased()
        let loweredName = name.lowercased()

        if deniedBundleIDs.contains(loweredBundleID)
            || deniedExecutableNamesLowercased.contains(loweredName) {
            return "ui.system-app-can-t-be-protected"
        }

        if terminalBundleIDs.contains(loweredBundleID)
            || loweredName.contains("terminal")
            || loweredName.contains("iterm") {
            return "ui.freezing-terminal-may-interrupt-active-commands"
        }

        return nil
    }
}
