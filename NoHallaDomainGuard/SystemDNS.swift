//
//  SystemDNS.swift
//  NoHallaDomainGuard
//
//  Reversible system DNS switch (D47). Everything privileged goes through
//  `/usr/sbin/networksetup`; the manifest is written before the first change,
//  so a crash can always put the original servers back.
//

import Foundation
import SystemConfiguration
import os

struct NetworkServiceInfo: Equatable {
    var name: String
    var interfaceType: String
    var bsdName: String?
}

protocol CommandRunning {
    func run(_ executable: String, _ arguments: [String]) -> (status: Int32, output: String)
}

enum DNSApplyResult: Equatable {
    case applied([String])
    case unavailable(String)
    case degraded(String)
}

enum SystemEnvironment {
    private static let networksetup = "/usr/sbin/networksetup"

    /// Enabled services on real interfaces; VPN/PPP/tunnel services are left
    /// alone so their own resolvers keep working.
    static func services() -> [NetworkServiceInfo] {
        guard let preferences = SCPreferencesCreate(nil, "NoHallaDomainGuard" as CFString, nil),
              let all = SCNetworkServiceCopyAll(preferences) as? [SCNetworkService] else {
            return []
        }
        var result: [NetworkServiceInfo] = []
        for service in all {
            guard SCNetworkServiceGetEnabled(service),
                  let name = SCNetworkServiceGetName(service) as String?,
                  let interface = SCNetworkServiceGetInterface(service),
                  let type = SCNetworkInterfaceGetInterfaceType(interface) as String? else {
                continue
            }
            let bsd = SCNetworkInterfaceGetBSDName(interface) as String?
            if type == "PPP" || type == "IPSec" || type == "VPN" { continue }
            if let bsd, bsd.hasPrefix("utun") || bsd.hasPrefix("ppp") || bsd.hasPrefix("ipsec") { continue }
            result.append(NetworkServiceInfo(name: name, interfaceType: type, bsdName: bsd))
        }
        return result
    }

    /// The resolvers the system is using before we touch anything.
    static func upstreams() -> [String] {
        guard let store = SCDynamicStoreCreate(nil, "NoHallaDomainGuard" as CFString, nil, nil),
              let value = SCDynamicStoreCopyValue(store, "State:/Network/Global/DNS" as CFString) as? [String: Any],
              let servers = value["ServerAddresses"] as? [String] else {
            return []
        }
        return servers.filter { $0 != "127.0.0.1" && $0 != "::1" }
    }
}

struct ProcessRunner: CommandRunning {
    func run(_ executable: String, _ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return (-1, "")
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}

final class SystemDNSManager {
    private static let networksetup = "/usr/sbin/networksetup"
    private static let loopback = Set(["127.0.0.1", "::1"])

    private let runner: CommandRunning
    private let services: [NetworkServiceInfo]
    private let upstreams: [String]
    private let manifestURL: URL
    private let dryRun: Bool
    private let logger = Logger(subsystem: "dev.nohalla.NoHalla", category: "dns")

    private(set) var manifest: DNSRestoreManifest?
    private(set) var isActive = false

    init(runner: CommandRunning, services: [NetworkServiceInfo], upstreams: [String], manifestURL: URL, dryRun: Bool) {
        self.runner = runner
        self.services = services.filter(Self.isSwitchable)
        self.upstreams = upstreams.filter { !Self.loopback.contains($0) }
        self.manifestURL = manifestURL
        self.dryRun = dryRun
    }

    private static func isSwitchable(_ service: NetworkServiceInfo) -> Bool {
        if ["PPP", "IPSec", "VPN"].contains(service.interfaceType) { return false }
        if let bsd = service.bsdName,
           bsd.hasPrefix("utun") || bsd.hasPrefix("ppp") || bsd.hasPrefix("ipsec") {
            return false
        }
        return true
    }

