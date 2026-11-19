//
//  SystemProxy.swift
//  NoHallaDomainGuard
//
//  Reversible system web/secure proxy switch (D48). The manifest is persisted
//  before the first change, so a crash can always restore the exact state.
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

enum ProxyApplyResult: Equatable {
    case applied
    case unavailable(String)
    case degraded(String)
}

enum SystemEnvironment {
    /// Enabled services on real interfaces; VPN/PPP/tunnel services are left
    /// alone so their own routing and settings keep working.
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

final class SystemProxyManager {
    private struct ProxyState: Equatable {
        var enabled: Bool
        var server: String
        var port: Int
    }

    private static let networksetup = "/usr/sbin/networksetup"
    private static let loopback = Set(["127.0.0.1", "::1"])

    private let runner: CommandRunning
    private let services: [NetworkServiceInfo]
    private let manifestURL: URL
    private let dryRun: Bool
    private let logger = Logger(subsystem: "dev.nohalla.NoHalla", category: "proxy")

    private(set) var manifest: ProxyRestoreManifest?
    private(set) var isActive = false

    init(runner: CommandRunning, services: [NetworkServiceInfo], manifestURL: URL, dryRun: Bool) {
        self.runner = runner
        self.services = services.filter(Self.isSwitchable)
        self.manifestURL = manifestURL
        self.dryRun = dryRun
    }

    func captureAndSwitch(port: UInt16) -> ProxyApplyResult {
        if manifest == nil { manifest = loadManifest() }
        if manifest != nil { _ = restore() }
        guard !services.isEmpty else { return .unavailable("no enabled network services") }

        manifest = ProxyRestoreManifest(schemaVersion: 1, services: [])
        var degraded: String?
        for service in services where !(manifest?.services.contains { $0.name == service.name } ?? false) {
            guard capture(service) else {
                degraded = degraded ?? "cannot read proxy state for \(service.name)"
                continue
            }
        }
        guard manifest?.services.isEmpty == false else {
            return .unavailable(degraded ?? "no service could be captured")
        }
        for service in manifest?.services ?? [] {
            if !set(service.name, port: port) {
                degraded = degraded ?? "cannot set proxy for \(service.name)"
            }
        }
        isActive = true
        if let degraded { return .degraded(degraded) }
        return .applied
    }

    func reconcile(port: UInt16) -> ProxyApplyResult {
        guard isActive else { return .unavailable("not active") }
        var degraded: String?
        for service in services where !(manifest?.services.contains { $0.name == service.name } ?? false) {
            guard capture(service) else {
                degraded = degraded ?? "cannot read proxy state for \(service.name)"
                continue
            }
        }
        for service in manifest?.services ?? [] {
            let portValue = Int(port)
            let web = read(service.name, secure: false)
            let secure = read(service.name, secure: true)
            if web == nil || secure == nil {
                degraded = degraded ?? "cannot read proxy state for \(service.name)"
                continue
            }
            let webOK = web!.enabled && web!.server == "127.0.0.1" && web!.port == portValue
            let secureOK = secure!.enabled && secure!.server == "127.0.0.1" && secure!.port == portValue
            if !webOK || !secureOK, !set(service.name, port: port) {
                degraded = degraded ?? "cannot set proxy for \(service.name)"
            }
        }
        if let degraded { return .degraded(degraded) }
        return .applied
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
            let web = ProxyState(enabled: service.webEnabled, server: service.webServer, port: service.webPort)
            let secure = ProxyState(enabled: service.secureEnabled, server: service.secureServer, port: service.securePort)
            if !apply(service.name, state: web, secure: false) { allSet = false }
            if !apply(service.name, state: secure, secure: true) { allSet = false }
        }
        if !dryRun { try? FileManager.default.removeItem(at: manifestURL) }
        manifest = nil
        isActive = false
        return allSet
    }

    // MARK: - Internals

    private static func isSwitchable(_ service: NetworkServiceInfo) -> Bool {
        if ["PPP", "IPSec", "VPN"].contains(service.interfaceType) { return false }
        if let bsd = service.bsdName,
           bsd.hasPrefix("utun") || bsd.hasPrefix("ppp") || bsd.hasPrefix("ipsec") {
            return false
        }
        return true
    }

    private func capture(_ service: NetworkServiceInfo) -> Bool {
        guard let web = read(service.name, secure: false),
              let secure = read(service.name, secure: true) else {
            return false
        }
        if (web.enabled && Self.loopback.contains(web.server)) ||
            (secure.enabled && Self.loopback.contains(secure.server)) {
            logger.error("Refusing to reuse a loopback proxy on \(service.name, privacy: .public)")
            return false
        }
        manifest?.services.append(.init(
            name: service.name,
            webEnabled: web.enabled,
            webServer: web.server,
            webPort: web.port,
            secureEnabled: secure.enabled,
            secureServer: secure.server,
            securePort: secure.port
        ))
        persist()
        return true
    }

    private func read(_ service: String, secure: Bool) -> ProxyState? {
        let result = runner.run(Self.networksetup, [secure ? "-getsecurewebproxy" : "-getwebproxy", service])
        guard result.status == 0 else { return nil }
        var state = ProxyState(enabled: false, server: "", port: 0)
        for line in result.output.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: ":", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard parts.count == 2 else { continue }
            switch parts[0] {
            case "Enabled": state.enabled = parts[1].lowercased() == "yes"
            case "Server": state.server = parts[1]
            case "Port": state.port = Int(parts[1]) ?? 0
            default: break
            }
        }
        return state
    }

    private func set(_ service: String, port: UInt16) -> Bool {
        var ok = true
        ok = command(["-setwebproxy", service, "127.0.0.1", "\(port)"]) && ok
        ok = command(["-setwebproxystate", service, "on"]) && ok
        ok = command(["-setsecurewebproxy", service, "127.0.0.1", "\(port)"]) && ok
        ok = command(["-setsecurewebproxystate", service, "on"]) && ok
        return ok
    }

    private func apply(_ service: String, state: ProxyState, secure: Bool) -> Bool {
        let setOK = command([
            secure ? "-setsecurewebproxy" : "-setwebproxy",
            service,
            state.server,
            "\(state.port)",
        ])
        let stateOK = command([
            secure ? "-setsecurewebproxystate" : "-setwebproxystate",
            service,
            state.enabled ? "on" : "off",
        ])
        return setOK && stateOK
    }

    private func command(_ arguments: [String]) -> Bool {
        if dryRun {
            print("dry-run: networksetup \(arguments.joined(separator: " "))")
            fflush(stdout)
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
            logger.error("Cannot save proxy restore manifest: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func loadManifest() -> ProxyRestoreManifest? {
        guard let data = try? Data(contentsOf: manifestURL) else { return nil }
        return try? JSONDecoder().decode(ProxyRestoreManifest.self, from: data)
    }
}