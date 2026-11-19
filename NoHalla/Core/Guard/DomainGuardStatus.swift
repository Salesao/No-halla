//
//  DomainGuardStatus.swift
//  NoHalla
//
//  Shared guard protocol and persisted state (D48). Compiled into both the app
//  and the privileged helper: models only, no I/O.
//

import Foundation

/// How far proxy blocking got in the helper.
enum DomainGuardProxyMode: String, Codable, Equatable {
    case active
    case unavailable
    case degraded
}

/// What the root helper publishes for the app to read.
struct DomainGuardStatus: Codable, Equatable {
    var protocolVersion: Int
    var proxyMode: DomainGuardProxyMode
    var proxySwitched: Bool
    var reason: String
    var updatedAt: Date
}

/// What the helper saves before it switches the system proxy.
struct ProxyRestoreManifest: Codable, Equatable {
    struct Service: Codable, Equatable {
        var name: String
        var webEnabled: Bool
        var webServer: String
        var webPort: Int
        var secureEnabled: Bool
        var secureServer: String
        var securePort: Int
    }

    var schemaVersion: Int
    var services: [Service]
}

enum DomainGuardProtocol {
    /// Increments when the helper gains a capability the app must know about.
    /// 4 replaces the DNS mechanism with a loopback HTTP proxy.
    static let version = 4
    static let statusURL = URL(fileURLWithPath: "/Library/Application Support/NoHalla/guard-status.json")
    static let manifestURL = URL(fileURLWithPath: "/Library/Application Support/NoHalla/proxy-restore.json")
}