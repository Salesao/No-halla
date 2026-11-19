//
//  AppPickerSheet.swift
//  NoHalla
//
//  Add-apps sheet (implementation brief FR-15/17/28, design §7.5). Running apps
//  plus /Applications, search by name and bundle ID, native checkboxes, an
//  "Added" disabled state for duplicates, yellow warnings for system and
//  Terminal-like apps (SafetyGuard.pickerWarning), Cancel/Add (Add disabled
//  without a selection) and "Add other app" via NSOpenPanel.
//

import AppKit
import SwiftUI

struct AppPickerSheet: View {
    struct PickerApp: Identifiable, Hashable {
        let bundleID: String
        let name: String
        let path: String
        var id: String { bundleID }
    }

    let existingBundleIDs: Set<String>
    let onAdd: ([ProtectedApp]) -> Void
    let onCancel: () -> Void

    @State private var search = ""
    @State private var selected: Set<String> = []
    @State private var running: [PickerApp] = []
    @State private var installed: [PickerApp] = []

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacing3) {
            Text(L10n.string("ui.add-apps"))
                .font(.system(size: DesignTokens.typeTitle, weight: .semibold))
                .foregroundStyle(DesignTokens.text)

            TextField(L10n.string("ui.search-applications"), text: $search)
                .textFieldStyle(.roundedBorder)

            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.spacing3) {
                    if !filteredRunning.isEmpty {
                        section(title: L10n.string("ui.running"), apps: filteredRunning)
                    }
                    if !filteredInstalled.isEmpty {
                        section(title: L10n.string("ui.applications"), apps: filteredInstalled)
                    }
                    if filteredRunning.isEmpty && filteredInstalled.isEmpty {
                        Text(L10n.string("ui.no-matching-applications"))
                            .font(.system(size: DesignTokens.typeBody))
                            .foregroundStyle(DesignTokens.muted)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, DesignTokens.spacing5)
                    }
                }
            }

            HStack {
                Button(L10n.string("ui.add-other-app"), action: addOtherApp)
                    .buttonStyle(.bordered)
                Spacer()
                Button(L10n.string("action.cancel"), action: onCancel)
                    .buttonStyle(.bordered)
                Button(L10n.string("ui.add"), action: confirmAdd)
                    .buttonStyle(.borderedProminent)
                    .disabled(selected.isEmpty)
            }
        }
        .padding(DesignTokens.spacing4)
        .frame(width: DesignTokens.pickerWidth, height: DesignTokens.pickerHeight)
        .onAppear(perform: loadApps)
    }

    private func section(title: String, apps: [PickerApp]) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacing1) {
            Text(title)
                .font(.system(size: DesignTokens.typeSmall, weight: .semibold))
                .foregroundStyle(DesignTokens.muted)
            ForEach(apps) { app in
                row(app)
            }
        }
    }

    private func row(_ app: PickerApp) -> some View {
        let added = existingBundleIDs.contains(app.bundleID)
        let warningKey = SafetyGuard.pickerWarning(for: app.bundleID, name: app.name)
        let isSystem = warningKey == "ui.system-app-can-t-be-protected"
        let disabled = added || isSystem
        return HStack(spacing: DesignTokens.spacing2) {
            Toggle(isOn: Binding(
                get: { selected.contains(app.bundleID) },
                set: { isOn in
                    if isOn { selected.insert(app.bundleID) } else { selected.remove(app.bundleID) }
                }
            )) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            .disabled(disabled)
            .labelsHidden()

            Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                .resizable()
                .frame(width: DesignTokens.appIcon, height: DesignTokens.appIcon)

            VStack(alignment: .leading, spacing: 0) {
                Text(app.name)
                    .font(.system(size: DesignTokens.typeBody))
                    .foregroundStyle(DesignTokens.text)
                    .lineLimit(1)
                Text(app.bundleID)
                    .font(.system(size: DesignTokens.typeSmall))
                    .foregroundStyle(DesignTokens.muted)
                    .lineLimit(1)
                if let warningKey = warningKey {
                    Text(L10n.string(warningKey))
                        .font(.system(size: DesignTokens.typeSmall))
                        .foregroundStyle(DesignTokens.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            if added {
                Text(L10n.string("ui.added"))
                    .font(.system(size: DesignTokens.typeSmall))
                    .foregroundStyle(DesignTokens.muted)
            }
        }
        .padding(.vertical, DesignTokens.spacing1)
        .frame(minHeight: DesignTokens.targetMin)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rowAccessibility(app, added: added, warningKey: warningKey))
        .accessibilityAddTraits(disabled ? .isButton : [])
    }

    private func rowAccessibility(_ app: PickerApp, added: Bool, warningKey: String?) -> String {
        var parts = [app.name, app.bundleID]
        if added { parts.append(L10n.string("ui.added")) }
        if let warningKey = warningKey { parts.append(L10n.string(warningKey)) }
        return parts.joined(separator: ", ")
    }

    // MARK: - Data

    private var filteredRunning: [PickerApp] { filter(running) }
    private var filteredInstalled: [PickerApp] {
        let runningIDs = Set(running.map { $0.bundleID })
        return filter(installed).filter { !runningIDs.contains($0.bundleID) }
    }

    private func filter(_ apps: [PickerApp]) -> [PickerApp] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return apps }
        return apps.filter { $0.name.lowercased().contains(query) || $0.bundleID.lowercased().contains(query) }
    }

    private func loadApps() {
        let selfBundle = Bundle.main.bundleIdentifier ?? "dev.nohalla.NoHalla"
        running = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != selfBundle }
            .compactMap { app in
                guard let bundleID = app.bundleIdentifier, let url = app.bundleURL else { return nil }
                return PickerApp(bundleID: bundleID, name: app.localizedName ?? bundleID, path: url.path)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        var found: [PickerApp] = []
        let applications = URL(fileURLWithPath: "/Applications", isDirectory: true)
        let entries = (try? FileManager.default.contentsOfDirectory(at: applications, includingPropertiesForKeys: nil)) ?? []
        for url in entries where url.pathExtension == "app" {
            guard let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier else { continue }
            let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? url.deletingPathExtension().lastPathComponent
            found.append(PickerApp(bundleID: bundleID, name: name, path: url.path))
        }
        installed = found.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func addOtherApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier else { continue }
            if !existingBundleIDs.contains(bundleID) {
                selected.insert(bundleID)
                let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                if !running.contains(where: { $0.bundleID == bundleID }) && !installed.contains(where: { $0.bundleID == bundleID }) {
                    installed.append(PickerApp(bundleID: bundleID, name: name, path: url.path))
                }
            }
        }
    }

    private func confirmAdd() {
        let all = running + installed
        let apps = selected.compactMap { bundleID -> ProtectedApp? in
            guard !existingBundleIDs.contains(bundleID),
                  let app = all.first(where: { $0.bundleID == bundleID }) else { return nil }
            return ProtectedApp(bundleID: app.bundleID, name: app.name, enabled: true)
        }
        onAdd(apps)
    }
}

#Preview("App picker") {
    AppPickerSheet(existingBundleIDs: ["com.anthropic.claudefordesktop"], onAdd: { _ in }, onCancel: {})
}