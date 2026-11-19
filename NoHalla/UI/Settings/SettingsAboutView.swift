//
//  SettingsAboutView.swift
//  NoHalla
//
//  About tab (design §7.4, FR-33, spec D21/D26): app icon, name, tagline,
//  version, MIT line, Copy version info, gate ornament. The Repository row is
//  hidden until a real URL exists (D26).
//

import AppKit
import SwiftUI

struct SettingsAboutView: View {
    var body: some View {
        VStack(spacing: DesignTokens.spacing3) {
            GateSceneView(variant: .about)
            Image("AppIcon")
                .resizable()
                .frame(width: 64, height: 64)
            Text(L10n.string("brand.name"))
                .font(.system(size: DesignTokens.typeTitle, weight: .semibold))
                .foregroundStyle(DesignTokens.text)
            Text(L10n.string("brand.tagline"))
                .font(.system(size: DesignTokens.typeBody))
                .foregroundStyle(DesignTokens.muted)
            Text(L10n.string("ui.version-0-1-0", "0.1.0"))
                .font(.system(size: DesignTokens.typeSmall))
                .foregroundStyle(DesignTokens.muted)
            Text(L10n.string("ui.free-and-open-source-mit-license"))
                .font(.system(size: DesignTokens.typeSmall))
                .foregroundStyle(DesignTokens.muted)
            Text(L10n.string("ui.sigstop-pauses-app-execution-macos-can-still-send-buffered-data-or-finish-existing-connections"))
                .font(.system(size: DesignTokens.typeSmall))
                .foregroundStyle(DesignTokens.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(L10n.string("ui.copy-version-info")) { copyVersionInfo() }
                .buttonStyle(.bordered)
            GateRuleView()
                .frame(width: 200)
            Spacer()
        }
        .padding(DesignTokens.spacing5)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func copyVersionInfo() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        let info = "No-halla \(version)\nmacOS \(ProcessInfo.processInfo.operatingSystemVersionString)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(info, forType: .string)
    }
}

#Preview {
    SettingsAboutView()
        .frame(width: 680, height: 520)
}