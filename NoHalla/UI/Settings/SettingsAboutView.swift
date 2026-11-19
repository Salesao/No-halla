//
//  SettingsAboutView.swift
//  NoHalla
//
//  About tab (design §7.4, FR-33, spec D21/D26): app icon, name, tagline,
//  version, MIT line, repository link, Copy version info, gate ornament.
//

import AppKit
import SwiftUI

struct SettingsAboutView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacing4) {
            HStack(alignment: .center, spacing: DesignTokens.spacing5) {
                VStack(alignment: .leading, spacing: DesignTokens.spacing2) {
                    Image(nsImage: AppIdentityIcon.image)
                        .resizable()
                        .frame(width: 86, height: 86)
                        .accessibilityHidden(true)
                    Text(L10n.string("brand.name"))
                        .font(.system(size: DesignTokens.typeHero, weight: .semibold))
                        .foregroundStyle(DesignTokens.text)
                    Text(L10n.string("brand.tagline"))
                        .font(.system(size: DesignTokens.typeBody))
                        .foregroundStyle(DesignTokens.text)
                    Text(L10n.string("ui.version-0-1-0", "0.1.0"))
                        .font(.system(size: DesignTokens.typeSmall))
                        .foregroundStyle(DesignTokens.muted)
                }
                GateSceneView(variant: .about)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            GateRuleView()
            Text(L10n.string("ui.free-and-open-source-mit-license"))
                .font(.system(size: DesignTokens.typeBody))
                .foregroundStyle(DesignTokens.muted)
            Text(L10n.string("ui.sigstop-pauses-app-execution-macos-can-still-send-buffered-data-or-finish-existing-connections"))
                .font(.system(size: DesignTokens.typeSmall))
                .foregroundStyle(DesignTokens.muted)
                .fixedSize(horizontal: false, vertical: true)
            Link(destination: URL(string: "https://github.com/Salesao/No-halla")!) {
                Text(L10n.string("ui.repository"))
                    .font(.system(size: DesignTokens.typeBody))
            }
            .buttonStyle(.link)
            .accessibilityLabel("\(L10n.string("ui.repository")): github.com/Salesao/No-halla")
            Button(L10n.string("ui.copy-version-info")) { copyVersionInfo() }
                .buttonStyle(.bordered)
                .tint(DesignTokens.blue)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 72)
        .padding(.top, DesignTokens.spacing5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

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
