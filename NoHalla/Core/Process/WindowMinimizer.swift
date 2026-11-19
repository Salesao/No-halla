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

    /// Prompts at most once per launch and only while not yet trusted.
    static func promptAccessibilityOnce() {
        guard !didPrompt, !AXIsProcessTrusted() else { return }
        didPrompt = true
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