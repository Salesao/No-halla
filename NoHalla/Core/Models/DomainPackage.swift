//
//  DomainPackage.swift
//  NoHalla
//
//  Shareable domain packages (D33): a small JSON document a person can send
//  to another. Import is treated as untrusted input — strict schema, size cap
//  and domain re-validation; packages never carry executable content.
//

import Foundation

/// One imported package stored in config.json. `id` is local (the file has no
/// stable identity); `enabled` toggles its contribution without deleting it.
struct DomainPackage: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var note: String?
    var domains: [String]
    var enabled: Bool

    init(
        id: String = UUID().uuidString,
        name: String,
        note: String? = nil,
        domains: [String],
        enabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.note = note
        self.domains = domains
        self.enabled = enabled
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, note, domains, enabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        note = try container.decodeIfPresent(String.self, forKey: .note)
        domains = try container.decodeIfPresent([String].self, forKey: .domains) ?? []
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }
}

/// On-disk/wire format of a shared package. This is what people exchange.
struct DomainPackageDocument: Codable, Equatable {
    static let currentSchemaVersion = 1
    static let maxBytes = 1_048_576
    static let maxDomains = 256
    static let maxNameLength = 80
    static let maxNoteLength = 500
    static let maxAuthorLength = 80

    var schemaVersion: Int
    var name: String
    var note: String?
    var author: String?
    var domains: [String]

    enum PackageError: Error {
        case tooLarge
        case unsupportedVersion
        case invalidJSON
        case empty
    }

    init(name: String, note: String? = nil, author: String? = nil, domains: [String]) {
        self.schemaVersion = Self.currentSchemaVersion
        self.name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxNameLength))
        self.note = note.map { String($0.prefix(Self.maxNoteLength)) }
        self.author = author.map { String($0.prefix(Self.maxAuthorLength)) }
        self.domains = DomainBlocklist.normalized(domains)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, name, note, author, domains
    }

    /// Decodes and sanitizes an untrusted package. Invalid domains are dropped;
    /// a document with no valid domain left is rejected.
    static func decode(_ data: Data) throws -> DomainPackageDocument {
        guard data.count <= maxBytes else { throw PackageError.tooLarge }
        guard let document = try? JSONDecoder().decode(DomainPackageDocument.self, from: data) else {
            throw PackageError.invalidJSON
        }
        guard document.schemaVersion == currentSchemaVersion else { throw PackageError.unsupportedVersion }
        let domains = DomainBlocklist.normalized(document.domains)
        guard !domains.isEmpty else { throw PackageError.empty }
        return DomainPackageDocument(
            name: document.name.isEmpty ? "Package" : document.name,
            note: document.note,
            author: document.author,
            domains: domains
        )
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}