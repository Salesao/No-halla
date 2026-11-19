//
//  DashboardView.swift
//  NoHalla
//
//  Shared protection dashboard content (status header, gate rule, network card,
//  protected apps, state-specific primary action). Reused by the menu bar
//  popover (compact, fixed width) and the main application window. User-requested
//  windowed experience: the same live state drives both surfaces.
//

import AppKit
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var appState: AppState
    @State private var showAppPicker = false

    private var snapshot: EngineSnapshot { appState.snapshot }
    private var status: UIStatus { appState.uiStatus }
    private var apps: [ProtectedApp] { appState.config.protectedApps }
    private var vpnMode: Bool { appState.config.protection.mode == .vpnInterface }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacing3) {
            header
            GateRuleView()
            protectionToggle
            NetworkCardView(
                ipv4: snapshot.currentIPv4,
                ipv6: snapshot.currentIPv6,
                vpnInterface: snapshot.vpnInterface,
                trusted: vpnMode ? snapshot.trusted : (snapshot.currentIPv4 == nil ? nil : snapshot.trusted),
                vpnMode: vpnMode,
                note: networkNote,
                onAddCurrentIP: { appState.send(.addCurrentIP) },
                onRefresh: { appState.send(.retryCheck) }
            )
            appsSection
            actionSection
        }
        .sheet(isPresented: $showAppPicker) {
            AppPickerSheet(
                existingBundleIDs: Set(apps.map { $0.bundleID }),
                onAdd: { newApps in
                    var config = appState.config
                    config.protectedApps.append(contentsOf: newApps)
                    appState.setConfig(config)
                    showAppPicker = false
                },
                onCancel: { showAppPicker = false }
            )
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacing1) {
            HStack {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: DesignTokens.typeTitle))
                    .foregroundStyle(DesignTokens.blue)
                    .accessibilityHidden(true)
                Text(L10n.string("brand.name"))
                    .font(.system(size: DesignTokens.typeTitle, weight: .semibold))
                    .foregroundStyle(DesignTokens.text)
                Spacer()
                StatusPillView(
                    status: status,
                    graceRemaining: snapshot.graceRemaining,
                    untilText: untilText
                )
            }
            Text(L10n.string(Self.statusKey(for: status) + ".lore"))
                .font(.system(size: DesignTokens.typeSmall))
                .foregroundStyle(DesignTokens.muted)
                .frame(height: 14, alignment: .leading)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    /// Master protection switch on the dashboard (owner request): the same D27
    /// semantics as Settings — off resumes everything and disables protection,
    /// on re-enables into an immediate check. Visible in every state, in both
    /// the main window and the menu bar popover (shared DashboardView).
    private var protectionToggle: some View {
        HStack {
            Text(L10n.string("ui.protection"))
                .font(.system(size: DesignTokens.typeBody, weight: .semibold))
                .foregroundStyle(DesignTokens.text)
            Spacer()
            Toggle("", isOn: Binding(
                get: { appState.config.protection.enabled },
                set: { appState.send(.setProtectionEnabled($0)) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .accessibilityLabel(L10n.string("ui.protection"))
        }
        .frame(minHeight: DesignTokens.targetMin)
    }

    // MARK: - Apps

    private var appsSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacing2) {
            HStack {
                Text(L10n.string("apps.title"))
                    .font(.system(size: DesignTokens.typeBody, weight: .semibold))
                    .foregroundStyle(DesignTokens.text)
                Spacer()
                Button(L10n.string("apps.add")) { showAppPicker = true }
                    .buttonStyle(.borderless)
                    .font(.system(size: DesignTokens.typeSmall))
            }
            if apps.isEmpty {
                emptyApps
            } else {
                ScrollView { appRows }
                    .frame(maxHeight: DesignTokens.appRow * 6 + DesignTokens.spacing2 * 5)
            }
        }
    }

    private var appRows: some View {
        VStack(spacing: DesignTokens.spacing2) {
            ForEach(apps) { app in
                AppRowView(
                    app: app,
                    runState: runState(for: app),
                    isFrozen: snapshot.frozenBundleIDs.contains(app.bundleID),
                    onToggle: { enabled in toggleApp(app, enabled: enabled) }
                )
            }
        }
    }

    private var emptyApps: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacing2) {
            GateSceneView(variant: .empty)
            Text(L10n.string("apps.empty"))
                .font(.system(size: DesignTokens.typeBody))
                .foregroundStyle(DesignTokens.muted)
            Button(L10n.string("apps.choose")) { showAppPicker = true }
                .buttonStyle(.bordered)
        }
    }

    // MARK: - Primary action

    @ViewBuilder
    private var actionSection: some View {
        switch status {
        case .protected:
            pauseMenu
        case .grace:
            VStack(alignment: .leading, spacing: DesignTokens.spacing2) {
                if let remaining = snapshot.graceRemaining {
                    CountdownBarView(remaining: remaining, total: max(remaining, appState.config.protection.graceSeconds))
                }
                HStack {
                    Button(L10n.string("action.cancel")) { appState.send(.cancelGrace) }
                        .buttonStyle(.bordered)
                    Spacer()
                    Button(L10n.string("action.freezeNow")) { appState.send(.freezeNow) }
                        .buttonStyle(.borderedProminent)
                }
            }
        case .frozen:
            VStack(alignment: .leading, spacing: DesignTokens.spacing2) {
                Button(L10n.string("action.resumeAll")) { appState.send(.resumeAll) }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                Text(L10n.string("caption.resumeBypass", appState.config.protection.manualResumeBypassMinutes))
                    .font(.system(size: DesignTokens.typeSmall))
                    .foregroundStyle(DesignTokens.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .unknown:
            HStack {
                Button(L10n.string("action.resumeAll")) { appState.send(.resumeAll) }
                    .buttonStyle(.bordered)
                Spacer()
                Button(L10n.string("action.retry")) { appState.send(.retryCheck) }
                    .buttonStyle(.borderedProminent)
            }
        case .paused:
            VStack(alignment: .leading, spacing: DesignTokens.spacing2) {
                Button(L10n.string("action.turnOn")) { appState.send(.turnOnNow) }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                if let until = snapshot.pauseUntil {
                    Text(L10n.string("ui.checking-resumes-at-14-32", Self.timeString(until)))
                        .font(.system(size: DesignTokens.typeSmall))
                        .foregroundStyle(DesignTokens.muted)
                }
            }
        case .disabled:
            // The master toggle above the network card is the single control
            // for turning protection back on; the header lore explains the state.
            EmptyView()
        case .setup:
            Button(L10n.string("network.addCurrentIP")) { appState.send(.addCurrentIP) }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
        case .bypassing:
            VStack(alignment: .leading, spacing: DesignTokens.spacing2) {
                if let until = snapshot.bypassUntil {
                    Text(L10n.string("status.bypass", Self.timeString(until)))
                        .font(.system(size: DesignTokens.typeBody))
                        .foregroundStyle(DesignTokens.text)
                }
                Text(L10n.string("ui.apps-are-running-until-protection-resumes"))
                    .font(.system(size: DesignTokens.typeSmall))
                    .foregroundStyle(DesignTokens.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Button(L10n.string("ui.resume-protection")) { appState.send(.resumeProtection) }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
            }
        case .checking:
            Button(L10n.string("status.checking")) {}
                .buttonStyle(.bordered)
                .disabled(true)
                .frame(maxWidth: .infinity)
        }
    }

    private var pauseMenu: some View {
        Menu {
            Button(L10n.string("action.pause15")) { appState.send(.pause(.minutes15)) }
            Button(L10n.string("action.pause60")) { appState.send(.pause(.hour1)) }
            Button(L10n.string("action.pauseUntilRelaunch")) { appState.send(.pause(.untilRelaunch)) }
        } label: {
            Text(L10n.string("action.pause"))
                .frame(maxWidth: .infinity)
        }
        .menuStyle(.borderedButton)
    }

    // MARK: - Helpers

    private var untilText: String? {
        if status == .paused, let until = snapshot.pauseUntil { return Self.timeString(until) }
        if status == .bypassing, let until = snapshot.bypassUntil { return Self.timeString(until) }
        return nil
    }

    private var networkNote: String? {
        if vpnMode { return nil }
        if status == .setup { return L10n.string("empty.noTrusted") }
        if snapshot.currentIPv4 == nil { return L10n.string("empty.offline") }
        return nil
    }

    private func runState(for app: ProtectedApp) -> AppRunState {
        if snapshot.frozenBundleIDs.contains(app.bundleID) { return .frozen }
        if snapshot.runningBundleIDs.contains(app.bundleID) { return .active }
        return .notRunning
    }

    private func toggleApp(_ app: ProtectedApp, enabled: Bool) {
        var config = appState.config
        if let index = config.protectedApps.firstIndex(where: { $0.bundleID == app.bundleID }) {
            config.protectedApps[index].enabled = enabled
            appState.setConfig(config)
        }
    }

    static func statusKey(for status: UIStatus) -> String {
        switch status {
        case .setup: return "status.setup"
        case .checking: return "status.checking"
        case .protected: return "status.protected"
        case .grace: return "status.grace"
        case .frozen: return "status.frozen"
        case .unknown: return "status.unknown"
        case .paused: return "status.paused"
        case .disabled: return "status.disabled"
        case .bypassing: return "status.bypass"
        }
    }

    static func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#Preview("Dashboard") {
    DashboardView()
        .environmentObject(AppState.preview(.protected))
        .padding()
        .frame(width: 480)
}