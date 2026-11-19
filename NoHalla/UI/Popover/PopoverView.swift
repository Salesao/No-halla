//
//  PopoverView.swift
//  NoHalla
//
//  Menu bar popover: the shared DashboardView at the compact 360 pt width plus
//  a Settings/Quit footer. The main application window (MainWindowView) reuses
//  the same DashboardView for the user-requested windowed experience.
//

import AppKit
import SwiftUI

struct PopoverView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DashboardView()
                .padding(DesignTokens.spacing4)
            footer
                .padding(.horizontal, DesignTokens.spacing4)
                .padding(.vertical, DesignTokens.spacing2)
                .background(DesignTokens.chrome)
        }
        .frame(width: DesignTokens.popoverWidth)
        .background(DesignTokens.bg)
        .tint(DesignTokens.action)
    }

    private var footer: some View {
        HStack {
            SettingsButton()
            Spacer()
            Button(L10n.string("action.quit")) { NSApp.terminate(nil) }
                .buttonStyle(.borderless)
        }
        .font(.system(size: DesignTokens.typeSmall))
        .foregroundStyle(DesignTokens.muted)
    }
}

#Preview("Protected") {
    PopoverView().environmentObject(AppState.preview(.protected))
}

#Preview("Grace") {
    PopoverView().environmentObject(AppState.preview(.grace, ipv4: "198.51.100.7", trusted: false, graceRemaining: 5))
}

#Preview("Frozen") {
    PopoverView().environmentObject(AppState.preview(.frozen, ipv4: "198.51.100.7", trusted: false, frozen: ["com.anthropic.claudefordesktop", "com.todesktop.230313mzl4w4u92"]))
}

#Preview("Unknown") {
    PopoverView().environmentObject(AppState.preview(.unknown, ipv4: nil, vpn: nil, trusted: false))
}

#Preview("Setup") {
    PopoverView().environmentObject(AppState.preview(.setup, trusted: false, trustedAddresses: []))
}

#Preview("Bypassing") {
    PopoverView().environmentObject(AppState.preview(.bypassing, ipv4: "198.51.100.7", trusted: false, bypassUntil: Date().addingTimeInterval(300)))
}