//
//  main.swift
//  NoHallaDomainGuard
//
//  Root LaunchDaemon (D32): reads the app-written
//  ~/Library/Application Support/NoHalla/domain-guard.json and keeps the
//  marked section of /etc/hosts in sync with the protection state.
//
//  Security boundary: the only user-controlled input is that JSON file. It is
//  read with lstat checks (regular file, install-time uid, size cap), and its
//  domains are re-validated here; the output is always 0.0.0.0/::1 lines
//  inside the markers. Paths come from the root-owned guard.plist, never from
//  the state file.
//

import Darwin
import Foundation
import os

struct GuardConfig: Decodable {
    let statePath: String
    let hostsPath: String
    let uid: UInt32
    let pollSeconds: Double?
}

let logger = Logger(subsystem: "dev.nohalla.NoHalla", category: "guard")
let defaultConfigPath = "/Library/Application Support/NoHalla/guard.plist"

func loadConfig(_ path: String) -> GuardConfig? {
    guard let data = FileManager.default.contents(atPath: path) else { return nil }
    return try? PropertyListDecoder().decode(GuardConfig.self, from: data)
}

/// Strict read of the user state file. Any anomaly (missing, symlink, wrong
/// owner, oversized, malformed JSON) is treated as "inactive".
func readState(_ config: GuardConfig) -> DomainGuardState? {
    var info = stat()
    guard lstat(config.statePath, &info) == 0,
          (info.st_mode & S_IFMT) == S_IFREG,
          info.st_uid == config.uid,
          info.st_size > 0,
          info.st_size <= 128 * 1024,
          let data = FileManager.default.contents(atPath: config.statePath) else { return nil }
    return try? JSONDecoder().decode(DomainGuardState.self, from: data)
}

func apply(_ config: GuardConfig) {
    let state = readState(config)
    let blockLines = state?.active == true
        ? DomainBlocklist.hostsLines(for: state?.domains ?? [])
        : []

    guard let current = try? String(contentsOfFile: config.hostsPath, encoding: .utf8) else {
        logger.error("Cannot read \(config.hostsPath, privacy: .public)")
        return
    }
    let updated = DomainBlocklist.merged(hosts: current, blockLines: blockLines)
    guard updated != current else { return }
    write(updated, to: config.hostsPath, blockedHosts: blockLines.count / 2)
}

func write(_ text: String, to path: String, blockedHosts: Int) {
    let tempPath = path + ".nohalla.tmp"
    do {
        try text.write(toFile: tempPath, atomically: false, encoding: .utf8)
        chmod(tempPath, 0o644)
        guard rename(tempPath, path) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        if blockedHosts > 0 {
            logger.notice("Domain guard active: \(blockedHosts, privacy: .public) hostnames blocked")
        } else {
            logger.notice("Domain guard inactive: block removed")
        }
    } catch {
        logger.error("Failed to update \(path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        unlink(tempPath)
    }
}

let configPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : defaultConfigPath
let runOnce = CommandLine.arguments.contains("--once")

guard let config = loadConfig(configPath) else {
    logger.error("Cannot load guard config at \(configPath, privacy: .public)")
    exit(2)
}

logger.notice("Domain guard started (poll \((config.pollSeconds ?? 1), privacy: .public)s)")

repeat {
    apply(config)
    if runOnce { break }
    Thread.sleep(forTimeInterval: max(0.2, config.pollSeconds ?? 1))
} while true