    func captureAndSwitch() -> DNSApplyResult {
        if manifest == nil { manifest = loadManifest() }
        if manifest != nil {
            // A stale manifest means an earlier run did not restore. Restore
            // before taking new values so nothing is mistaken for a fresh one.
            _ = restore()
        }
        guard !services.isEmpty else { return .unavailable("no enabled network services") }
        guard !upstreams.isEmpty else { return .unavailable("no non-loopback upstream DNS") }

        manifest = DNSRestoreManifest(schemaVersion: 1, services: [], upstreams: upstreams)
        var degraded: String?
        for service in services {
            if !capture(service) {
                degraded = degraded ?? "cannot read DNS for \(service.name)"
                continue
            }
        }
        guard manifest?.services.isEmpty == false else {
            return .unavailable(degraded ?? "no service could be captured")
        }
        for service in manifest?.services ?? [] {
            if !set(service.name, servers: ["127.0.0.1"]) {
                degraded = degraded ?? "cannot set DNS for \(service.name)"
            }
        }
        isActive = true
        if let degraded { return .degraded(degraded) }
        return .applied(upstreams)
    }

    func reconcile() -> DNSApplyResult {
        if !isActive { return .unavailable("not active") }
        guard !upstreams.isEmpty else { return .unavailable("no non-loopback upstream DNS") }
        var degraded: String?
        for service in services where !(manifest?.services.contains { $0.name == service.name } ?? false) {
            if !capture(service) {
                degraded = degraded ?? "cannot read DNS for \(service.name)"
                continue
            }
        }
        for service in manifest?.services ?? [] {
            if !set(service.name, servers: ["127.0.0.1"]) {
                degraded = degraded ?? "cannot set DNS for \(service.name)"
            }
        }
        if let degraded { return .degraded(degraded) }
        return .applied(upstreams)
    }

    @discardableResult
    func restore() -> Bool {
        let saved = manifest ?? loadManifest()
        guard let saved else {
            isActive = false
            return true
        }
        var allSet = true
        for service in saved.services {
            if !set(service.name, servers: service.servers) { allSet = false }
        }
        if !dryRun {
            try? FileManager.default.removeItem(at: manifestURL)
        }
        manifest = nil
        isActive = false
        return allSet
    }

    // MARK: - Internals

    private func capture(_ service: NetworkServiceInfo) -> Bool {
        let result = runner.run(Self.networksetup, ["-getdnsservers", service.name])
        guard result.status == 0 else { return false }
        let servers = parse(result.output)
        if servers.contains(where: { Self.loopback.contains($0) }) {
            logger.error("Refusing to reuse loopback DNS on \(service.name, privacy: .public)")
            return false
        }
        manifest?.services.append(.init(name: service.name, servers: servers))
        persist()
        return true
    }

    private func parse(_ output: String) -> [String] {
        if output.contains("There aren't any DNS Servers set") || output.contains("There are no DNS Servers") {
            return []
        }
        return output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func set(_ service: String, servers: [String]) -> Bool {
        var arguments = ["-setdnsservers", service]
        arguments.append(contentsOf: servers.isEmpty ? ["Empty"] : servers)
        if dryRun {
            logger.notice("dry-run: networksetup \(arguments.joined(separator: " "), privacy: .public)")
            return true
        }
        return runner.run(Self.networksetup, arguments).status == 0
    }

    private func persist() {
        guard let manifest, !dryRun else { return }
        do {
            try FileManager.default.createDirectory(
                at: manifestURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o755]
            )
            let data = try JSONEncoder().encode(manifest)
            try data.write(to: manifestURL, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: manifestURL.path)
        } catch {
            logger.error("Cannot save DNS restore manifest: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func loadManifest() -> DNSRestoreManifest? {
        guard let data = try? Data(contentsOf: manifestURL) else { return nil }
        return try? JSONDecoder().decode(DNSRestoreManifest.self, from: data)
    }
}