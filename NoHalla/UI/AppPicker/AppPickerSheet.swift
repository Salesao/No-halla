//
//  AppPickerSheet.swift
//  NoHalla
//
//  Add-apps sheet (implementation brief FR-15/17/28, design §7.5). Running apps
//  plus /Applications, search by name and bundle ID, native checkboxes, an
//  checked, disabled state for duplicates, yellow warnings for system and
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
                LazyVStack(alignment: .leading, spacing: 0) {
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
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 150)
            .background(DesignTokens.surface, in: RoundedRectangle(cornerRadius: DesignTokens.radiusCard))
            .overlay(RoundedRectangle(cornerRadius: DesignTokens.radiusCard).strokeBorder(DesignTokens.line, lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.radiusCard))

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
        .background(DesignTokens.bg)
        .tint(DesignTokens.action)
        .onAppear(perform: loadApps)
    }

    private func section(title: String, apps: [PickerApp]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: DesignTokens.typeSmall, weight: .semibold))
                .foregroundStyle(DesignTokens.muted)
                .padding(.horizontal, DesignTokens.spacing3)
                .padding(.top, DesignTokens.spacing3)
                .padding(.bottom, DesignTokens.spacing1)
            ForEach(apps) { app in
                row(app)
                if app.id != apps.last?.id {
                    Rectangle()
                        .fill(DesignTokens.line)
                        .frame(height: 0.5)
                        .padding(.leading, DesignTokens.appIcon + DesignTokens.spacing2)
                }
            }
            .padding(.horizontal, DesignTokens.spacing3)
            .padding(.bottom, DesignTokens.spacing1)
        }
    }

    private func row(_ app: PickerApp) -> some View {
        let added = existingBundleIDs.contains(app.bundleID)
        let warningKey = SafetyGuard.pickerWarning(for: app.bundleID, name: app.name)
        let isSystem = warningKey == "ui.system-app-can-t-be-protected"
        let disabled = added || isSystem
        return HStack(alignment: .center, spacing: DesignTokens.spacing2) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                .resizable()
                .frame(width: DesignTokens.appIcon, height: DesignTokens.appIcon)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(app.name)
                    .font(.system(size: DesignTokens.typeBody, weight: .medium))
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
                        .padding(.top, DesignTokens.spacing1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityHidden(true)

            Toggle(isOn: Binding(
                // D44: already protected apps stay checked and unavailable.
                get: { added || selected.contains(app.bundleID) },
                set: { isOn in
                    if isOn { selected.insert(app.bundleID) } else { selected.remove(app.bundleID) }
                }
            )) { EmptyView() }
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(disabled)
                .frame(width: DesignTokens.targetMin, height: DesignTokens.targetMin)
                .accessibilityLabel(rowAccessibility(app, added: added, warningKey: warningKey))
        }
        .padding(.vertical, DesignTokens.spacing2)
        .frame(minHeight: DesignTokens.appRow)
        .accessibilityElement(children: .contain)
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
        running = InstalledAppCatalog.running(excluding: selfBundle).map {
            PickerApp(bundleID: $0.bundleID, name: $0.name, path: $0.path)
        }
        let runningIDs = Set(running.map(\.bundleID))
        installed = InstalledAppCatalog.installed()
            .filter { !runningIDs.contains($0.bundleID) }
            .map { PickerApp(bundleID: $0.bundleID, name: $0.name, path: $0.path) }
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
