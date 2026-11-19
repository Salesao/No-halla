//
//  BlockedSitesCard.swift
//  NoHalla
//
//  Dashboard shortcut for the D32 blocked-site list: shows the effective
//  domains (manual + enabled packages) and lets the user add or remove one
//  without opening Settings. DashboardView decides visibility: the card is
//  only useful when the root helper is installed and the list is not empty.
//  Input and persistence follow Settings → Protection (DomainEditor +
//  DomainBlocklist + AppState.setConfig).
//

import SwiftUI

struct BlockedSitesCard: View {
    /// Effective blocked domains, already normalized and deduped.
    let domains: [String]
    /// Adds a normalized domain to the manual list. Returns false when the
    /// list is full; true when the domain was saved or already present.
    let onAdd: (String) -> Bool
    /// Removes a domain from every source that currently blocks it.
    let onRemove: (String) -> Void

    @State private var showEditor = false
    @State private var limitReached = false

    /// Rows visible before the list scrolls, matching the app list cap.
    private let maxVisibleRows = 4

    var body: some View {
        SettingsSection(L10n.string("ui.domain-guard")) {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(domains.enumerated()), id: \.element) { index, domain in
                        if index > 0 { Divider().overlay(DesignTokens.line) }
                        row(domain)
                    }
                }
            }
            .frame(height: listHeight)

            HStack(spacing: DesignTokens.spacing2) {
                Button(L10n.string("ui.domain-guard-add")) {
                    limitReached = false
                    showEditor = true
                }
                .buttonStyle(.bordered)
                .tint(DesignTokens.blue)
                .accessibilityLabel(L10n.string("ui.domain-guard-add"))
                Spacer()
            }

            Text(L10n.string("ui.domain-guard-card-helper"))
                .font(.system(size: DesignTokens.typeSmall))
                .foregroundStyle(DesignTokens.muted)
                .fixedSize(horizontal: false, vertical: true)

            if limitReached {
                Text(L10n.string("ui.domain-guard-limit"))
                    .font(.system(size: DesignTokens.typeSmall))
                    .foregroundStyle(DesignTokens.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .sheet(isPresented: $showEditor) {
            DomainEditor(
                original: nil,
                onSave: { value in
                    showEditor = false
                    limitReached = !onAdd(value)
                },
                onCancel: { showEditor = false }
            )
        }
    }

    private var listHeight: CGFloat {
        let rows = min(domains.count, maxVisibleRows)
        // One divider (1 pt) between adjacent rows keeps the frame exact.
        return CGFloat(rows) * DesignTokens.targetMin + CGFloat(max(0, rows - 1))
    }

    private func row(_ domain: String) -> some View {
        HStack(spacing: DesignTokens.spacing2) {
            Text(domain)
                .font(.system(size: DesignTokens.typeBody, design: .monospaced))
                .foregroundStyle(DesignTokens.text)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: DesignTokens.spacing2)
            Button(L10n.string("ui.remove")) { onRemove(domain) }
                .buttonStyle(.borderless)
                .foregroundStyle(DesignTokens.red)
                .accessibilityLabel("\(L10n.string("ui.remove")): \(domain)")
        }
        .frame(height: DesignTokens.targetMin)
    }
}

#Preview("Blocked sites") {
    BlockedSitesCard(
        domains: ["chatgpt.com", "claude.ai", "youtube.com", "m.youtube.com", "x.com"],
        onAdd: { _ in true },
        onRemove: { _ in }
    )
    .padding()
    .frame(width: DesignTokens.popoverWidth)
    .background(DesignTokens.bg)
    .tint(DesignTokens.action)
}