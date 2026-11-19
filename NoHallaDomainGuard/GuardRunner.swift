//
//  GuardRunner.swift
//  NoHallaDomainGuard
//
//  Applies the guard state to hosts, the loopback DNS proxy, and system DNS
//  (D47). The runner is the only place that decides ordering; every privileged
//  action is delegated to SystemDNSManager.
//

import Darwin
import Foundation
import os

final class GuardRunner {
    private let config: GuardConfig
    private let statePath: String
    private let hostsPath: String
    private let statusURL: URL
    private let manifestURL: URL
    private let dryRun: Bool
    private let proxyPort: UInt16
    private let logger = Logger(subsystem: "dev.nohalla.NoHalla", category: "guard")

    private var proxy: DNSProxy?
    private var dns: SystemDNSManager?
    private var suffixMode: DomainGuardSuffixMode = .unavailable
    private var dnsSwitched = false
    private var reason = ""
    private var lastPublished = Date.distantPast
    private var lastSignature = ""

    init(
        config: GuardConfig,
        statePath: String,
        hostsPath: String,
        statusURL: URL,
        manifestURL: URL,
        dryRun: Bool,
        proxyPort: UInt16 = 53
    ) {
        self.config = config
        self.statePath = statePath
        self.hostsPath = hostsPath
        self.statusURL = statusURL
        self.manifestURL = manifestURL
        self.dryRun = dryRun
        self.proxyPort = proxyPort
    }

    @discardableResult
    func runOnce() -> DomainGuardStatus {
        let state = readState()
        if state?.active == true {
            applyActive(domains: state?.domains ?? [])
        } else {
            release()
        }
        let status = makeStatus()
        publish(status)
        return status
    }

    /// Restores saved DNS and clears hosts without touching the state file.
    func restoreOnly() {
        let manager = dns ?? SystemDNSManager(
            runner: ProcessRunner(),
            services: SystemEnvironment.services(),
            upstreams: SystemEnvironment.upstreams(),
            manifestURL: manifestURL,
            dryRun: dryRun
        )
        _ = manager.restore()
        dns = nil
        proxy?.stop()
        proxy = nil
        writeHosts([])
        suffixMode = .unavailable
        dnsSwitched = false
        reason = "restored"
        flushDNSCache()
        publish(makeStatus())
    }

    // MARK: - Apply / release

    private func applyActive(domains: [String]) {
        writeHosts(DomainBlocklist.hostsLines(for: domains))

        if proxy == nil {
            let proxy = DNSProxy(
                port: proxyPort,
                suffixes: DomainBlocklist.normalized(domains),
                upstreams: SystemEnvironment.upstreams()
            )
            do {
                try proxy.start()
                self.proxy = proxy
            } catch {
                suffixMode = .unavailable
                dnsSwitched = false
                reason = "cannot listen on 127.0.0.1:\(proxyPort): \(error)"
                logger.error("\(self.reason, privacy: .public)")
                return
            }
        }
        proxy?.update(suffixes: DomainBlocklist.normalized(domains), upstreams: SystemEnvironment.upstreams())

        if dns == nil {
            let manager = SystemDNSManager(
                runner: ProcessRunner(),
                services: SystemEnvironment.services(),
                upstreams: SystemEnvironment.upstreams(),
                manifestURL: manifestURL,
                dryRun: dryRun
            )
            dns = manager
            apply(manager.captureAndSwitch())
            flushDNSCache()
        } else if let dns {
            apply(dns.reconcile())
        }
    }

    private func release() {
        let hadManifest = FileManager.default.fileExists(atPath: manifestURL.path)
        let wasActive = dns != nil || suffixMode != .unavailable
        let manager = dns ?? SystemDNSManager(
            runner: ProcessRunner(),
            services: SystemEnvironment.services(),
            upstreams: SystemEnvironment.upstreams(),
            manifestURL: manifestURL,
            dryRun: dryRun
        )
        _ = manager.restore()
        dns = nil
        proxy?.stop()
        proxy = nil
        writeHosts([])
        suffixMode = .unavailable
        dnsSwitched = false
        reason = "protection released"
        if wasActive || hadManifest { flushDNSCache() }
    }

    private func apply(_ result: DNSApplyResult) {
        switch result {
        case .applied:
            suffixMode = .active
            dnsSwitched = true
            reason = ""
        case .degraded(let why):
            suffixMode = .degraded
            dnsSwitched = true
            reason = why
        case .unavailable(let why):
            suffixMode = .unavailable
            dnsSwitched = false
            reason = why
        }
    }

    /// A switch to loopback only affects new lookups; the system cache would
    /// keep serving pre-block answers. Only the root helper can flush it.
    private func flushDNSCache() {
        guard !dryRun else { return }
        _ = ProcessRunner().run("/usr/bin/dscacheutil", ["-flushcache"])
        _ = ProcessRunner().run("/usr/bin/killall", ["-HUP", "mDNSResponder"])
    }

    // MARK: - State and files

    private func readState() -> DomainGuardState? {
        var info = stat()
        guard lstat(statePath, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFREG,
              info.st_uid == config.uid,
              info.st_size > 0,
              info.st_size <= 128 * 1024,
              let data = FileManager.default.contents(atPath: statePath) else {
            return nil
        }
        return try? JSONDecoder().decode(DomainGuardState.self, from: data)
    }

    private func writeHosts(_ lines: [String]) {
        guard let current = try? String(contentsOfFile: hostsPath, encoding: .utf8) else {
            logger.error("Cannot read \(self.hostsPath, privacy: .public)")
            return
        }
        let updated = DomainBlocklist.merged(hosts: current, blockLines: lines)
        guard updated != current else { return }
        let tempPath = hostsPath + ".nohalla.tmp"
        do {
            try updated.write(toFile: tempPath, atomically: false, encoding: .utf8)
            chmod(tempPath, 0o644)
            guard rename(tempPath, hostsPath) == 0 else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
        } catch {
            logger.error("Failed to update \(self.hostsPath, privacy: .public): \(error.localizedDescription, privacy: .public)")
            unlink(tempPath)
        }
    }

    private func makeStatus() -> DomainGuardStatus {
        DomainGuardStatus(
            protocolVersion: DomainGuardProtocol.version,
            suffixMode: suffixMode,
            dnsSwitched: dnsSwitched,
            reason: reason,
            updatedAt: Date()
        )
    }

    private func publish(_ status: DomainGuardStatus) {
        let signature = "\(status.suffixMode.rawValue)|\(status.dnsSwitched)|\(status.reason)"
        let now = Date()
        if signature == lastSignature, now.timeIntervalSince(lastPublished) < 30 { return }
        do {
            try FileManager.default.createDirectory(
                at: statusURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o755]
            )
            let data = try JSONEncoder().encode(status)
            try data.write(to: statusURL, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: statusURL.path)
            lastSignature = signature
            lastPublished = now
        } catch {
            logger.error("Cannot write guard status: \(error.localizedDescription, privacy: .public)")
        }
    }
}