//
//  WindowMinimizer.swift
//  NoHalla
//
//  User-requested freeze UX: minimize a protected app's windows to the Dock
//  while it is frozen, and restore them on resume, so a frozen app does not sit
//  on screen looking hung. Minimizing another app's windows uses the public
//  Accessibility API (AXUIElement) and requires the user to grant Accessibility
//  permission; without it we fall back to hiding the app (NSRunningApplication).
//  Window actions must run BEFORE SIGSTOP (a frozen app cannot process them)
//  and restoration AFTER SIGCONT.
//

import AppKit
import ApplicationServices

enum WindowMinimizer {
    /// Whether the user has granted Accessibility permission.
    static func isAccessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system Accessibility prompt (once; opens System Settings).
    static func promptAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private static var didPrompt = false
    private static let promptedKey = "nohalla.accessibilityPrompted"

    /// Prompts at most once ever and only while not yet trusted. The flag is
    /// persisted because an ad-hoc signed rebuild gets a new TCC identity: the
    /// system would otherwise ask again on every launch and every freeze.
    /// Without the grant windows are hidden instead of minimized, so the app
    /// stays fully usable; the user can still enable it in System Settings.
    static func promptAccessibilityOnce() {
        guard !didPrompt, !AXIsProcessTrusted() else { return }
        didPrompt = true
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: promptedKey) else { return }
        defaults.set(true, forKey: promptedKey)
        promptAccessibility()
    }

    /// Minimizes every window of the running app with the given bundle ID.
    /// Uses Accessibility when trusted, otherwise hides the app.
    static func minimizeApp(bundleID: String) {
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) else { return }
        if AXIsProcessTrusted() {
            performOnWindows(pid: app.processIdentifier) { window in
                AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
            }
        } else {
            app.hide()
        }
    }

    /// Restores windows of the given process after resume. Un-minimizes via
    /// Accessibility when trusted, otherwise unhides the app.
    static func restoreApp(pid: Int32) {
        if AXIsProcessTrusted() {
            performOnWindows(pid: pid) { window in
                AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            }
        } else {
            NSRunningApplication(processIdentifier: pid)?.unhide()
        }
    }

    /// Restores windows of the running app with the given bundle ID. Used by
    /// the freeze abort path: the app was never stopped, so only the
    /// minimization needs undoing.
    static func restoreApp(bundleID: String) {
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) else { return }
        restoreApp(pid: app.processIdentifier)
    }

    private static func performOnWindows(pid: Int32, action: (AXUIElement) -> Void) {
        let axApp = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value)
        guard result == .success, let windows = value as? [AXUIElement] else { return }
        for window in windows {
            action(window)
        }
    }
}