//
//  AppConfig.swift
//  NoHalla
//
//  Persisted application configuration (implementation brief §5.4) with the
//  defaults from §13. `logLevel` is the D11 schema extension. The on-disk
//  schema version is 2 (IPv6/quorum removed); loading, migration, validation
//  and atomic writes live in ConfigStore.
//

import Foundation

/// Root configuration object stored in config.json.
struct AppConfig: Codable, Equatable {
    var schemaVersion: Int
    var onboardingCompleted: Bool
    var protection: ProtectionSettings
    /// Trusted IPs/CIDRs as raw strings; parsed via TrustedAddress/CIDRRange.
    var trustedAddresses: [String]
    var protectedApps: [ProtectedApp]
    var ipCheck: IPCheckSettings
    var launchAtLogin: Bool
    var notifications: Bool
    var language: AppLanguage
    var logLevel: LogLevel

    init(
        schemaVersion: Int,
        onboardingCompleted: Bool,
        protection: ProtectionSettings,
        trustedAddresses: [String],
        protectedApps: [ProtectedApp],
        ipCheck: IPCheckSettings,
        launchAtLogin: Bool,
        notifications: Bool,
        language: AppLanguage,
        logLevel: LogLevel
    ) {
        self.schemaVersion = schemaVersion
        self.onboardingCompleted = onboardingCompleted
        self.protection = protection
        self.trustedAddresses = trustedAddresses
        self.protectedApps = protectedApps
        self.ipCheck = ipCheck
        self.launchAtLogin = launchAtLogin
        self.notifications = notifications
        self.language = language
        self.logLevel = logLevel
    }

    /// Factory defaults. Per owner request (simple whitelist model): only freeze
    /// on a KNOWN non-whitelisted IP — `freezeWhenUnknown=false` (unknown IP keeps
    /// apps running). IPv6 checks were removed (owner decision); the main
    /// endpoint is one that routes through the VPN tunnel on split-tunnel hosts.
    /// Four additional endpoints are factory fallbacks: they are queried only
    /// when no main endpoint answers. Other values per brief §13, endpoints
    /// §5.4, logLevel .info per D11.
    static let defaults = AppConfig(
        schemaVersion: 3,
        onboardingCompleted: false,
        protection: ProtectionSettings(
            enabled: true,
            graceSeconds: 1,
            checkIntervalSeconds: 30,
            freezeWhenUnknown: false,
            requireVPNInterface: false,
            manualResumeBypassMinutes: 5
        ),
        trustedAddresses: [],
        protectedApps: [],
        ipCheck: IPCheckSettings(
            endpointsV4: [IPCheckEndpoint.defaultMain],
            fallbackEndpointsV4: IPCheckEndpoint.defaultFallbacks,
            timeoutSeconds: 2.5
        ),
        launchAtLogin: true,
        notifications: true,
        language: .system,
        logLevel: .info
    )
}

/// Protection behaviour toggles and timings (brief §5.4, ranges D19/D24).
struct ProtectionSettings: Codable, Equatable {
    var enabled: Bool
    var graceSeconds: Int
    var checkIntervalSeconds: Int
    var freezeWhenUnknown: Bool
    var requireVPNInterface: Bool
    var manualResumeBypassMinutes: Int
    /// Owner-requested hybrid: decide by public-IP whitelist (external query to
    /// learn the IP) or by the local VPN tunnel interface (no external query).
    var mode: ProtectionMode

    enum CodingKeys: String, CodingKey {
        case enabled, graceSeconds, checkIntervalSeconds, freezeWhenUnknown
        case requireVPNInterface, manualResumeBypassMinutes, mode
    }

    init(
        enabled: Bool,
        graceSeconds: Int,
        checkIntervalSeconds: Int,
        freezeWhenUnknown: Bool,
        requireVPNInterface: Bool,
        manualResumeBypassMinutes: Int,
        mode: ProtectionMode = .vpnInterface
    ) {
        self.enabled = enabled
        self.graceSeconds = graceSeconds
        self.checkIntervalSeconds = checkIntervalSeconds
        self.freezeWhenUnknown = freezeWhenUnknown
        self.requireVPNInterface = requireVPNInterface
        self.manualResumeBypassMinutes = manualResumeBypassMinutes
        self.mode = mode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decode(Bool.self, forKey: .enabled)
        graceSeconds = try container.decode(Int.self, forKey: .graceSeconds)
        checkIntervalSeconds = try container.decode(Int.self, forKey: .checkIntervalSeconds)
        freezeWhenUnknown = try container.decode(Bool.self, forKey: .freezeWhenUnknown)
        requireVPNInterface = try container.decode(Bool.self, forKey: .requireVPNInterface)
        manualResumeBypassMinutes = try container.decode(Int.self, forKey: .manualResumeBypassMinutes)
        // Older configs predate `mode`; default to the VPN-tunnel mode.
        mode = try container.decodeIfPresent(ProtectionMode.self, forKey: .mode) ?? .vpnInterface
    }
}

/// How protection decides trust (owner-requested hybrid switch).
enum ProtectionMode: String, Codable, Equatable {
    /// Local VPN tunnel interface presence — no external query.
    case vpnInterface
    /// Public-IP whitelist — an external endpoint learns the current IP.
    case ipWhitelist
}

/// External IP verification settings (brief §5.4; IPv6/quorum removed by
/// owner decision — every valid answer must be trusted, zero answers is
/// unknown). Main endpoints are queried in parallel; fallback endpoints are
/// queried only when no main endpoint answers.
struct IPCheckSettings: Codable, Equatable {
    var endpointsV4: [String]
    var fallbackEndpointsV4: [String]
    var timeoutSeconds: Double

    enum CodingKeys: String, CodingKey {
        case endpointsV4, fallbackEndpointsV4, timeoutSeconds
    }

    init(endpointsV4: [String], fallbackEndpointsV4: [String], timeoutSeconds: Double) {
        self.endpointsV4 = endpointsV4
        self.fallbackEndpointsV4 = fallbackEndpointsV4
        self.timeoutSeconds = timeoutSeconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        endpointsV4 = try container.decode([String].self, forKey: .endpointsV4)
        // Added in schema 3; schema 2 configs are migrated to the defaults.
        fallbackEndpointsV4 = try container.decodeIfPresent([String].self, forKey: .fallbackEndpointsV4) ?? []
        timeoutSeconds = try container.decode(Double.self, forKey: .timeoutSeconds)
    }
}

/// UI language preference; `system` follows the macOS locale (EN/RU).
enum AppLanguage: String, Codable {
    case system
    case en
    case ru
}

/// Log verbosity (D11). At `info` IPs are masked; `debug` may log full IPs.
enum LogLevel: String, Codable {
    case info
    case debug
}
