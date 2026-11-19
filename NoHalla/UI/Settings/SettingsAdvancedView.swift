//
//  SettingsAdvancedView.swift
//  NoHalla
//
//  Advanced settings tab (design §7.4, FR-8/22/27/32, spec D11/D14): IP-check
//  endpoints (edit + reset to defaults), manual resume bypass 0–60, log
//  level Info/Debug (D11), Export diagnostics (NSSavePanel → DiagnosticsExporter),
//  and a destructive Reset all settings with confirmation.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsAdvancedView: View {
    @EnvironmentObject var appState: AppState
    private struct EndpointEdit: Identifiable {
        let index: Int
        let original: String
        var id: Int { index }
    }

    @State private var editingEndpoint: EndpointEdit?
    @State private var exportError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.spacing3) {
            SettingsSection(L10n.string("ui.ip-check-endpoints")) {
                endpointList(title: "IPv4", endpoints: appState.config.ipCheck.endpointsV4)
                Button(L10n.string("ui.reset-to-defaults")) { resetEndpoints() }
                    .buttonStyle(.bordered)
                    .tint(DesignTokens.blue)
            }

            SettingsSection(L10n.string("ui.preferences")) {
                SettingRowView(label: L10n.string("ui.manual-resume-bypass")) {
                    HStack {
                        Slider(value: Binding(
                            get: { Double(appState.config.protection.manualResumeBypassMinutes) },
                            set: { newValue in
                                let minutes = Int(newValue.rounded())
                                guard minutes != appState.config.protection.manualResumeBypassMinutes else { return }
                                var config = appState.config
                                config.protection.manualResumeBypassMinutes = minutes
                                appState.setConfig(config)
                            }
                        ), in: 0...60)
                        .accessibilityLabel(L10n.string("ui.manual-resume-bypass"))
                        .frame(width: 160)
                        Text("\(appState.config.protection.manualResumeBypassMinutes) \(L10n.string("ui.unit-minutes"))")
                            .font(.system(size: DesignTokens.typeSmall))
                            .foregroundStyle(DesignTokens.muted)
                            .frame(width: 56, alignment: .trailing)
                    }
                }
                SettingRowView(label: L10n.string("ui.log-level")) {
                    Picker("", selection: Binding(
                        get: { appState.config.logLevel },
                        set: { newValue in
                            var config = appState.config
                            config.logLevel = newValue
                            appState.setConfig(config)
                        }
                    )) {
                        Text(L10n.string("ui.log-level-info")).tag(LogLevel.info)
                        Text(L10n.string("ui.log-level-debug")).tag(LogLevel.debug)
                    }
                    .labelsHidden()
                    .accessibilityLabel(L10n.string("ui.log-level"))
                    .frame(width: 160)
                }
            }

            HStack {
                Button(L10n.string("ui.export-diagnostics")) { exportDiagnostics() }
                    .buttonStyle(.bordered)
                    .tint(DesignTokens.blue)
                Spacer()
                Button(L10n.string("ui.reset-all-settings")) { resetAll() }
                    .buttonStyle(.bordered)
                    .tint(DesignTokens.red)
            }
            if let exportError = exportError {
                Text(exportError)
                    .font(.system(size: DesignTokens.typeSmall))
                    .foregroundStyle(DesignTokens.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            }
            .padding(DesignTokens.spacing5)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(DesignTokens.bg)
        .tint(DesignTokens.action)
        .toggleStyle(.switch)
        .sheet(item: $editingEndpoint) { edit in
            EndpointEditor(
                original: edit.original,
                onSave: { value in saveEndpoint(value, at: edit.index); editingEndpoint = nil },
                onCancel: { editingEndpoint = nil }
            )
        }
    }

    private func endpointList(title: String, endpoints: [String]) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacing1) {
            Text(title)
                .font(.system(size: DesignTokens.typeSmall, weight: .semibold))
                .foregroundStyle(DesignTokens.muted)
            ForEach(Array(endpoints.enumerated()), id: \.offset) { index, endpoint in
                HStack {
                    Text(endpoint)
                        .font(.system(size: DesignTokens.typeSmall, design: .monospaced))
                        .foregroundStyle(DesignTokens.text)
                        .lineLimit(1)
                    Spacer()
                    Button(L10n.string("ui.edit")) { editingEndpoint = EndpointEdit(index: index, original: endpoint) }
                        .buttonStyle(.borderless)
                        .tint(DesignTokens.blue)
                        .accessibilityLabel("\(L10n.string("ui.edit")): \(endpoint)")
                }
            }
        }
    }

    private func saveEndpoint(_ value: String, at index: Int) {
        var config = appState.config
        if config.ipCheck.endpointsV4.indices.contains(index) { config.ipCheck.endpointsV4[index] = value }
        appState.setConfig(config)
    }

    private func resetEndpoints() {
        var config = appState.config
        config.ipCheck.endpointsV4 = AppConfig.defaults.ipCheck.endpointsV4
        appState.setConfig(config)
    }

    private func exportDiagnostics() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.nameFieldStringValue = "no-halla-diagnostics.zip"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try DiagnosticsExporter.export(to: url, configDirectory: ConfigStore.defaultDirectory)
            exportError = nil
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func resetAll() {
        guard ResetSettingsAlert.confirm() else { return }
        appState.setConfig(AppConfig.defaults)
    }
}

#Preview {
    SettingsAdvancedView()
        .environmentObject(AppState())
        .frame(width: 680, height: 520)
}
