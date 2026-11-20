//
//  NetworkCardView.swift
//  NoHalla
//
//  Network field group: label/value pairs read together,
//  monospace IP, a separate refresh button with a descriptive label, and an
//  "Add current IP" action only when the address is known and untrusted.
//  Unknown/offline values show an em dash with an explanatory note (R54);
//  controls meet the 28 pt target (R58).
//

import SwiftUI

struct NetworkCardView: View {
    let ipv4: String?
    let vpnInterface: String?
    /// nil = unknown/unverifiable (render "—"); true/false = known trust.
    let trusted: Bool?
    /// VPN-tunnel protection mode: show the tunnel status instead of the IP.
    var vpnMode: Bool = false
    var note: String? = nil
    var onAddCurrentIP: (() -> Void)? = nil
    var onRefresh: (() -> Void)? = nil
    /// A user-requested check is pending (possibly behind the verifier throttle).
    var isRefreshing: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacing2) {
            if vpnMode {
                vpnFields
            } else {
                ipFields
            }

            if let note = note {
                Text(note)
                    .font(.system(size: DesignTokens.typeSmall))
                    .foregroundStyle(DesignTokens.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !vpnMode, trusted == false, ipv4 != nil, let onAddCurrentIP = onAddCurrentIP {
                Button(L10n.string("network.addCurrentIP"), action: onAddCurrentIP)
                    .buttonStyle(.bordered)
                    .frame(minHeight: DesignTokens.targetMin)
            }

        }
        .padding(DesignTokens.spacing3)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.radiusCard)
                .fill(DesignTokens.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.radiusCard)
                .strokeBorder(DesignTokens.line, lineWidth: 0.5)
        )
    }

    private var trustedText: String {
        guard let trusted = trusted else { return "—" }
        return trusted ? L10n.string("ui.yes") : L10n.string("ui.no")
    }

    /// IP-whitelist mode fields.
    private var ipFields: some View {
        Group {
            HStack(spacing: 0) {
                field(label: L10n.string("network.currentIP"), value: ipv4 ?? "—", mono: true)
                refreshControl
            }
            field(label: L10n.string("network.vpnInterface"), value: vpnInterface ?? "—", mono: false)
            field(label: L10n.string("network.trusted"), value: trustedText, mono: false)
        }
    }

    /// VPN-tunnel mode fields: tunnel status (no IP, no external check).
    private var vpnFields: some View {
        let connected = vpnInterface != nil
        return Group {
            field(
                label: L10n.string("network.vpn"),
                value: connected ? L10n.string("network.vpnConnected") : L10n.string("network.vpnDisconnected"),
                mono: false
            )
            HStack(spacing: 0) {
                field(label: L10n.string("network.vpnInterface"), value: vpnInterface ?? "—", mono: true)
                refreshControl
            }
        }
    }

    @ViewBuilder private var refreshControl: some View {
        if isRefreshing {
            ProgressView().controlSize(.small)
                .frame(width: DesignTokens.targetMin, height: DesignTokens.targetMin)
                .accessibilityLabel(L10n.string("ui.refresh-current-ip"))
                .accessibilityValue(L10n.string("status.checking"))
        } else if let onRefresh = onRefresh {
            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
                    .frame(width: DesignTokens.targetMin, height: DesignTokens.targetMin)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .foregroundStyle(DesignTokens.muted)
            .accessibilityLabel(L10n.string("ui.refresh-current-ip"))
            .help(L10n.string("ui.refresh-current-ip"))
        }
    }

    private func field(label: String, value: String, mono: Bool) -> some View {
        HStack {
            Text(label)
                .font(.system(size: DesignTokens.typeSmall))
                .foregroundStyle(DesignTokens.muted)
            Spacer()
            Text(value)
                .font(mono ? .system(size: DesignTokens.typeBody, design: .monospaced) : .system(size: DesignTokens.typeBody))
                .foregroundStyle(DesignTokens.text)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

#Preview("Network card") {
    VStack(spacing: 12) {
        NetworkCardView(ipv4: "203.0.113.5", vpnInterface: "utun3", trusted: true, onRefresh: {})
        NetworkCardView(ipv4: "198.51.100.7", vpnInterface: nil, trusted: false, onAddCurrentIP: {}, onRefresh: {})
        NetworkCardView(ipv4: nil, vpnInterface: nil, trusted: nil, note: L10n.string("empty.offline"), onRefresh: {})
    }
    .padding()
    .frame(width: 360)
}