//
//  ProtectionState.swift
//  NoHalla
//
//  Engine/UI status enums and the crash-recovery state persisted in
//  state.json (implementation brief §5.4).
//

import Foundation

/// Core protection state produced by the state machine (brief §6).
enum ProtectionStatus: String, Codable {
    case initializing
    case checking
    case protected
    case grace
    case frozen
    case unknown
    case paused
    case disabled
}

/// Why the apps were frozen. Wire format follows brief §5.4 (`ip_disallowed`).
enum FreezeReason: String, Codable {
    case ipDisallowed = "ip_disallowed"
    case unknown
}

/// User-requested pause length for the protection engine.
enum PauseDuration {
    case minutes15
    case hour1
    case untilRelaunch
}

/// Status presented by the UI; adds onboarding and manual-bypass surfaces
/// on top of the engine states (design brief, D25/D27).
enum UIStatus {
    case setup
    case checking
    case protected
    case grace
    case frozen
    case unknown
    case paused
    case disabled
    case bypassing
}

/// Crash-recovery snapshot written to state.json while apps are frozen.
/// The watchdog reads it to resume processes if the app dies (FR-4/5/41).
struct PersistedState: Codable {
    var schemaVersion: Int
    var frozen: [FrozenProcess]
    var frozenSince: Date?
    var reason: FreezeReason?
    /// Last verified external IP; masked in logs outside debug (FR-39).
    var lastKnownIP: String?
}
