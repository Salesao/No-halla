//
//  PopoverView.swift
//  NoHalla
//
//  S1 placeholder popover: live status plus its lore line through L10n. S3
//  (s3-popover) replaces this with the full 360 pt design covering every state.
//

import SwiftUI

struct PopoverView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacing2) {
            Text(L10n.string("brand.name"))
                .font(.system(size: DesignTokens.typeTitle, weight: .semibold))
            Text(statusText)
                .font(.system(size: DesignTokens.typeBody))
            Text(loreText)
                .font(.system(size: DesignTokens.typeSmall))
                .foregroundStyle(.secondary)
        }
        .padding(DesignTokens.spacing4)
        .frame(width: DesignTokens.popoverWidth, alignment: .leading)
    }

    private var statusText: String {
        let status = appState.uiStatus
        if status == .grace, let remaining = appState.snapshot.graceRemaining {
            return L10n.string("status.grace", remaining)
        }
        return L10n.string(Self.statusKey(for: status))
    }

    private var loreText: String {
        L10n.string(Self.statusKey(for: appState.uiStatus) + ".lore")
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
}

#Preview {
    PopoverView()
        .environmentObject(AppState())
}