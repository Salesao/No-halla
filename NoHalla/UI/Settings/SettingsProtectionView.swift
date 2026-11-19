//
//  SettingsProtectionView.swift
//  NoHalla
//
//  Protection settings tab (design §7.4, FR-10/13/14/21/27, spec D19/D24/D27/D31):
//  grace slider 0–120 (D24), check interval 10–120 (D19), freeze-when-unknown /
//  require-VPN toggles, trusted IPs (add/remove/edit + Add current IP) and
//  protected apps (add/remove via the app picker). D31: the master Protection
//  switch lives on the dashboard only; editing the trusted list restarts
//  protection immediately. Changes apply to config/engine right away.
//

import SwiftUI
import UniformTypeIdentifiers

struct SettingsProtectionView: View {
    @EnvironmentObject var appState: AppState
    @State private var showAppPicker = false
    private struct AddressEdit: Identifiable {
        let id = UUID()
        let original: String?
    }

    @State private var editingAddress: AddressEdit?
    @State private var editingDomain: String?
    @State private var showDomainEditor = false
    @State private var showPackageImporter = false
    @State private var showPackageExporter = false
    @State private var isPackageDropTargeted = false
    @State private var isDomainDropTargeted = false
    @State private var domainDropMessage: String?
    @State private var domainDropFailed = false
    @State private var pendingImport: PendingImport?
    @State private var importError: String?
    @State private var exportDocument = PackageDocumentFile(document: DomainPackageDocument(name: "package", domains: []))
    @State private var exportFilename = "domains.json"

