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
                vpnInterface: snapshot.vpnInterface,
                trusted: vpnMode ? snapshot.trusted : (snapshot.currentIPv4 == nil ? nil : snapshot.trusted),
                vpnMode: vpnMode,
                note: networkNote,
                onAddCurrentIP: { appState.send(.addCurrentIP) },
                onRefresh: { appState.send(.retryCheck) },
                isRefreshing: snapshot.isRefreshing
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
                Image(nsImage: AppIdentityIcon.image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: DesignTokens.typeTitle, height: DesignTokens.typeTitle)
                    .accessibilityHidden(true)
                Text(L10n.string("brand.name"))
                    .font(.system(size: DesignTokens.typeTitle, weight: .semibold))
                    .foregroundStyle(DesignTokens.text)
                Spacer()
                if status != .grace {
                    StatusPillView(status: status, untilText: untilText)
                }
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
            .controlSize(.small)
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
                    .tint(DesignTokens.blue)
                    .font(.system(size: DesignTokens.typeSmall))
            }
            if apps.isEmpty {
                emptyApps
            } else {
                ScrollView { appRows }
                    .frame(height: min(CGFloat(apps.count) * DesignTokens.appRow + CGFloat(max(0, apps.count - 1)), DesignTokens.appRow * 4))
                    .background(DesignTokens.surface, in: RoundedRectangle(cornerRadius: DesignTokens.radiusCard))
                    .overlay(RoundedRectangle(cornerRadius: DesignTokens.radiusCard).strokeBorder(DesignTokens.line, lineWidth: 0.5))
            }
        }
    }

    private var appRows: some View {
        VStack(spacing: 0) {
            ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
                if index > 0 { Divider().overlay(DesignTokens.line) }
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
        Text(L10n.string("apps.empty"))
            .font(.system(size: DesignTokens.typeBody))
            .foregroundStyle(DesignTokens.muted)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, DesignTokens.spacing3)
            .padding(.vertical, DesignTokens.spacing5)
            .background(DesignTokens.surface, in: RoundedRectangle(cornerRadius: DesignTokens.radiusCard))
            .overlay(RoundedRectangle(cornerRadius: DesignTokens.radiusCard).strokeBorder(DesignTokens.line, lineWidth: 0.5))
    }

    // MARK: - Primary action

    @ViewBuilder
    private var actionSection: some View {
        switch status {
        case .protected, .frozen, .disabled:
            EmptyView()
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
        case .unknown:
            Button(L10n.string("action.retry")) { appState.send(.retryCheck) }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity, alignment: .trailing)
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

#Preview("No protected apps") {
    DashboardView()
        .environmentObject(AppState.preview(.protected, apps: []))
        .padding()
        .frame(width: DesignTokens.popoverWidth)
}

#Preview("Protection off — no Resume all") {
    DashboardView()
        .environmentObject(AppState.preview(.disabled, protectionEnabled: false))
        .padding()
        .frame(width: 480)
}

#Preview("Unknown — Retry only") {
    DashboardView()
        .environmentObject(AppState.preview(.unknown, ipv4: nil, vpn: nil, trusted: false))
        .padding()
        .frame(width: 480)
}

#Preview("Unknown — frozen apps") {
    DashboardView()
        .environmentObject(AppState.preview(
            .unknown,
            ipv4: nil,
            vpn: nil,
            trusted: false,
            frozen: ["com.anthropic.claudefordesktop"]
        ))
        .padding()
        .frame(width: 480)
}


