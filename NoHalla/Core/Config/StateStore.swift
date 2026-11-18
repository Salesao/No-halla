//
//  StateStore.swift
//  NoHalla
//
//  Atomic persistence for state.json, the crash-recovery snapshot consumed
//  by the watchdog (brief §5.4/§5.5). Writes use temp + replaceItemAt; dates
//  are ISO 8601 as in the brief's schema. A missing or corrupt state file
//  loads as nil (nothing to recover).
//

import Foundation

/// Atomic persistence for PersistedState (state.json).
final class StateStore {
    private static let currentSchemaVersion = 1

    private let directory: URL
    private var stateURL: URL { directory.appendingPathComponent("state.json") }

    init(directory: URL = ConfigStore.defaultDirectory) {
        self.directory = directory
    }

    /// Loads the recovery snapshot; nil when absent, corrupt or written by
    /// an unsupported newer schema.
    func load() -> PersistedState? {
        guard FileManager.default.fileExists(atPath: stateURL.path) else {
            return nil
        }
        do {
            let data = try Data(contentsOf: stateURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            var state = try decoder.decode(PersistedState.self, from: data)
            guard state.schemaVersion <= Self.currentSchemaVersion else {
                AppLog.engine.error("State schema \(state.schemaVersion, privacy: .public) newer than supported; discarding")
                return nil
            }
            // Version 1 is the first shipped schema; older snapshots would
            // be upgraded here before stamping the current version.
            state.schemaVersion = Self.currentSchemaVersion
            return state
        } catch {
            AppLog.engine.error("State load failed, discarding: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Atomically writes the snapshot (temp file + replaceItemAt).
    func save(_ state: PersistedState) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(state)
        try writeAtomically(data, to: stateURL)
    }

    /// Removes the snapshot; a missing file is already a clear state.
    func clear() throws {
        if FileManager.default.fileExists(atPath: stateURL.path) {
            try FileManager.default.removeItem(at: stateURL)
        }
    }

    // MARK: - Atomic write

    /// Writes data to a temp file in the same directory, then atomically
    /// replaces the destination (or moves the temp file into place when the
    /// destination does not exist yet). Cleans up the temp file on failure.
    private func writeAtomically(_ data: Data, to url: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let tempURL = directory.appendingPathComponent(".\(url.lastPathComponent).tmp-\(UUID().uuidString)")
        do {
            try data.write(to: tempURL, options: .atomic)
            if fileManager.fileExists(atPath: url.path) {
                _ = try fileManager.replaceItemAt(url, withItemAt: tempURL)
            } else {
                try fileManager.moveItem(at: tempURL, to: url)
            }
        } catch {
            try? fileManager.removeItem(at: tempURL)
            throw error
        }
    }
}
