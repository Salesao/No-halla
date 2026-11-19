//
//  OnboardingAppsView.swift
//  NoHalla
//
//  Onboarding step 2 of 3 (design §7.3): choose running apps with checkboxes
//  and search; Claude/Cursor/ChatGPT are suggested only when actually running
//  (NSWorkspace bundle-ID check, brief §13); Add other app via NSOpenPanel; a
//  selection counter; Back / Continue.
//

import AppKit
import SwiftUI

struct OnboardingAppsView: View {
    @Binding var selectedApps: [ProtectedApp]
    let onBack: () -> Void
    let onContinue: () -> Void

    @State private var search = ""
    @State private var running: [RunningApp] = []

    private struct RunningApp: Identifiable {
        let bundleID: String
        let name: String
        let path: String
        var id: String { bundleID }
    }

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
                VStack(alignment: .leading, spacing: DesignTokens.spacing2) {
                    let suggested = running.filter { app in suggestions.contains { $0.bundleID == app.bundleID } }
                    if !suggested.isEmpty {
                        ForEach(suggested) { app in row(app) }
                    }
                    ForEach(filteredRunning.filter { app in !suggestions.contains { $0.bundleID == app.bundleID } }) { app in
                        row(app)
                    }
                }
            }

            HStack {
                Button(L10n.string("ui.add-other-app"), action: addOtherApp)
                    .buttonStyle(.bordered)
                Spacer()
                Text(L10n.string("ui.2-apps-selected", selectedApps.count))
                    .font(.system(size: DesignTokens.typeSmall))
                    .foregroundStyle(DesignTokens.muted)
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
        .onAppear(perform: loadRunning)
    }

    private func row(_ app: RunningApp) -> some View {
        let isSelected = selectedApps.contains { $0.bundleID == app.bundleID }
        return HStack(spacing: DesignTokens.spacing2) {
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
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                .resizable()
                .frame(width: DesignTokens.appIcon, height: DesignTokens.appIcon)
            Text(app.name)
                .font(.system(size: DesignTokens.typeBody))
                .foregroundStyle(DesignTokens.text)
            Spacer()
        }
        .frame(minHeight: DesignTokens.targetMin)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(app.name)
        .accessibilityValue(isSelected ? L10n.string("ui.yes") : L10n.string("ui.no"))
    }

    private var filteredRunning: [RunningApp] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return running }
        return running.filter { $0.name.lowercased().contains(query) || $0.bundleID.lowercased().contains(query) }
    }

    private func loadRunning() {
        let selfBundle = Bundle.main.bundleIdentifier ?? "dev.nohalla.NoHalla"
        running = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != selfBundle }
            .compactMap { app in
                guard let bundleID = app.bundleIdentifier, let url = app.bundleURL else { return nil }
                return RunningApp(bundleID: bundleID, name: app.localizedName ?? bundleID, path: url.path)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func addOtherApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
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
        .frame(width: 560, height: 420)
}