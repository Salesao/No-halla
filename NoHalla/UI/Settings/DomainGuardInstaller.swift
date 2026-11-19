//
//  DomainGuardInstaller.swift
//  NoHalla
//
//  Installs/removes the D32 root helper from the app (D41/D43). The privileged
//  step runs a bundled script through the system admin prompt via `osascript`;
//  the install command is also copyable for manual use. The app itself stays
//  unprivileged.
//

import AppKit
import Foundation

enum DomainGuardInstaller {
    static let label = "dev.nohalla.NoHallaDomainGuard"
    static let plistPath = "/Library/LaunchDaemons/\(label).plist"

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: plistPath)
    }

    static var scriptPath: String {
        Bundle.main.bundlePath + "/Contents/Resources/install-domain-guard.sh"
    }

    static var uninstallScriptPath: String {
        Bundle.main.bundlePath + "/Contents/Resources/uninstall-domain-guard.sh"
    }

    /// Exact command shown to the user and copied to the pasteboard.
    static var command: String {
        "sudo bash \"\(scriptPath)\""
    }

    static func copyCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
    }

    /// Runs the bundled installer with administrator rights. Returns false when
    /// the user cancels or the installer exits non-zero.
    static func install() async -> Bool {
        await runBundledScript(at: scriptPath)
    }

    /// Runs the bundled uninstaller with administrator rights.
    static func uninstall() async -> Bool {
        await runBundledScript(at: uninstallScriptPath)
    }

    private static func runBundledScript(at path: String) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: runPrivileged(path: path))
            }
        }
    }

    private static func runPrivileged(path: String) -> Bool {
        guard FileManager.default.fileExists(atPath: path) else { return false }
        // AppleScript string escaping, then `quoted form of` handles shell quoting.
        let escaped = path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let appleScript = "do shell script \"bash \" & quoted form of \"\(escaped)\" with administrator privileges"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", appleScript]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return false
        }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}