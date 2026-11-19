//
//  SettingsAdvancedView.swift
//  NoHalla
//
//  Advanced settings tab (design §7.4, FR-8/22/27/32, spec D11/D14): IP-check
//  endpoints v4/v6 (edit + reset to defaults), manual resume bypass 0–60, log
//  level Info/Debug (D11), Export diagnostics (NSSavePanel → DiagnosticsExporter),
//  and a destructive Reset all settings with confirmation.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsAdvancedView: View {
    @EnvironmentObject var appState: AppState
    @State private var editingEndpoint: (family: String, index: Int)?
    @State private var showEndpointEditor = false
    @State private var exportError: String?

    var body: some View {
        Form {
            Section(L10n.string("ui.ip-check-endpoints")) {
                endpointList(title: "IPv4", endpoints: appState.config.ipCheck.endpointsV4, family: "v4")
                endpointList(title: "IPv6", endpoints: appState.config.ipCheck.endpointsV6, family: "v6")
                Button(L10n.string("ui.reset-to-defaults")) { resetEndpoints() }
                    .buttonStyle(.bordered)
            }

            Section(L10n.string("ui.preferences")) {
                SettingRowView(label: L10n.string("ui.manual-resume-bypass")) {
                    HStack {
                        Slider(value: Binding(
                            get: { Double(appState.config.protection.manualResumeBypassMinutes) },
                            set: { newValue in
                                var config = appState.config
                                config.protection.manualResumeBypassMinutes = Int(newValue)
                                appState.setConfig(config)
                            }
                        ), in: 0...60, step: 1)
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
                    .frame(width: 160)
                }
            }

            Section {
                Button(L10n.string("ui.export-diagnostics")) { exportDiagnostics() }
                    .buttonStyle(.bordered)
                if let exportError = exportError {
                    Text(exportError)
                        .font(.system(size: DesignTokens.typeSmall))
                        .foregroundStyle(DesignTokens.red)
                }
                Button(L10n.string("ui.reset-all-settings")) { resetAll() }
                    .buttonStyle(.bordered)
                    .foregroundStyle(DesignTokens.red)
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showEndpointEditor) {
            if let editing = editingEndpoint {
                let endpoints = editing.family == "v4" ? appState.config.ipCheck.endpointsV4 : appState.config.ipCheck.endpointsV6
                EndpointEditor(
                    original: endpoints.indices.contains(editing.index) ? endpoints[editing.index] : "",
                    onSave: { value in saveEndpoint(value); showEndpointEditor = false },
                    onCancel: { showEndpointEditor = false }
                )
            }
        }
    }

    private func endpointList(title: String, endpoints: [String], family: String) -> some View {
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
                    Button(L10n.string("ui.edit")) { editingEndpoint = (family, index); showEndpointEditor = true }
                        .buttonStyle(.borderless)
                }
            }
        }
    }

    private func saveEndpoint(_ value: String) {
        guard let editing = editingEndpoint else { return }
        var config = appState.config
        if editing.family == "v4" {
            if config.ipCheck.endpointsV4.indices.contains(editing.index) { config.ipCheck.endpointsV4[editing.index] = value }
        } else {
            if config.ipCheck.endpointsV6.indices.contains(editing.index) { config.ipCheck.endpointsV6[editing.index] = value }
        }
        appState.setConfig(config)
    }

    private func resetEndpoints() {
        var config = appState.config
        config.ipCheck.endpointsV4 = AppConfig.defaults.ipCheck.endpointsV4
        config.ipCheck.endpointsV6 = AppConfig.defaults.ipCheck.endpointsV6
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