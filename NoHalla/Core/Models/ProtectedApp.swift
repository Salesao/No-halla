//
//  ProtectedApp.swift
//  NoHalla
//
//  An application selected for protection, identified by its bundle ID
//  (implementation brief §5.4).
//

import Foundation

/// What a selected app freezes on an untrusted IP (D30).
enum FreezeScope: String, Codable, Equatable {
    /// The app's own processes, helpers and XPC services (v1 behaviour).
    case app
    /// Leave the app running and stop only the terminal sessions that host a
    /// CLI agent (Claude Code, Codex). Builds, ssh and dev servers in other
    /// terminals keep running.
    case agentTerminals
}

/// A user-selected app whose processes are frozen on an untrusted IP.
struct ProtectedApp: Codable, Equatable, Identifiable {
    var bundleID: String
    var name: String
    var enabled: Bool
    /// D30: what to freeze for this app. Absent from configs written before
    /// D30, hence the custom decoder; a legacy `freezeTerminalProcesses: true`
    /// maps to `.agentTerminals`.
    var freezeScope: FreezeScope

    var id: String { bundleID }

    init(bundleID: String, name: String, enabled: Bool, freezeScope: FreezeScope = .app) {
        self.bundleID = bundleID
        self.name = name
        self.enabled = enabled
        self.freezeScope = freezeScope
    }

    private enum CodingKeys: String, CodingKey {
        case bundleID, name, enabled, freezeScope
    }

    /// Key from the first D30 build, kept only for migration.
    private enum LegacyCodingKeys: String, CodingKey {
        case freezeTerminalProcesses
    }

    /// Decoding tolerates configs written before D30: a missing `freezeScope`
    /// means `.app`; the intermediate boolean means `.agentTerminals`.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bundleID = try container.decode(String.self, forKey: .bundleID)
        name = try container.decode(String.self, forKey: .name)
        enabled = try container.decode(Bool.self, forKey: .enabled)
        if let scope = try container.decodeIfPresent(FreezeScope.self, forKey: .freezeScope) {
            freezeScope = scope
        } else {
            let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
            let freezeTerminals = try legacy.decodeIfPresent(Bool.self, forKey: .freezeTerminalProcesses) ?? false
            freezeScope = freezeTerminals ? .agentTerminals : .app
        }
    }
}