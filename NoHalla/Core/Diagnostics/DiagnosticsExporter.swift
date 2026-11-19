//
//  DiagnosticsExporter.swift
//  NoHalla
//
//  Local diagnostics export (implementation brief FR-32, spec D14). Builds a
//  ZIP with config.json, state.json, the last 15 minutes of process logs
//  (OSLogStore, best-effort), versions.txt and export-notes.txt. Uses the
//  system /usr/bin/zip — no dependencies. Nothing is sent automatically; the
//  UI supplies the destination URL via NSSavePanel.
//

import Foundation
import OSLog

enum DiagnosticsExporter {
    static func export(to url: URL, configDirectory: URL) throws {
        let fileManager = FileManager.default
        let staging = fileManager.temporaryDirectory
            .appendingPathComponent("nohalla-diagnostics-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }

        var notes: [String] = []

        // config.json / state.json (if present).
        for name in ["config.json", "state.json"] {
            let source = configDirectory.appendingPathComponent(name)
            if fileManager.fileExists(atPath: source.path) {
                try? fileManager.copyItem(at: source, to: staging.appendingPathComponent(name))
            } else {
                notes.append("\(name): not present")
            }
        }

        // versions.txt
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        let versions = "No-halla \(version)\nmacOS \(osVersion)\n"
        try versions.write(to: staging.appendingPathComponent("versions.txt"), atomically: true, encoding: .utf8)

        // Last 15 minutes of logs (best-effort; OSLogStore may be unavailable in
        // an ad-hoc bundle — record a note rather than failing the export).
        let logText = collectRecentLogs(notes: &notes)
        try logText.write(to: staging.appendingPathComponent("logs.txt"), atomically: true, encoding: .utf8)

        if notes.isEmpty {
            notes.append("All sources collected.")
        }
        try notes.joined(separator: "\n").write(to: staging.appendingPathComponent("export-notes.txt"), atomically: true, encoding: .utf8)

        // Zip the staging contents into the destination URL.
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = staging
        process.arguments = ["-r", "-q", url.path, "."]
        let pipe = Pipe()
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? "zip failed"
            throw NSError(domain: "dev.nohalla.NoHalla.diagnostics", code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    private static func collectRecentLogs(notes: inout [String]) -> String {
        do {
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            let start = Date().addingTimeInterval(-15 * 60)
            let position = store.position(date: start)
            let entries = try store.getEntries(at: position)
            var lines: [String] = []
            let formatter = ISO8601DateFormatter()
            for entry in entries {
                guard let logEntry = entry as? OSLogEntryLog else { continue }
                guard logEntry.date >= start else { continue }
                let timestamp = formatter.string(from: logEntry.date)
                lines.append("\(timestamp) [\(logEntry.subsystem)/\(logEntry.category)] \(logEntry.composedMessage)")
            }
            if lines.isEmpty {
                notes.append("logs.txt: no log entries returned for the last 15 minutes (OSLogStore may be restricted in this build).")
            }
            return lines.joined(separator: "\n")
        } catch {
            notes.append("logs.txt: OSLogStore unavailable (\(error.localizedDescription)); logs omitted.")
            return ""
        }
    }
}