//
//  StatusPillView.swift
//  NoHalla
//
//  Protection badge (design/COMPONENTS.md): state glyph plus semantic label
//  inside a 1 pt decorative bronze rim. The status is read before the lore;
//  bronze carries no status meaning (D3). Wraps long translations.
//

import SwiftUI

struct StatusPillView: View {
    let status: UIStatus
    var graceRemaining: Int? = nil
    var untilText: String? = nil

    var body: some View {
        HStack(spacing: DesignTokens.spacing1) {
            Image(systemName: Self.symbol(for: status))
                .font(.system(size: DesignTokens.typeSmall, weight: .semibold))
                .foregroundStyle(Self.tint(for: status))
            Text(Self.label(for: status, graceRemaining: graceRemaining, untilText: untilText))
                .font(.system(size: DesignTokens.typeSmall, weight: .semibold))
                .foregroundStyle(DesignTokens.text)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, DesignTokens.spacing2)
        .frame(minHeight: DesignTokens.statusHeight)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.radiusPill)
                .fill(Self.tint(for: status).opacity(DesignTokens.badgeTintOpacity))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.radiusPill)
                .strokeBorder(DesignTokens.bronze, lineWidth: DesignTokens.ornamentStroke)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Self.label(for: status, graceRemaining: graceRemaining, untilText: untilText))
    }

    static func symbol(for status: UIStatus) -> String {
        switch status {
        case .protected: return "shield.checkered"
        case .checking, .grace: return "clock"
        case .frozen: return "pause.circle"
        case .unknown, .setup: return "exclamationmark.shield"
        case .paused, .disabled, .bypassing: return "shield.slash"
        }
    }

    static func tint(for status: UIStatus) -> Color {
        switch status {
        case .protected: return DesignTokens.green
        case .checking: return DesignTokens.muted
        case .grace, .bypassing: return DesignTokens.orange
        case .frozen: return DesignTokens.red
        case .unknown, .setup: return DesignTokens.orange
        case .paused, .disabled: return DesignTokens.muted
        }
    }

    static func label(for status: UIStatus, graceRemaining: Int?, untilText: String?) -> String {
        switch status {
        case .setup: return L10n.string("status.setup")
        case .checking: return L10n.string("status.checking")
        case .protected: return L10n.string("status.protected")
        case .grace: return L10n.string("status.grace", graceRemaining ?? 0)
        case .frozen: return L10n.string("status.frozen")
        case .unknown: return L10n.string("status.unknown")
        case .paused:
            // R57: "until relaunch" has no clock time; use a dedicated label.
            if let untilText = untilText { return L10n.string("status.paused", untilText) }
            return L10n.string("status.paused-until-relaunch")
        case .disabled: return L10n.string("status.disabled")
        case .bypassing: return L10n.string("status.bypass", untilText ?? "")
        }
    }
}

#Preview("Status pills") {
    VStack(alignment: .leading, spacing: 8) {
        StatusPillView(status: .protected)
        StatusPillView(status: .checking)
        StatusPillView(status: .grace, graceRemaining: 5)
        StatusPillView(status: .frozen)
        StatusPillView(status: .unknown)
        StatusPillView(status: .setup)
        StatusPillView(status: .paused, untilText: "14:32")
        StatusPillView(status: .disabled)
        StatusPillView(status: .bypassing, untilText: "14:32")
    }
    .padding()
    .frame(width: 360)
}