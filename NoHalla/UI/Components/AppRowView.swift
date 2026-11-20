//
//  AppRowView.swift
//  NoHalla
//
//  Protected-app row: 44 pt row, 20 pt icon, a toggle
//  whose label includes the app name, run-state text, and a 1 pt waiting rim
//  plus Frozen label when frozen. Toggling changes protection without removing
//  the row.
//

import SwiftUI

/// Run state of a protected app, derived from the engine snapshot.
enum AppRunState {
    case active
    case frozen
    case notRunning
}

struct AppRowView: View {
    let app: ProtectedApp
    let runState: AppRunState
    let isFrozen: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(spacing: DesignTokens.spacing2) {
            ProtectedAppIconView(bundleID: app.bundleID)
            Text(app.name)
                .font(.system(size: DesignTokens.typeBody, weight: .medium))
                .foregroundStyle(DesignTokens.text)
                .lineLimit(1)
            Spacer(minLength: DesignTokens.spacing2)
            Text(stateText)
                .font(.system(size: DesignTokens.typeSmall))
                .foregroundStyle(runState == .frozen ? DesignTokens.red : DesignTokens.muted)
                .lineLimit(1)
            Toggle(isOn: Binding(get: { app.enabled }, set: { onToggle($0) })) {
                Text(L10n.string("ui.protect-app", app.name))
                    .font(.system(size: DesignTokens.typeSmall))
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
            .accessibilityLabel(L10n.string("ui.protect-app", app.name))
        }
        .padding(.horizontal, DesignTokens.spacing2)
        .frame(minHeight: DesignTokens.appRow)
        .background(isFrozen ? DesignTokens.bronze.opacity(0.08) : Color.clear)
        .overlay {
            if isFrozen {
                RoundedRectangle(cornerRadius: DesignTokens.radiusControl)
                    .strokeBorder(DesignTokens.bronze, lineWidth: DesignTokens.ornamentStroke)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(app.name), \(stateText), \(L10n.string("ui.protect-app", app.name))")
        .accessibilityValue(app.enabled ? L10n.string("ui.yes") : L10n.string("ui.no"))
    }

    private var stateText: String {
        switch runState {
        case .active: return L10n.string("apps.active")
        case .frozen: return L10n.string("apps.frozen")
        case .notRunning: return L10n.string("apps.notRunning")
        }
    }

}

#Preview("App rows") {
    VStack(spacing: 8) {
        AppRowView(app: ProtectedApp(bundleID: "com.anthropic.claudefordesktop", name: "Claude", enabled: true), runState: .active, isFrozen: false) { _ in }
        AppRowView(app: ProtectedApp(bundleID: "com.todesktop.230313mzl4w4u92", name: "Cursor", enabled: true), runState: .frozen, isFrozen: true) { _ in }
        AppRowView(app: ProtectedApp(bundleID: "com.openai.chat", name: "ChatGPT", enabled: false), runState: .notRunning, isFrozen: false) { _ in }
    }
    .padding()
    .frame(width: 360)
}
