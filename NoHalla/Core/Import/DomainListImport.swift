//
//  DomainListImport.swift
//  NoHalla
//
//  Parses a dropped domain list for the Blocked sites UI (D37). Accepts the
//  shared package JSON, a bare JSON array of hostnames, or a plain text list
//  (one per line, comma/semicolon/space separated, hosts-file lines and
//  comments tolerated). Every hostname goes through DomainBlocklist.normalize.
//

import Foundation

struct DomainListImportResult: Equatable {
    let domains: [String]
    /// Invalid entries, beyond-limit entries and non-domain tokens.
    let skipped: Int
}

enum DomainListImportError: Error {
    case tooLarge
    case empty
    case unreadable
}

enum DomainListImport {
    static let maxBytes = 1_048_576

    static func parse(_ data: Data) throws -> DomainListImportResult {
        guard data.count <= maxBytes else { throw DomainListImportError.tooLarge }
        guard !data.isEmpty else { throw DomainListImportError.empty }

        let prefix = String(decoding: data.prefix(64), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Shared package document.
        if prefix.hasPrefix("{") {
            do {
                let document = try DomainPackageDocument.decode(data)
                return DomainListImportResult(domains: document.domains, skipped: 0)
            } catch let error as DomainPackageDocument.PackageError {
                switch error {
                case .tooLarge: throw DomainListImportError.tooLarge
                case .empty: throw DomainListImportError.empty
                default: throw DomainListImportError.unreadable
                }
            } catch {
                throw DomainListImportError.unreadable
            }
        }

        // Bare JSON array of hostnames.
        if prefix.hasPrefix("["), let list = try? JSONDecoder().decode([String].self, from: data) {
            return try collect(list.map { ($0, false) })
        }

        guard let text = String(data: data, encoding: .utf8) else { throw DomainListImportError.unreadable }

        var tokens: [String] = []
        for rawLine in text.split(whereSeparator: \.isNewline) {
            var line = String(rawLine).trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), !line.hasPrefix("//") else { continue }
            if let comment = line.firstIndex(of: "#") { line = String(line[..<comment]) }
            let parts = line.split(whereSeparator: { $0 == "," || $0 == ";" || $0.isWhitespace })
            tokens.append(contentsOf: parts.map(String.init))
        }
        return try collect(tokens.map { ($0, true) })
    }

    /// Normalizes, dedupes and caps. `countInvalid` is false for the JSON
    /// array form, where every element is expected to be a hostname anyway.
    private static func collect(_ values: [(String, Bool)]) throws -> DomainListImportResult {
        var seen = Set<String>()
        var domains: [String] = []
        var skipped = 0
        for (value, countInvalid) in values {
            guard let domain = DomainBlocklist.normalize(value) else {
                if countInvalid { skipped += 1 }
                continue
            }
            guard seen.insert(domain).inserted else { continue }
            guard domains.count < DomainBlocklist.maxDomains else {
                skipped += 1
                continue
            }
            domains.append(domain)
        }
        guard !domains.isEmpty else { throw DomainListImportError.empty }
        return DomainListImportResult(domains: domains, skipped: skipped)
    }
}