    private var protection: ProtectionSettings { appState.config.protection }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.spacing3) {
                SettingsSection(L10n.string("ui.protection-mode")) {
                    Picker("", selection: Binding(
                        get: { protection.mode },
                        set: { newValue in updateProtection { $0.mode = newValue } }
                    )) {
                        Text(L10n.string("ui.mode-vpn")).tag(ProtectionMode.vpnInterface)
                        Text(L10n.string("ui.mode-ip")).tag(ProtectionMode.ipWhitelist)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Text(protection.mode == .vpnInterface ? L10n.string("ui.mode-vpn-helper") : L10n.string("ui.mode-ip-helper"))
                        .font(.system(size: DesignTokens.typeSmall))
                        .foregroundStyle(DesignTokens.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                SettingsSection(L10n.string("ui.trusted-ips")) {
                    ForEach(appState.config.trustedAddresses, id: \.self) { address in
                        HStack {
                            Text(address)
                                .font(.system(size: DesignTokens.typeBody, design: .monospaced))
                                .foregroundStyle(DesignTokens.text)
                            Spacer()
                            Button(L10n.string("ui.edit")) { editingAddress = AddressEdit(original: address) }
                                .buttonStyle(.borderless)
                                .tint(DesignTokens.blue)
                                .accessibilityLabel("\(L10n.string("ui.edit")): \(address)")
                            Button(L10n.string("ui.remove")) { removeAddress(address) }
                                .buttonStyle(.borderless)
                                .foregroundStyle(DesignTokens.red)
                                .accessibilityLabel("\(L10n.string("ui.remove")): \(address)")
                        }
                    }
                    HStack {
                        Button(L10n.string("ui.add")) { editingAddress = AddressEdit(original: nil) }
                            .buttonStyle(.bordered)
                            .tint(DesignTokens.blue)
                        Button(L10n.string("network.addCurrentIP")) { appState.send(.addCurrentIP) }
                            .buttonStyle(.bordered)
                            .tint(DesignTokens.blue)
                    }
                }

                SettingsSection(L10n.string("ui.domain-guard")) {
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
                    Button(L10n.string("ui.domain-guard-add")) { editingDomain = nil; showDomainEditor = true }
                        .buttonStyle(.bordered)
                        .tint(DesignTokens.blue)
                    Text(L10n.string("ui.domain-list-drop-hint"))
                        .font(.system(size: DesignTokens.typeSmall))
                        .foregroundStyle(DesignTokens.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    if let domainDropMessage = domainDropMessage {
                        Text(domainDropMessage)
                            .font(.system(size: DesignTokens.typeSmall))
                            .foregroundStyle(domainDropFailed ? DesignTokens.red : DesignTokens.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(L10n.string("ui.domain-guard-helper"))
                        .font(.system(size: DesignTokens.typeSmall))
                        .foregroundStyle(DesignTokens.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    DomainGuardInstallView(showsUninstall: true)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.radiusCard)
                        .strokeBorder(DesignTokens.action, lineWidth: 2)
                        .opacity(isDomainDropTargeted ? 1 : 0)
                        .allowsHitTesting(false)
                )
                .onDrop(of: [.fileURL], isTargeted: $isDomainDropTargeted) { providers in
                    handleDomainDrop(providers)
                }

                SettingsSection(L10n.string("ui.domain-packages")) {
                    ForEach(appState.config.domainPackages) { package in
                        HStack(spacing: DesignTokens.spacing2) {
                            Toggle("", isOn: Binding(
                                get: { package.enabled },
                                set: { newValue in setPackageEnabled(newValue, id: package.id) }
                            ))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .accessibilityLabel("\(package.name): \(L10n.string("ui.domain-packages-enabled"))")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(package.name)
                                    .font(.system(size: DesignTokens.typeBody))
                                    .foregroundStyle(DesignTokens.text)
                                Text(L10n.string("ui.domain-packages-domain-count", package.domains.count))
                                    .font(.system(size: DesignTokens.typeSmall))
                                    .foregroundStyle(DesignTokens.muted)
                            }
                            .onDrag { packageProvider(for: package) }
                            .help(L10n.string("ui.domain-packages-drag"))
                            Spacer()
                            Button {
                                export(package)
                            } label: {
                                Image(systemName: "square.and.arrow.up")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(L10n.string("ui.domain-packages-export"))
                            Button(L10n.string("ui.remove")) { removePackage(package.id) }
                                .buttonStyle(.borderless)
                                .foregroundStyle(DesignTokens.red)
                        }
                    }
                    if appState.config.domainPackages.isEmpty {
                        Text(L10n.string("ui.domain-packages-empty"))
                            .font(.system(size: DesignTokens.typeSmall))
                            .foregroundStyle(DesignTokens.muted)
                    }
                    HStack {
                        Button(L10n.string("ui.domain-packages-import")) { showPackageImporter = true }
                            .buttonStyle(.bordered)
                            .tint(DesignTokens.blue)
                        if !appState.config.domainBlocklist.isEmpty {
                            Button(L10n.string("ui.domain-packages-export-list")) { exportManualList() }
                                .buttonStyle(.bordered)
                                .tint(DesignTokens.blue)
                        }
                    }
                    Text(L10n.string("ui.domain-packages-helper"))
                        .font(.system(size: DesignTokens.typeSmall))
                        .foregroundStyle(DesignTokens.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.radiusCard)
                        .strokeBorder(DesignTokens.action, lineWidth: 2)
                        .opacity(isPackageDropTargeted ? 1 : 0)
                        .allowsHitTesting(false)
                )
                .onDrop(of: [.fileURL], isTargeted: $isPackageDropTargeted) { providers in
                    handlePackageDrop(providers)
                }

                SettingsSection(L10n.string("apps.title")) {
                    ForEach(Array(appState.config.protectedApps.enumerated()), id: \.element.id) { index, app in
                        if index > 0 {
                            Divider().overlay(DesignTokens.line)
                                .padding(.vertical, DesignTokens.spacing1)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: DesignTokens.spacing2) {
                                ProtectedAppIconView(bundleID: app.bundleID)
                                Text(app.name)
                                    .font(.system(size: DesignTokens.typeBody))
                                    .foregroundStyle(DesignTokens.text)
                                Spacer()
                                Text(appState.snapshot.runningBundleIDs.contains(app.bundleID) ? L10n.string("ui.running") : L10n.string("apps.notRunning"))
                                    .font(.system(size: DesignTokens.typeSmall))
                                    .foregroundStyle(DesignTokens.muted)
                                Button(L10n.string("ui.remove")) { removeApp(app) }
                                    .buttonStyle(.borderless)
                                    .foregroundStyle(DesignTokens.red)
                                    .accessibilityLabel("\(L10n.string("ui.remove")): \(app.name)")
                            }
                            // D30: choose what freezes. `.app` stops the app;
                            // `.agentTerminals` leaves it running and stops only
                            // Claude Code/Codex sessions started in its terminals.
                            HStack(spacing: DesignTokens.spacing2) {
                                Text(L10n.string("apps.freeze-scope"))
                                    .font(.system(size: DesignTokens.typeSmall))
                                    .foregroundStyle(DesignTokens.muted)
                                Picker("", selection: Binding(
                                    get: { app.freezeScope },
                                    set: { newValue in setFreezeScope(newValue, for: app) }
                                )) {
                                    Text(L10n.string("apps.scope-app")).tag(FreezeScope.app)
                                    Text(L10n.string("apps.scope-agent-terminals")).tag(FreezeScope.agentTerminals)
                                }
                                .pickerStyle(.segmented)
                                .labelsHidden()
                                .frame(maxWidth: 300)
                                .accessibilityLabel("\(L10n.string("apps.freeze-scope")): \(app.name)")
                                Spacer(minLength: 0)
                            }
                            .padding(.leading, DesignTokens.appIcon + DesignTokens.spacing2)
                        }
                    }
                    Button(L10n.string("apps.add")) { showAppPicker = true }
                        .buttonStyle(.bordered)
                        .tint(DesignTokens.blue)
                    if appState.config.protectedApps.contains(where: { $0.freezeScope == .agentTerminals }) {
                        Text(L10n.string("apps.scope-agent-terminals-help"))
                            .font(.system(size: DesignTokens.typeSmall))
                            .foregroundStyle(DesignTokens.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(L10n.string("apps.scope-agent-terminals-caveat"))
                            .font(.system(size: DesignTokens.typeSmall))
                            .foregroundStyle(DesignTokens.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                SettingsSection(L10n.string("ui.preferences")) {
                    VStack(alignment: .leading, spacing: DesignTokens.spacing1) {
                        Text(L10n.string("ui.grace-period"))
                            .font(.system(size: DesignTokens.typeBody))
                            .foregroundStyle(DesignTokens.text)
                        Text(L10n.string("ui.apps-freeze-after-this-delay-when-the-ip-changes"))
                            .font(.system(size: DesignTokens.typeSmall))
                            .foregroundStyle(DesignTokens.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Slider(value: Binding(
                                get: { Double(protection.graceSeconds) },
                                set: { newValue in
                                    let seconds = Int(newValue.rounded())
                                    guard seconds != protection.graceSeconds else { return }
                                    updateProtection { $0.graceSeconds = seconds }
                                }
                            ), in: 0...120)
                            .accessibilityLabel(L10n.string("ui.grace-period"))
                            Text("\(protection.graceSeconds) \(L10n.string("ui.unit-seconds"))")
                                .font(.system(size: DesignTokens.typeSmall))
                                .foregroundStyle(DesignTokens.muted)
                                .frame(width: 48, alignment: .trailing)
                        }
                    }
                    Divider().overlay(DesignTokens.line)
                    VStack(alignment: .leading, spacing: DesignTokens.spacing1) {
                        Text(L10n.string("ui.check-interval"))
                            .font(.system(size: DesignTokens.typeBody))
                            .foregroundStyle(DesignTokens.text)
                        HStack {
                            Slider(value: Binding(
                                get: { Double(protection.checkIntervalSeconds) },
                                set: { newValue in
                                    let seconds = Int(newValue.rounded())
                                    guard seconds != protection.checkIntervalSeconds else { return }
                                    updateProtection { $0.checkIntervalSeconds = seconds }
                                }
                            ), in: 10...120)
                            .accessibilityLabel(L10n.string("ui.check-interval"))
                            Text("\(protection.checkIntervalSeconds) \(L10n.string("ui.unit-seconds"))")
                                .font(.system(size: DesignTokens.typeSmall))
                                .foregroundStyle(DesignTokens.muted)
                                .frame(width: 48, alignment: .trailing)
                        }
                    }
                    Divider().overlay(DesignTokens.line)
                    SettingRowView(label: L10n.string("ui.freeze-when-ip-can-t-be-verified")) {
                        Toggle("", isOn: Binding(
                            get: { protection.freezeWhenUnknown },
                            set: { newValue in updateProtection { $0.freezeWhenUnknown = newValue } }
                        ))
                        .labelsHidden()
                        .accessibilityLabel(L10n.string("ui.freeze-when-ip-can-t-be-verified"))
                    }
                    SettingRowView(label: L10n.string("ui.require-active-vpn-interface"), helper: L10n.string("ui.protection-requires-an-active-tunnel-when-this-is-on")) {
                        Toggle("", isOn: Binding(
                            get: { protection.requireVPNInterface },
                            set: { newValue in updateProtection { $0.requireVPNInterface = newValue } }
                        ))
                        .labelsHidden()
                        .accessibilityLabel(L10n.string("ui.require-active-vpn-interface"))
                    }
                }

            }
            .padding(DesignTokens.spacing5)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(DesignTokens.bg)
        .tint(DesignTokens.action)
        .toggleStyle(.switch)
        .sheet(item: $editingAddress) { edit in
            TrustedAddressEditor(
                original: edit.original,
                onSave: { value in saveAddress(value, original: edit.original); editingAddress = nil },
                onCancel: { editingAddress = nil }
            )
        }
        .sheet(isPresented: $showDomainEditor) {
            DomainEditor(
                original: editingDomain,
                onSave: { value in saveDomain(value); showDomainEditor = false },
                onCancel: { showDomainEditor = false }
            )
        }
        .sheet(isPresented: $showAppPicker) {
            AppPickerSheet(
                existingBundleIDs: Set(appState.config.protectedApps.map { $0.bundleID }),
                onAdd: { newApps in
                    var config = appState.config
                    config.protectedApps.append(contentsOf: newApps)
                    appState.setConfig(config)
                    showAppPicker = false
                },
                onCancel: { showAppPicker = false }
            )
        }
        // D33: package preview, then the system import/export panels.
        .sheet(item: $pendingImport) { item in
            PackageImportSheet(
                pending: item,
                onImport: { addPackage(item.document); pendingImport = nil },
                onCancel: { pendingImport = nil }
            )
        }
        .fileImporter(
            isPresented: $showPackageImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .fileExporter(
            isPresented: $showPackageExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: exportFilename
        ) { _ in }
        .alert(
            L10n.string("ui.domain-packages-import-failed"),
            isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )
        ) {
            Button(L10n.string("ui.ok")) { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }

    private func updateProtection(_ mutate: (inout ProtectionSettings) -> Void) {
        var config = appState.config
        mutate(&config.protection)
        appState.setConfig(config)
    }

    private func saveAddress(_ value: String, original: String?) {
        var config = appState.config
        if let original = original, let index = config.trustedAddresses.firstIndex(of: original) {
            config.trustedAddresses[index] = value
        } else if !config.trustedAddresses.contains(value) {
            config.trustedAddresses.append(value)
        }
        appState.setConfig(config)
    }

    private func removeAddress(_ address: String) {
        var config = appState.config
        config.trustedAddresses.removeAll { $0 == address }
        appState.setConfig(config)
    }

    private func saveDomain(_ value: String) {
        guard let domain = DomainBlocklist.normalize(value) else { return }
        var config = appState.config
        if let original = editingDomain, let index = config.domainBlocklist.firstIndex(of: original) {
            config.domainBlocklist[index] = domain
        } else if !config.domainBlocklist.contains(domain) {
            guard config.domainBlocklist.count < DomainBlocklist.maxDomains else {
                reportDomainLimit()
                return
            }
            config.domainBlocklist.append(domain)
        }
        appState.setConfig(config)
    }

    private func reportDomainLimit() {
        domainDropMessage = L10n.string("ui.domain-guard-limit")
        domainDropFailed = true
    }

    private func removeDomain(_ domain: String) {
        var config = appState.config
        config.domainBlocklist.removeAll { $0 == domain }
        appState.setConfig(config)
    }

    /// D37: drop a `.txt`/`.json` domain list to merge it into the manual list.
    private func handleDomainDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        domainDropMessage = nil
        DomainDrop.loadFileURL(from: provider) { url in
            guard let url else { return }
            DispatchQueue.main.async { importDomainList(url) }
        }
        return true
    }

    private func importDomainList(_ url: URL) {
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
            guard added.count <= max(0, DomainBlocklist.maxDomains - config.domainBlocklist.count) else {
                reportDomainLimit()
                return
            }
            config.domainBlocklist.append(contentsOf: added)
            appState.setConfig(config)
            domainDropFailed = false
            if added.isEmpty && result.skipped == 0 {
                domainDropMessage = L10n.string("ui.domain-list-none-new")
            } else if result.skipped > 0 {
                domainDropMessage = L10n.string("ui.domain-list-added-skipped", added.count, result.skipped)
            } else {
                domainDropMessage = L10n.string("ui.domain-list-added", added.count)
            }
        } catch {
            domainDropFailed = true
            if let importError = error as? DomainListImportError {
                switch importError {
                case .tooLarge:
                    domainDropMessage = L10n.string("ui.domain-list-too-large")
                case .empty:
                    domainDropMessage = L10n.string("ui.domain-list-empty")
                case .unreadable:
                    domainDropMessage = L10n.string("ui.domain-list-import-failed")
                }
            } else {
                domainDropMessage = L10n.string("ui.domain-list-import-failed")
            }
        }
    }

    private func setPackageEnabled(_ enabled: Bool, id: String) {
        var config = appState.config
        guard let index = config.domainPackages.firstIndex(where: { $0.id == id }) else { return }
        config.domainPackages[index].enabled = enabled
        appState.setConfig(config)
    }

    private func removePackage(_ id: String) {
        var config = appState.config
        config.domainPackages.removeAll { $0.id == id }
        appState.setConfig(config)
    }

    private func addPackage(_ document: DomainPackageDocument) {
        var config = appState.config
        guard config.domainPackages.count < 32 else {
            importError = L10n.string("ui.domain-packages-limit")
            return
        }
        config.domainPackages.append(
            DomainPackage(name: document.name, note: document.note, domains: document.domains)
        )
        appState.setConfig(config)
    }

    private func export(_ package: DomainPackage) {
        exportDocument = PackageDocumentFile(
            document: DomainPackageDocument(name: package.name, note: package.note, domains: package.domains)
        )
        exportFilename = fileName(for: package.name)
        showPackageExporter = true
    }

    private func exportManualList() {
        let name = L10n.string("ui.domain-guard")
        exportDocument = PackageDocumentFile(
            document: DomainPackageDocument(name: name, domains: appState.config.domainBlocklist)
        )
        exportFilename = fileName(for: name)
        showPackageExporter = true
    }

    private func fileName(for name: String) -> String {
        let cleaned = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (cleaned.isEmpty ? "domains" : cleaned) + ".json"
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        importPackageFile(url)
    }

    /// Shared by the file panel and drag-and-drop: validate, then show the
    /// preview. The callbacks from NSItemProvider arrive off the main queue.
    private func importPackageFile(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
            guard size <= DomainPackageDocument.maxBytes else {
                throw DomainPackageDocument.PackageError.tooLarge
            }
            let document = try DomainPackageDocument.decode(Data(contentsOf: url))
            let existing = Set(appState.config.effectiveDomainBlocklist)
            let newCount = document.domains.filter { !existing.contains($0) }.count
            pendingImport = PendingImport(
                document: document,
                newCount: newCount,
                duplicateCount: document.domains.count - newCount
            )
        } catch {
            importError = importErrorMessage(error)
        }
    }

    /// D33: a dropped .json package goes through the same validation and
    /// preview as the Import panel. Only the first file is taken.
    private func handlePackageDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first,
              provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let url: URL?
            switch item {
            case let data as Data:
                url = URL(dataRepresentation: data, relativeTo: nil)
            case let string as String:
                url = URL(string: string)
            case let nsURL as NSURL:
                url = nsURL as URL
            default:
                url = nil
            }
            guard let url else { return }
            DispatchQueue.main.async { importPackageFile(url) }
        }
        return true
    }

    /// D33: writes the package to a temp file so dragging to Finder or another
    /// app produces a real .json document.
    private func packageProvider(for package: DomainPackage) -> NSItemProvider {
        let document = DomainPackageDocument(name: package.name, note: package.note, domains: package.domains)
        guard let data = try? document.encoded() else { return NSItemProvider() }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("No-halla-packages", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent(fileName(for: package.name))
            try data.write(to: url, options: .atomic)
            return NSItemProvider(contentsOf: url) ?? NSItemProvider()
        } catch {
            return NSItemProvider()
        }
    }

    private func importErrorMessage(_ error: Error) -> String {
        if let packageError = error as? DomainPackageDocument.PackageError {
            switch packageError {
            case .tooLarge:
                return L10n.string("ui.domain-packages-too-large")
            case .unsupportedVersion:
                return L10n.string("ui.domain-packages-unsupported")
            case .invalidJSON, .empty:
                break
            }
        }
        return L10n.string("ui.domain-packages-invalid")
    }

    private func removeApp(_ app: ProtectedApp) {
        var config = appState.config
        config.protectedApps.removeAll { $0.bundleID == app.bundleID }
        appState.setConfig(config)
    }

    /// D30: persists the per-app freeze scope. The engine reconciles on the
    /// next 5 s pass — freezing agent sessions or resuming revoked ones.
    private func setFreezeScope(_ value: FreezeScope, for app: ProtectedApp) {
        var config = appState.config
        guard let index = config.protectedApps.firstIndex(where: { $0.bundleID == app.bundleID }) else { return }
        config.protectedApps[index].freezeScope = value
        appState.setConfig(config)
    }
}

#Preview {
    SettingsProtectionView()
        .environmentObject(AppState())
        .frame(width: 680, height: 520)
}
