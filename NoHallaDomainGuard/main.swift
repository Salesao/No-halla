//
//  main.swift
//  NoHallaDomainGuard
//
//  Root LaunchDaemon (D32/D47): reads the app-written
//  ~/Library/Application Support/NoHalla/domain-guard.json and keeps the marked
//  hosts section and the loopback DNS proxy in sync with the protection state.
//
//  Security boundary: the only user-controlled input is that JSON file. It is
//  read with lstat checks (regular file, install-time uid, size cap), and its
//  domains are re-validated here. Privileged paths come from the root-owned
//  guard.plist, never from the state file.
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

let arguments = CommandLine.arguments
if arguments.contains("--version") {
    print("domainGuardProtocol=\(DomainGuardProtocol.version)")
    exit(0)
}

let dryRun = arguments.contains("--dry-run")
let runOnce = arguments.contains("--once")
let restoreOnly = arguments.contains("--restore")

var proxyPort: UInt16 = 8844
var positional: [String] = []
var index = 1
while index < arguments.count {
    let argument = arguments[index]
    if argument == "--port", index + 1 < arguments.count, let port = UInt16(arguments[index + 1]) {
        proxyPort = port
        index += 2
        continue
    }
    if !argument.hasPrefix("--") { positional.append(argument) }
    index += 1
}

let configPath = positional.first ?? defaultConfigPath
guard let config = loadConfig(configPath) else {
    logger.error("Cannot load guard config at \(configPath, privacy: .public)")
    exit(2)
}

let stateDirectory = URL(fileURLWithPath: config.statePath).deletingLastPathComponent()
let manifestURL = dryRun ? stateDirectory.appendingPathComponent("proxy-restore.json") : DomainGuardProtocol.manifestURL
let statusURL = dryRun ? stateDirectory.appendingPathComponent("guard-status.json") : DomainGuardProtocol.statusURL

let runner = GuardRunner(
    config: config,
    statePath: config.statePath,
    hostsPath: config.hostsPath,
    statusURL: statusURL,
    manifestURL: manifestURL,
    dryRun: dryRun,
    proxyPort: proxyPort
)

if restoreOnly {
    exit(runner.restoreOnly() ? 0 : 1)
}
if runOnce {
    _ = runner.runOnce()
    exit(0)
}

logger.notice("Domain guard started (poll \((config.pollSeconds ?? 1), privacy: .public)s)")
let signalQueue = DispatchQueue(label: "dev.nohalla.NoHalla.guard-signal")
let signalSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: signalQueue)
signal(SIGTERM, SIG_IGN)
signalSource.setEventHandler {
    runner.restoreOnly()
    exit(0)
}
signalSource.resume()

repeat {
    _ = runner.runOnce()
    Thread.sleep(forTimeInterval: max(0.2, config.pollSeconds ?? 1))
} while true
