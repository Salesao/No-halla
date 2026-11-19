//
//  GuardRunner.swift
//  NoHallaDomainGuard
//
//  Applies the guard state to hosts, the loopback HTTP proxy, and the system
//  proxy (D48). The runner is the only place that decides ordering; privileged
//  actions are delegated to SystemProxyManager.
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

    private var proxy: HTTPProxy?
    private var systemProxy: SystemProxyManager?
    private var proxyMode: DomainGuardProxyMode = .unavailable
    private var proxySwitched = false
    private var reason = ""
    private var lastPublished = Date.distantPast
    private var lastSignature = ""
    private var lastReconcile = Date.distantPast
    private let workQueue = DispatchQueue(label: "dev.nohalla.NoHalla.guard-runner")

    init(
        config: GuardConfig,
        statePath: String,
        hostsPath: String,
        statusURL: URL,
        manifestURL: URL,
        dryRun: Bool,
        proxyPort: UInt16 = 8844
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
        workQueue.sync { runOnceLocked() }
    }

    private func runOnceLocked() -> DomainGuardStatus {
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

    /// Restores the saved system proxy and clears hosts without touching the
    /// state file. Returns false when a service could not be restored.
    @discardableResult
    func restoreOnly() -> Bool {
        workQueue.sync { restoreOnlyLocked() }
    }

    private func restoreOnlyLocked() -> Bool {
        let manager = systemProxy ?? SystemProxyManager(
            runner: ProcessRunner(),
            serviceProvider: { SystemEnvironment.services() },
            manifestURL: manifestURL,
            dryRun: dryRun
        )
        let restored = manager.restore()
        if restored {
            systemProxy = nil
            proxy?.stop()
            proxy = nil
        } else {
            systemProxy = manager
            proxy?.update(suffixes: [])
        }
        writeHosts([])
        proxyMode = restored ? .unavailable : .degraded
        proxySwitched = !restored
        reason = restored ? "restored" : "cannot restore the system proxy"
        publish(makeStatus())
        return restored
    }

    // MARK: - Apply / release

    private func applyActive(domains: [String]) {
        writeHosts(DomainBlocklist.hostsLines(for: domains))
        let suffixes = DomainBlocklist.normalized(domains)

        var justCreated = false
        if systemProxy == nil {
            let manager = SystemProxyManager(
                runner: ProcessRunner(),
                serviceProvider: { SystemEnvironment.services() },
                manifestURL: manifestURL,
                dryRun: dryRun
            )
            guard manager.restore() else {
                proxyMode = .unavailable
                proxySwitched = false
                reason = "cannot restore the previous system proxy"
                return
            }
            systemProxy = manager
            justCreated = true
        }

        if proxy == nil {
            let proxy = HTTPProxy(port: proxyPort, suffixes: suffixes)
            do {
                try proxy.start()
                self.proxy = proxy
            } catch {
                proxyMode = .unavailable
                proxySwitched = false
                reason = "cannot listen on 127.0.0.1:\(proxyPort): \(error)"
                logger.error("\(self.reason, privacy: .public)")
                systemProxy = nil
                return
            }
        }
        proxy?.update(suffixes: suffixes)

        guard let systemProxy else { return }
        if justCreated {
            let result = systemProxy.captureAndSwitch(port: proxyPort)
            apply(result)
            lastReconcile = Date()
            if case .unavailable = result { self.systemProxy = nil }
        } else if Date().timeIntervalSince(lastReconcile) >= 10 {
            let result = systemProxy.reconcile(port: proxyPort)
            apply(result)
            lastReconcile = Date()
            if case .unavailable = result { self.systemProxy = nil }
        }
    }

    private func release() {
        let manager = systemProxy ?? SystemProxyManager(
            runner: ProcessRunner(),
            serviceProvider: { SystemEnvironment.services() },
            manifestURL: manifestURL,
            dryRun: dryRun
        )
        let restored = manager.restore()
        if !restored {
            systemProxy = manager
            proxy?.update(suffixes: [])
            writeHosts([])
            proxyMode = .degraded
            proxySwitched = true
            reason = "cannot restore the system proxy"
            return
        }
        systemProxy = nil
        proxy?.stop()
        proxy = nil
        writeHosts([])
        proxyMode = .unavailable
        proxySwitched = false
        reason = "protection released"
    }

    private func apply(_ result: ProxyApplyResult) {
        switch result {
        case .applied:
            proxyMode = .active
            proxySwitched = true
            reason = ""
        case .degraded(let why):
            proxyMode = .degraded
            proxySwitched = true
            reason = why
        case .unavailable(let why):
            proxyMode = .unavailable
            proxySwitched = false
            reason = why
        }
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
            proxyMode: proxyMode,
            proxySwitched: proxySwitched,
            reason: reason,
            updatedAt: Date()
        )
    }

    private func publish(_ status: DomainGuardStatus) {
        let signature = "\(status.proxyMode.rawValue)|\(status.proxySwitched)|\(status.reason)"
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