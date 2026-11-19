//
//  OnboardingDomainsView.swift
//  NoHalla
//
//  Onboarding step 4 of 4 (D36): optional blocked hostnames. Reuses the
//  Settings domain editor and the shared blocklist validation; packages and
//  the root helper stay a Settings concern after onboarding.
//

import SwiftUI

struct OnboardingDomainsView: View {
    @EnvironmentObject var appState: AppState
    let onBack: () -> Void
    let onFinish: () -> Void

    @State private var editingDomain: String?
    @State private var showEditor = false
    @State private var isDropTargeted = false
    @State private var dropMessage: String?
    @State private var dropFailed = false

    private var canFinish: Bool {
        appState.config.protection.mode == .vpnInterface
            || !appState.config.trustedAddresses.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.spacing3) {
                    Text(L10n.string("onboarding.4.title"))
                        .font(.system(size: DesignTokens.typeTitle, weight: .semibold))
                        .foregroundStyle(DesignTokens.text)
                    Text(L10n.string("onboarding.4.body"))
                        .font(.system(size: DesignTokens.typeBody))
                        .foregroundStyle(DesignTokens.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: DesignTokens.spacing2) {
                        ForEach(appState.config.domainBlocklist, id: \.self) { domain in
                            HStack {
                                Text(domain)
                                    .font(.system(size: DesignTokens.typeBody, design: .monospaced))
                                    .foregroundStyle(DesignTokens.text)
                                Spacer()
                                Button(L10n.string("ui.remove")) { removeDomain(domain) }
                                    .buttonStyle(.borderless)
                                    .foregroundStyle(DesignTokens.red)
                            }
                        }
                        Button(L10n.string("ui.domain-guard-add")) {
                            editingDomain = nil
                            showEditor = true
                        }
                        .buttonStyle(.bordered)
                        .tint(DesignTokens.blue)
                        Text(L10n.string("ui.domain-list-drop-hint"))
                            .font(.system(size: DesignTokens.typeSmall))
                            .foregroundStyle(DesignTokens.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        if let dropMessage = dropMessage {
                            Text(dropMessage)
                                .font(.system(size: DesignTokens.typeSmall))
                                .foregroundStyle(dropFailed ? DesignTokens.red : DesignTokens.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text(L10n.string("onboarding.4.helper"))
                            .font(.system(size: DesignTokens.typeSmall))
                            .foregroundStyle(DesignTokens.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(DesignTokens.spacing3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DesignTokens.surface, in: RoundedRectangle(cornerRadius: DesignTokens.radiusCard))
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.radiusCard)
                            .strokeBorder(isDropTargeted ? DesignTokens.action : DesignTokens.line,
                                          lineWidth: isDropTargeted ? 2 : 0.5)
                    )
                    .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                        handleDrop(providers)
                    }

                    // D42: install the helper here too, not only in Settings.
                    DomainGuardInstallView()
                        .padding(DesignTokens.spacing3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(DesignTokens.surface, in: RoundedRectangle(cornerRadius: DesignTokens.radiusCard))
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignTokens.radiusCard)
                                .strokeBorder(DesignTokens.line, lineWidth: 0.5)
                        )

                    if !canFinish {
                        Text(L10n.string("onboarding.3.need-ip"))
                            .font(.system(size: DesignTokens.typeSmall))
                            .foregroundStyle(DesignTokens.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(DesignTokens.spacing5)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Button(L10n.string("ui.back"), action: onBack)
                    .buttonStyle(.bordered)
                Spacer()
                Button(L10n.string("ui.finish"), action: onFinish)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canFinish)
            }
            .padding(.horizontal, DesignTokens.spacing5)
            .padding(.vertical, DesignTokens.spacing3)
            .background(DesignTokens.chrome)
        }
        .tint(DesignTokens.action)
        .sheet(isPresented: $showEditor) {
            DomainEditor(
                original: editingDomain,
                onSave: { value in saveDomain(value); showEditor = false },
                onCancel: { showEditor = false }
            )
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        dropMessage = nil
        DomainDrop.loadFileURL(from: provider) { url in
            guard let url else { return }
            DispatchQueue.main.async { importList(url) }
        }
        return true
    }

    private func importList(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
            guard size <= DomainListImport.maxBytes else { throw DomainListImportError.tooLarge }
            let result = try DomainListImport.parse(Data(contentsOf: url))
            var config = appState.config
            let existing = Set(config.domainBlocklist)
            let added = result.domains.filter { !existing.contains($0) }
            config.domainBlocklist.append(contentsOf: added)
            appState.setConfig(config)
            dropFailed = false
            if added.isEmpty && result.skipped == 0 {
                dropMessage = L10n.string("ui.domain-list-none-new")
            } else if result.skipped > 0 {
                dropMessage = L10n.string("ui.domain-list-added-skipped", added.count, result.skipped)
            } else {
                dropMessage = L10n.string("ui.domain-list-added", added.count)
            }
        } catch {
            dropFailed = true
            if let importError = error as? DomainListImportError {
                switch importError {
                case .tooLarge:
                    dropMessage = L10n.string("ui.domain-list-too-large")
                case .empty:
                    dropMessage = L10n.string("ui.domain-list-empty")
                case .unreadable:
                    dropMessage = L10n.string("ui.domain-list-import-failed")
                }
            } else {
                dropMessage = L10n.string("ui.domain-list-import-failed")
            }
        }
    }

    private func saveDomain(_ value: String) {
        guard let domain = DomainBlocklist.normalize(value) else { return }
        var config = appState.config
        if let original = editingDomain, let index = config.domainBlocklist.firstIndex(of: original) {
            config.domainBlocklist[index] = domain
        } else if !config.domainBlocklist.contains(domain) {
            config.domainBlocklist.append(domain)
        }
        appState.setConfig(config)
    }

    private func removeDomain(_ domain: String) {
        var config = appState.config
        config.domainBlocklist.removeAll { $0 == domain }
        appState.setConfig(config)
    }
}

#Preview {
    OnboardingDomainsView(onBack: {}, onFinish: {})
        .environmentObject(AppState())
        .frame(width: 560, height: 460)
}