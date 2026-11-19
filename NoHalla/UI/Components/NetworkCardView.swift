//
//  NetworkCardView.swift
//  NoHalla
//
//  Network field group (design/COMPONENTS.md): label/value pairs read together,
//  monospace IP, a separate refresh button with a descriptive label, and an
//  "Add current IP" action when the address is not trusted. Unknown values show
//  an em dash.
//

import SwiftUI

struct NetworkCardView: View {
    let ipv4: String?
    let ipv6: String?
    let vpnInterface: String?
    let trusted: Bool
    var onAddCurrentIP: (() -> Void)? = nil
    var onRefresh: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacing2) {
            field(label: L10n.string("network.currentIP"), value: ipv4 ?? "—", mono: true)
            if let ipv6 = ipv6 {
                field(label: "IPv6", value: ipv6, mono: true)
            }
            field(label: L10n.string("network.vpnInterface"), value: vpnInterface ?? "—", mono: false)
            field(label: L10n.string("network.trusted"), value: trusted ? L10n.string("ui.yes") : L10n.string("ui.no"), mono: false)

            HStack(spacing: DesignTokens.spacing2) {
                if !trusted, let onAddCurrentIP = onAddCurrentIP {
                    Button(L10n.string("network.addCurrentIP"), action: onAddCurrentIP)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                Spacer()
                if let onRefresh = onRefresh {
                    Button(action: onRefresh) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(L10n.string("ui.refresh-current-ip"))
                    .help(L10n.string("ui.refresh-current-ip"))
                }
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
        NetworkCardView(ipv4: "203.0.113.5", ipv6: "2001:db8::1", vpnInterface: "utun3", trusted: true, onRefresh: {})
        NetworkCardView(ipv4: nil, ipv6: nil, vpnInterface: nil, trusted: false, onAddCurrentIP: {}, onRefresh: {})
    }
    .padding()
    .frame(width: 360)
}