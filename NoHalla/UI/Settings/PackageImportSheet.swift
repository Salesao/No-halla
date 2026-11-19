//
//  PackageImportSheet.swift
//  NoHalla
//
//  Preview before an imported domain package changes the guard (D33): the
//  name, note, author and how many domains are new versus already blocked.
//

import SwiftUI
import UniformTypeIdentifiers

/// Imported document plus the counts computed against the current list.
struct PendingImport: Identifiable {
    let id = UUID()
    let document: DomainPackageDocument
    let newCount: Int
    let duplicateCount: Int
}

/// FileDocument wrapper for the export panel.
struct PackageDocumentFile: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    static var writableContentTypes: [UTType] { [.json] }

    let data: Data

    init(document: DomainPackageDocument) {
        data = (try? document.encoded()) ?? Data()
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct PackageImportSheet: View {
    let pending: PendingImport
    let onImport: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacing3) {
            Text(L10n.string("ui.domain-packages-preview-title"))
                .font(.system(size: DesignTokens.typeTitle, weight: .semibold))
                .foregroundStyle(DesignTokens.text)
            Text(pending.document.name)
                .font(.system(size: DesignTokens.typeBody, weight: .semibold))
                .foregroundStyle(DesignTokens.text)
            if let note = pending.document.note, !note.isEmpty {
                Text(note)
                    .font(.system(size: DesignTokens.typeSmall))
                    .foregroundStyle(DesignTokens.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let author = pending.document.author, !author.isEmpty {
                Text(L10n.string("ui.domain-packages-preview-author", author))
                    .font(.system(size: DesignTokens.typeSmall))
                    .foregroundStyle(DesignTokens.muted)
            }
            Text(L10n.string("ui.domain-packages-preview-count", pending.document.domains.count, pending.newCount))
                .font(.system(size: DesignTokens.typeBody))
                .foregroundStyle(DesignTokens.text)
            if pending.duplicateCount > 0 {
                Text(L10n.string("ui.domain-packages-preview-duplicates", pending.duplicateCount))
                    .font(.system(size: DesignTokens.typeSmall))
                    .foregroundStyle(DesignTokens.muted)
            }
            HStack {
                Spacer()
                Button(L10n.string("action.cancel"), action: onCancel)
                    .buttonStyle(.bordered)
                Button(L10n.string("ui.domain-packages-import-action"), action: onImport)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(DesignTokens.spacing4)
        .frame(width: 440)
        .background(DesignTokens.bg)
        .tint(DesignTokens.action)
    }
}

#Preview {
    PackageImportSheet(
        pending: PendingImport(
            document: DomainPackageDocument(name: "AI services", note: "Blocked in RU/CN", domains: ["chatgpt.com"]),
            newCount: 1,
            duplicateCount: 0
        ),
        onImport: {},
        onCancel: {}
    )
}