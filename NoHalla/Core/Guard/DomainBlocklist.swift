//
//  DomainBlocklist.swift
//  NoHalla
//
//  Shared, pure domain-guard rules (D32). Compiled into both the app and the
//  privileged helper, so it may only depend on Foundation — no AppKit, no
//  logging, no file I/O.
//
//  The app writes ~/Library/Application Support/NoHalla/domain-guard.json;
//  the root helper rewrites the marked section of /etc/hosts from it. Only
//  hostnames that pass `normalize` ever reach the file.
//

import Foundation

/// What the app tells the helper. Atomic write, strict decode on the helper.
struct DomainGuardState: Codable, Equatable {
    var schemaVersion: Int
    var active: Bool
    var domains: [String]
}

enum DomainBlocklist {
    static let maxDomains = 256
    static let maxHostLength = 253
    static let maxHosts = 512
    static let sectionStart = "# >>> No-halla domain guard >>>"
    static let sectionEnd = "# <<< No-halla domain guard <<<"

    /// Normalizes user input ("https://Example.com/path:443") to a bare
    /// lowercase hostname, or nil when it is not a valid DNS name. IP
    /// literals are rejected: this list is hostname-based.
    static func normalize(_ raw: String) -> String? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !value.isEmpty else { return nil }
        if let scheme = value.range(of: "://") { value = String(value[scheme.upperBound...]) }
        if let cut = value.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) {
            value = String(value[..<cut])
        }
        if let colon = value.firstIndex(of: ":") { value = String(value[..<colon]) }
        while value.hasPrefix(".") { value.removeFirst() }
        while value.hasSuffix(".") { value.removeLast() }
        guard !value.isEmpty, value.count <= maxHostLength else { return nil }

        let labels = value.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, let tld = labels.last, tld.count >= 2 else { return nil }
        guard !tld.allSatisfy({ $0.isNumber }) else { return nil }

        for label in labels {
            guard (1...63).contains(label.count) else { return nil }
            guard label.first != "-", label.last != "-" else { return nil }
            for scalar in label.unicodeScalars {
                let code = scalar.value
                let valid = (code >= 97 && code <= 122)      // a-z
                    || (code >= 48 && code <= 57)            // 0-9
                    || code == 45                            // -
                guard valid else { return nil }
            }
        }
        return value
    }

    /// Valid entries only, order-preserving, deduped, capped.
    static func normalized(_ raw: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for item in raw {
            guard let domain = normalize(item), seen.insert(domain).inserted else { continue }
            result.append(domain)
            if result.count >= maxDomains { break }
        }
        return result
    }

    /// Domains plus their `www.` variants, deduped and capped. A bare entry
    /// cannot cover arbitrary subdomains (hosts has no wildcards); the UI
    /// documents exact-host semantics.
    static func hostnames(for domains: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for domain in normalized(domains) {
            let candidates = domain.hasPrefix("www.") ? [domain] : [domain, "www." + domain]
            for host in candidates where seen.insert(host).inserted {
                result.append(host)
                if result.count >= maxHosts { return result }
            }
        }
        return result
    }

    /// Hosts entries that blackhole both address families.
    static func hostsLines(for domains: [String]) -> [String] {
        hostnames(for: domains).flatMap { ["0.0.0.0 \($0)", "::1 \($0)"] }
    }

    /// Replaces the marked section in `hosts`, leaving every other line
    /// untouched. An empty `blockLines` removes the section. Idempotent.
    static func merged(hosts: String, blockLines: [String]) -> String {
        var kept: [String] = []
        var inside = false
        for line in hosts.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == sectionStart { inside = true; continue }
            if trimmed == sectionEnd { inside = false; continue }
            if !inside { kept.append(line) }
        }
        // Keep exactly one trailing newline and no empty tail.
        while kept.last?.isEmpty == true { kept.removeLast() }
        if !blockLines.isEmpty {
            kept.append(sectionStart)
            kept.append(contentsOf: blockLines)
            kept.append(sectionEnd)
        }
        return kept.joined(separator: "\n") + "\n"
    }
}