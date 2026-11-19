//
//  DomainGuardStatus.swift
//  NoHalla
//
//  Shared guard protocol and persisted state (D47). Compiled into both the app
//  and the privileged helper: models only, no I/O.
//

import Foundation

/// How far suffix blocking got in the helper.
enum DomainGuardSuffixMode: String, Codable, Equatable {
    case active
    case unavailable
    case degraded
}

/// What the root helper publishes for the app to read.
struct DomainGuardStatus: Codable, Equatable {
    var protocolVersion: Int
    var suffixMode: DomainGuardSuffixMode
    var dnsSwitched: Bool
    var reason: String
    var updatedAt: Date
}

/// What the helper saves before it switches system DNS.
struct DNSRestoreManifest: Codable, Equatable {
    struct Service: Codable, Equatable {
        var name: String
        var servers: [String]
    }

    var schemaVersion: Int
    var services: [Service]
    var upstreams: [String]
}

enum DomainGuardProtocol {
    /// Increments when the helper gains a capability the app must know about.
    /// 3 adds the DNS cache flush on activation/release.
    static let version = 3
    static let statusURL = URL(fileURLWithPath: "/Library/Application Support/NoHalla/guard-status.json")
    static let manifestURL = URL(fileURLWithPath: "/Library/Application Support/NoHalla/dns-restore.json")
}