//
//  AppLog.swift
//  NoHalla
//
//  Central OSLog loggers (subsystem dev.nohalla.NoHalla) and IP masking for
//  log output (FR-39). Convention: info-level messages must only contain
//  masked IPs (use `maskIP`, e.g. 203.0.113.x); full addresses are allowed
//  in debug-level messages only. OSLog additionally redacts dynamic strings
//  at info level unless explicitly marked public.
//

import Foundation
import OSLog

/// Shared loggers, one per core subsystem category.
enum AppLog {
    static let subsystem = "dev.nohalla.NoHalla"

    static let network = Logger(subsystem: subsystem, category: "network")
    static let engine = Logger(subsystem: subsystem, category: "engine")
    static let process = Logger(subsystem: subsystem, category: "process")
    static let ui = Logger(subsystem: subsystem, category: "ui")
    static let watchdog = Logger(subsystem: subsystem, category: "watchdog")

    /// Log-safe form of an IP address: the last IPv4 octet is replaced with
    /// `x` (203.0.113.x). Input that is not an address is returned unchanged
    /// (colon-bearing text gets its last group masked as a privacy fallback).
    static func maskIP(_ ip: String) -> String {
        let trimmed = ip.trimmingCharacters(in: .whitespacesAndNewlines)
        if let address = IPAddress(trimmed) {
            return address.masked
        }
        // Textual fallback for non-canonical forms that inet_pton rejects.
        if trimmed.contains(":") {
            guard let cut = trimmed.lastIndex(of: ":") else { return trimmed }
            return String(trimmed[...cut]) + "x"
        }
        let octets = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4 else { return trimmed }
        return octets.dropLast().joined(separator: ".") + ".x"
    }
}
