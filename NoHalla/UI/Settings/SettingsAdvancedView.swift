//
//  SettingsAdvancedView.swift
//  NoHalla
//
//  Advanced settings tab (design §7.4, FR-8/22/27/32, spec D11/D14): main and
//  fallback IP-check endpoints (add/edit/remove + reset to defaults), manual
//  resume bypass 0–60, log level Info/Debug (D11), Export diagnostics
//  (NSSavePanel → DiagnosticsExporter), and a destructive Reset all settings
//  with confirmation.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsAdvancedView: View {
    @EnvironmentObject var appState: AppState
    private struct EndpointEdit: Identifiable {
        let index: Int?
        let original: String
        let fallback: Bool
        var id: String { "\(fallback ? "fallback" : "main")-\(index.map(String.init) ?? "new")" }
    }

    @State private var editingEndpoint: EndpointEdit?
    @State private var exportError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.spacing3) {
            endpointSection(
                title: L10n.string("ui.ip-check-endpoints"),
                help: L10n.string("ui.ip-check-endpoints-help"),
                endpoints: appState.config.ipCheck.endpointsV4,
                fallback: false
            )

            endpointSection(
                title: L10n.string("ui.fallback-ip-check-endpoints"),
                help: L10n.string("ui.fallback-ip-check-endpoints-help"),
                endpoints: appState.config.ipCheck.fallbackEndpointsV4,
                fallback: true
            )

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
                title: editorTitle(for: edit),
                validate: { value in
                    validateEndpoint(value, replacing: edit.index, fallback: edit.fallback)
                },
                onSave: { value in
                    if let index = edit.index {
                        saveEndpoint(value, at: index, fallback: edit.fallback)
                    } else {
                        addEndpoint(value, fallback: edit.fallback)
                    }
                    editingEndpoint = nil
                },
                onCancel: { editingEndpoint = nil }
            )
        }
    }

    private func editorTitle(for edit: EndpointEdit) -> String {
        switch (edit.fallback, edit.index == nil) {
        case (false, true):
            return L10n.string("ui.add-ip-check-endpoint")
        case (false, false):
            return L10n.string("ui.edit-ip-check-endpoint")
        case (true, true):
            return L10n.string("ui.add-fallback-endpoint")
        case (true, false):
            return L10n.string("ui.edit-fallback-endpoint")
        }
    }

    private func endpointSection(
        title: String,
        help: String,
        endpoints: [String],
        fallback: Bool
    ) -> some View {
        SettingsSection(title) {
            Text(help)
                .font(.system(size: DesignTokens.typeSmall))
                .foregroundStyle(DesignTokens.muted)
                .fixedSize(horizontal: false, vertical: true)
            endpointList(title: "IPv4", endpoints: endpoints, fallback: fallback)
            HStack {
                Menu(L10n.string(fallback ? "ui.add-fallback-endpoint" : "ui.add-ip-check-endpoint")) {
                    ForEach(IPCheckEndpoint.presets, id: \.self) { preset in
                        Button(preset) { addEndpoint(preset, fallback: fallback) }
                            .disabled(isEndpointUsed(preset))
                    }
                    Divider()
                    Button(L10n.string("ui.custom-endpoint")) {
                        editingEndpoint = EndpointEdit(index: nil, original: "", fallback: fallback)
                    }
                }
                .buttonStyle(.bordered)
                .tint(DesignTokens.blue)
                .disabled(endpoints.count >= IPCheckEndpoint.maxCount)
                if !fallback {
                    Button(L10n.string("ui.reset-to-defaults")) { resetEndpoints() }
                        .buttonStyle(.bordered)
                        .tint(DesignTokens.blue)
                }
                Spacer()
            }
        }
    }

    private func endpointList(title: String, endpoints: [String], fallback: Bool) -> some View {
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
                    Button(L10n.string("ui.edit")) {
                        editingEndpoint = EndpointEdit(
                            index: index,
                            original: endpoint,
                            fallback: fallback
                        )
                    }
                    .buttonStyle(.borderless)
                    .tint(DesignTokens.blue)
                    .accessibilityLabel("\(L10n.string("ui.edit")): \(endpoint)")
                    Button(L10n.string("ui.remove")) {
                        removeEndpoint(at: index, fallback: fallback)
                    }
                    .buttonStyle(.borderless)
                    .tint(DesignTokens.red)
                    .disabled(!fallback && endpoints.count <= 1)
                    .accessibilityLabel("\(L10n.string("ui.remove")): \(endpoint)")
                }
            }
        }
    }

    private func endpointsArray(fallback: Bool) -> [String] {
        fallback
            ? appState.config.ipCheck.fallbackEndpointsV4
            : appState.config.ipCheck.endpointsV4
    }

    private func otherEndpoints(fallback: Bool) -> [String] {
        fallback
            ? appState.config.ipCheck.endpointsV4
            : appState.config.ipCheck.fallbackEndpointsV4
    }

    private func isEndpointUsed(_ value: String) -> Bool {
        appState.config.ipCheck.endpointsV4.contains(value)
            || appState.config.ipCheck.fallbackEndpointsV4.contains(value)
    }

    private func setEndpoints(_ endpoints: [String], fallback: Bool) {
        var config = appState.config
        if fallback {
            config.ipCheck.fallbackEndpointsV4 = endpoints
        } else {
            config.ipCheck.endpointsV4 = endpoints
        }
        appState.setConfig(config)
    }

    private func saveEndpoint(_ value: String, at index: Int, fallback: Bool) {
        var endpoints = endpointsArray(fallback: fallback)
        guard endpoints.indices.contains(index) else { return }
        endpoints[index] = value
        setEndpoints(endpoints, fallback: fallback)
    }

    private func addEndpoint(_ value: String, fallback: Bool) {
        guard IPCheckEndpoint.isValid(value) else { return }
        var endpoints = endpointsArray(fallback: fallback)
        guard !endpoints.contains(value),
              !otherEndpoints(fallback: fallback).contains(value),
              endpoints.count < IPCheckEndpoint.maxCount
        else { return }
        endpoints.append(value)
        setEndpoints(endpoints, fallback: fallback)
    }

    private func removeEndpoint(at index: Int, fallback: Bool) {
        var endpoints = endpointsArray(fallback: fallback)
        guard endpoints.indices.contains(index) else { return }
        if !fallback && endpoints.count <= 1 { return }
        endpoints.remove(at: index)
        setEndpoints(endpoints, fallback: fallback)
    }

    private func validateEndpoint(_ value: String, replacing index: Int?, fallback: Bool) -> String? {
        let endpoints = endpointsArray(fallback: fallback)
        if let index = index, endpoints.indices.contains(index), endpoints[index] == value {
            return nil
        }
        if endpoints.contains(value) { return L10n.string("ui.endpoint-duplicate") }
        if otherEndpoints(fallback: fallback).contains(value) {
            return L10n.string("ui.endpoint-duplicate")
        }
        if index == nil && endpoints.count >= IPCheckEndpoint.maxCount {
            return L10n.string("ui.endpoint-limit", IPCheckEndpoint.maxCount)
        }
        return nil
    }

    private func resetEndpoints() {
        var config = appState.config
        config.ipCheck.endpointsV4 = AppConfig.defaults.ipCheck.endpointsV4
        config.ipCheck.fallbackEndpointsV4 = AppConfig.defaults.ipCheck.fallbackEndpointsV4
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
        .frame(width: 680, height: 620)
}