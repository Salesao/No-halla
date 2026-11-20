//
//  ConfigStore.swift
//  NoHalla
//
//  Loads and saves config.json in ~/Library/Application Support/NoHalla/
//  (brief §5.4). Writes are atomic: temp file + FileManager.replaceItemAt.
//  Loading migrates by schemaVersion, validates fields against the D11/D19/
//  D24 ranges, repairs invalid fields with defaults, and falls back to full
//  defaults on corrupt JSON. `lastLoadWasCorrupt` drives the settings banner.
//

import Foundation

/// Atomic, validating persistence for AppConfig.
final class ConfigStore {
    /// ~/Library/Application Support/NoHalla/
    static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("NoHalla", isDirectory: true)
    }

    private static let currentSchemaVersion = 2

    private let directory: URL
    private var configURL: URL { directory.appendingPathComponent("config.json") }

    /// True when the last load hit corrupt JSON or repaired invalid fields.
    private(set) var lastLoadWasCorrupt: Bool = false

    init(directory: URL = ConfigStore.defaultDirectory) {
        self.directory = directory
    }

    /// Loads the config; missing file yields defaults, corrupt JSON yields
    /// defaults plus `lastLoadWasCorrupt`, invalid fields are repaired.
    func load() -> AppConfig {
        lastLoadWasCorrupt = false
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            return .defaults
        }
        do {
            let data = try Data(contentsOf: configURL)
            let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
            let migrated = try migrate(decoded)
            return validated(migrated)
        } catch {
            lastLoadWasCorrupt = true
            AppLog.engine.error("Config load failed, using defaults: \(error.localizedDescription, privacy: .public)")
            return .defaults
        }
    }

    /// Atomically writes the config (temp file + replaceItemAt).
    func save(_ config: AppConfig) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try writeAtomically(data, to: configURL)
    }

    // MARK: - Migration

    private enum StoreError: Error {
        case unsupportedSchemaVersion(Int)
    }

    /// Step-wise schema migration. v1 → v2 (owner decision): IPv6 checks and
    /// quorum removed; the old factory-default endpoint list (whose ipify and
    /// ifconfig.me entries bypass domain-routed split tunnels and leak the real
    /// IP) becomes the single tunnel-routed default; IPv6 trusted entries are
    /// dropped silently — they can no longer be observed. Files written by a
    /// newer schema cannot be interpreted safely and are treated as corrupt.
    private func migrate(_ config: AppConfig) throws -> AppConfig {
        guard config.schemaVersion <= Self.currentSchemaVersion else {
            throw StoreError.unsupportedSchemaVersion(config.schemaVersion)
        }
        var config = config
        if config.schemaVersion < 2 {
            let legacyDefaultEndpoints: Set<String> = [
                "https://api.ipify.org",
                "https://ifconfig.me/ip",
                "https://icanhazip.com",
                "https://ipinfo.io/ip"
            ]
            if Set(config.ipCheck.endpointsV4) == legacyDefaultEndpoints {
                config.ipCheck.endpointsV4 = AppConfig.defaults.ipCheck.endpointsV4
            }
            config.trustedAddresses = config.trustedAddresses.filter { TrustedAddress(raw: $0).isValid }
        }
        config.schemaVersion = Self.currentSchemaVersion
        return config
    }

    // MARK: - Validation

    /// Replaces out-of-range or unparseable fields with defaults (brief §5.4,
    /// D19/D24) and logs every repair. Any repair sets `lastLoadWasCorrupt`.
    private func validated(_ config: AppConfig) -> AppConfig {
        var config = config
        let fallback = AppConfig.defaults
        var repaired = false

        if !(0...120).contains(config.protection.graceSeconds) {
            AppLog.engine.error("Config graceSeconds \(config.protection.graceSeconds, privacy: .public) outside 0...120; using default")
            config.protection.graceSeconds = fallback.protection.graceSeconds
            repaired = true
        }
        if !(10...120).contains(config.protection.checkIntervalSeconds) {
            AppLog.engine.error("Config checkIntervalSeconds \(config.protection.checkIntervalSeconds, privacy: .public) outside 10...120; using default")
            config.protection.checkIntervalSeconds = fallback.protection.checkIntervalSeconds
            repaired = true
        }
        if !(0...60).contains(config.protection.manualResumeBypassMinutes) {
            AppLog.engine.error("Config manualResumeBypassMinutes \(config.protection.manualResumeBypassMinutes, privacy: .public) outside 0...60; using default")
            config.protection.manualResumeBypassMinutes = fallback.protection.manualResumeBypassMinutes
            repaired = true
        }
        if !config.ipCheck.timeoutSeconds.isFinite || config.ipCheck.timeoutSeconds <= 0 {
            AppLog.engine.error("Config timeoutSeconds invalid; using default")
            config.ipCheck.timeoutSeconds = fallback.ipCheck.timeoutSeconds
            repaired = true
        }

        let (v4, v4Repaired) = sanitizeEndpoints(
            config.ipCheck.endpointsV4,
            defaults: fallback.ipCheck.endpointsV4,
            family: "IPv4"
        )
        config.ipCheck.endpointsV4 = v4
        repaired = repaired || v4Repaired

        var trusted: [String] = []
        for raw in config.trustedAddresses {
            if TrustedAddress(raw: raw).isValid {
                trusted.append(raw)
            } else {
                AppLog.engine.error("Dropped unparseable trusted address \(AppLog.maskIP(raw), privacy: .public)")
                repaired = true
            }
        }
        config.trustedAddresses = trusted

        if repaired {
            lastLoadWasCorrupt = true
        }
        return config
    }

    /// Keeps only valid HTTPS endpoints; an emptied list falls back to the
    /// §5.4 defaults so IP verification stays possible.
    private func sanitizeEndpoints(_ endpoints: [String], defaults: [String], family: String) -> ([String], Bool) {
        let valid = endpoints.filter(Self.isHTTPSEndpoint)
        var repaired = false
        if valid.count != endpoints.count {
            AppLog.engine.error("Dropped \(endpoints.count - valid.count, privacy: .public) invalid \(family, privacy: .public) endpoint(s)")
            repaired = true
        }
        if valid.isEmpty {
            AppLog.engine.error("No valid \(family, privacy: .public) endpoints remain; restoring defaults")
            return (defaults, true)
        }
        return (valid, repaired)
    }

    private static func isHTTPSEndpoint(_ string: String) -> Bool {
        guard let url = URL(string: string),
              url.scheme?.lowercased() == "https",
              let host = url.host,
              !host.isEmpty
        else { return false }
        return true
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
