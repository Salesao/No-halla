//
//  AppConfig.swift
//  NoHalla
//
//  Persisted application configuration (implementation brief §5.4) with the
//  defaults from §13. `logLevel` is the D11 schema extension. The on-disk
//  schema version is 1; loading, validation and atomic writes live in
//  ConfigStore.
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

    /// Factory defaults. Per owner request (simple whitelist model): only freeze
    /// on a KNOWN non-whitelisted IP — `freezeWhenUnknown=false` (unknown IP keeps
    /// apps running) and `quorum=1` (a single responding endpoint suffices).
    /// Other values per brief §13, endpoints §5.4, logLevel .info per D11.
    static let defaults = AppConfig(
        schemaVersion: 1,
        onboardingCompleted: false,
        protection: ProtectionSettings(
            enabled: true,
            graceSeconds: 5,
            checkIntervalSeconds: 30,
            freezeWhenUnknown: false,
            checkIPv6: true,
            requireVPNInterface: false,
            manualResumeBypassMinutes: 5
        ),
        trustedAddresses: [],
        protectedApps: [],
        ipCheck: IPCheckSettings(
            endpointsV4: [
                "https://api.ipify.org",
                "https://ifconfig.me/ip",
                "https://icanhazip.com",
                "https://ipinfo.io/ip"
            ],
            endpointsV6: [
                "https://api6.ipify.org",
                "https://ifconfig.co/ip"
            ],
            timeoutSeconds: 2.5,
            quorum: 1
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
    var checkIPv6: Bool
    var requireVPNInterface: Bool
    var manualResumeBypassMinutes: Int
}

/// External IP verification settings (brief §5.4).
struct IPCheckSettings: Codable, Equatable {
    var endpointsV4: [String]
    var endpointsV6: [String]
    var timeoutSeconds: Double
    var quorum: Int
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
