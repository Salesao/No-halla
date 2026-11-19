//
//  OnboardingAppsView.swift
//  NoHalla
//
//  Onboarding step 2 of 4 (design §7.3, D38/D40): choose running and installed
//  apps with checkboxes and search, and choose per selected app whether the app
//  itself or only its agent terminal sessions freeze (same choice as Settings).
//  Claude/Cursor/ChatGPT are suggested first when actually running (NSWorkspace
//  bundle-ID check, brief §13); Add other app via NSOpenPanel; a selection
//  counter; an explicit empty state; Back / Continue.
//

import AppKit
import SwiftUI

struct OnboardingAppsView: View {
    @Binding var selectedApps: [ProtectedApp]
    let onBack: () -> Void
    let onContinue: () -> Void

    @State private var search = ""
    @State private var running: [AppCatalogEntry] = []
    @State private var installed: [AppCatalogEntry] = []

    private let suggestions: [(bundleID: String, name: String)] = [
        ("com.anthropic.claudefordesktop", "Claude"),
        ("com.todesktop.230313mzl4w4u92", "Cursor"),
        ("com.openai.chat", "ChatGPT")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacing3) {
            Text(L10n.string("onboarding.2.title"))
                .font(.system(size: DesignTokens.typeTitle, weight: .semibold))
                .foregroundStyle(DesignTokens.text)
            TextField(L10n.string("ui.search-applications"), text: $search)
                .textFieldStyle(.roundedBorder)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !filteredRunning.isEmpty {
                        section(L10n.string("ui.running"), apps: filteredRunning)
                    }
                    if !filteredInstalled.isEmpty {
                        section(L10n.string("ui.applications"), apps: filteredInstalled)
                    }
                    if filteredRunning.isEmpty && filteredInstalled.isEmpty {
                        Text(L10n.string("ui.no-matching-applications"))
                            .font(.system(size: DesignTokens.typeBody))
                            .foregroundStyle(DesignTokens.muted)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, DesignTokens.spacing5)
                    }
                }
                .padding(.horizontal, DesignTokens.spacing2)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 150)
            .background(DesignTokens.surface, in: RoundedRectangle(cornerRadius: DesignTokens.radiusCard))
            .overlay(RoundedRectangle(cornerRadius: DesignTokens.radiusCard).strokeBorder(DesignTokens.line, lineWidth: 0.5))

            HStack {
                Button(L10n.string("ui.add-other-app"), action: addOtherApp)
                    .buttonStyle(.bordered)
                Spacer()
                Text(L10n.string("ui.2-apps-selected", selectedApps.count))
                    .font(.system(size: DesignTokens.typeSmall))
                    .foregroundStyle(DesignTokens.muted)
            }

            if selectedApps.contains(where: { $0.freezeScope == .agentTerminals }) {
                Text(L10n.string("apps.scope-agent-terminals-help"))
                    .font(.system(size: DesignTokens.typeSmall))
                    .foregroundStyle(DesignTokens.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button(L10n.string("ui.back"), action: onBack)
                    .buttonStyle(.bordered)
                Spacer()
                Button(L10n.string("ui.continue"), action: onContinue)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(DesignTokens.spacing5)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tint(DesignTokens.action)
        .task { loadApps() }
    }

    private func section(_ title: String, apps: [AppCatalogEntry]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: DesignTokens.typeSmall, weight: .semibold))
                .foregroundStyle(DesignTokens.muted)
                .padding(.top, DesignTokens.spacing2)
                .padding(.bottom, 2)
            ForEach(apps) { app in row(app) }
        }
    }

    private func row(_ app: AppCatalogEntry) -> some View {
        let selected = selectedApps.first { $0.bundleID == app.bundleID }
        let isSelected = selected != nil
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: DesignTokens.spacing2) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                    .resizable()
                    .frame(width: DesignTokens.appIcon, height: DesignTokens.appIcon)
                VStack(alignment: .leading, spacing: 1) {
                    Text(app.name)
                        .font(.system(size: DesignTokens.typeBody, weight: .medium))
                        .foregroundStyle(DesignTokens.text)
                    Text(app.bundleID)
                        .font(.system(size: DesignTokens.typeSmall))
                        .foregroundStyle(DesignTokens.muted)
                        .lineLimit(1)
                }
                Spacer()
                Toggle(isOn: Binding(
                    get: { isSelected },
                    set: { isOn in
                        if isOn {
                            if !isSelected { selectedApps.append(ProtectedApp(bundleID: app.bundleID, name: app.name, enabled: true)) }
                        } else {
                            selectedApps.removeAll { $0.bundleID == app.bundleID }
                        }
                    }
                )) { EmptyView() }
                .toggleStyle(.checkbox)
                .labelsHidden()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(app.name)
            .accessibilityValue(isSelected ? L10n.string("ui.yes") : L10n.string("ui.no"))

            // D38: the same per-app choice as Settings — the app itself or only
            // the agent terminal sessions it hosts.
            if isSelected {
                HStack(spacing: DesignTokens.spacing2) {
                    Text(L10n.string("apps.freeze-scope"))
                        .font(.system(size: DesignTokens.typeSmall))
                        .foregroundStyle(DesignTokens.muted)
                    Picker("", selection: Binding(
                        get: { selected?.freezeScope ?? .app },
                        set: { scope in
                            guard let index = selectedApps.firstIndex(where: { $0.bundleID == app.bundleID }) else { return }
                            selectedApps[index].freezeScope = scope
                        }
                    )) {
                        Text(L10n.string("apps.scope-app")).tag(FreezeScope.app)
                        Text(L10n.string("apps.scope-agent-terminals")).tag(FreezeScope.agentTerminals)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 260)
                    .accessibilityLabel("\(app.name): \(L10n.string("apps.freeze-scope"))")
                    Spacer(minLength: 0)
                }
                .padding(.leading, DesignTokens.appIcon + DesignTokens.spacing2)
            }
        }
        .padding(.vertical, 2)
        .frame(minHeight: DesignTokens.appRow)
    }

    private var filteredRunning: [AppCatalogEntry] {
        filter(running)
    }

    private var filteredInstalled: [AppCatalogEntry] {
        let runningIDs = Set(running.map(\.bundleID))
        return filter(installed).filter { !runningIDs.contains($0.bundleID) }
    }

    private func filter(_ apps: [AppCatalogEntry]) -> [AppCatalogEntry] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return apps }
        return apps.filter { $0.name.lowercased().contains(query) || $0.bundleID.lowercased().contains(query) }
    }

    private func loadApps() {
        let selfBundle = Bundle.main.bundleIdentifier ?? "dev.nohalla.NoHalla"
        // Suggested apps first among the running ones, then alphabetical.
        running = InstalledAppCatalog.running(excluding: selfBundle).sorted { lhs, rhs in
            let left = suggestions.firstIndex { $0.bundleID == lhs.bundleID } ?? Int.max
            let right = suggestions.firstIndex { $0.bundleID == rhs.bundleID } ?? Int.max
            if left != right { return left < right }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        let runningIDs = Set(running.map(\.bundleID))
        installed = InstalledAppCatalog.installed().filter { !runningIDs.contains($0.bundleID) }
    }

    private func addOtherApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier else { continue }
            if !selectedApps.contains(where: { $0.bundleID == bundleID }) {
                let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                selectedApps.append(ProtectedApp(bundleID: bundleID, name: name, enabled: true))
            }
        }
    }
}

#Preview {
    OnboardingAppsView(selectedApps: .constant([]), onBack: {}, onContinue: {})
        .frame(width: 560, height: 460)
}