//
//  DomainGuardWriter.swift
//  NoHalla
//
//  App side of the D32 domain guard. Writes the state file the root helper
//  polls: {active, domains}. The helper is the only component that touches
//  /etc/hosts; the app never needs root.
//

import Foundation

protocol DomainGuardWriting: AnyObject {
    /// Publishes "block these hostnames now" or "release" to the helper.
    /// Unchanged payloads are not rewritten.
    func update(active: Bool, domains: [String])
}

/// Atomic writer for ~/Library/Application Support/NoHalla/domain-guard.json.
final class DomainGuardWriter: DomainGuardWriting {
    private let url: URL
    private let queue = DispatchQueue(label: "dev.nohalla.NoHalla.domain-guard-writer")
    private var last: DomainGuardState?

    init(directory: URL) {
        self.url = directory.appendingPathComponent("domain-guard.json")
    }

    func update(active: Bool, domains: [String]) {
        let state = DomainGuardState(
            schemaVersion: 1,
            active: active,
            domains: DomainBlocklist.normalized(domains)
        )
        queue.sync {
            guard state != last else { return }
            do {
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                let data = try JSONEncoder().encode(state)
                try data.write(to: url, options: .atomic)
                last = state
            } catch {
                AppLog.engine.error("Domain guard write failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}