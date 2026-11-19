//
//  SettingsButton.swift
//  NoHalla
//
//  Opens the Settings scene reliably. SettingsLink (macOS 14+) is the native,
//  dependable way; on macOS 13 fall back to activating the app and sending the
//  showSettingsWindow: action (an inactive agent's Settings window otherwise
//  opens unseen).
//

import AppKit
import SwiftUI

struct SettingsButton: View {
    var label: String = L10n.string("action.settings")
    var iconOnly = false

    @ViewBuilder private var buttonLabel: some View {
        if iconOnly {
            Image(systemName: "gearshape")
                .font(.system(size: 18, weight: .medium))
                .frame(width: 40, height: 32)
                .contentShape(Rectangle())
        } else {
            Label(label, systemImage: "gearshape")
        }
    }

    var body: some View {
        if #available(macOS 14.0, *) {
            SettingsLink {
                buttonLabel
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(label)
        } else {
            Button {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            } label: {
                buttonLabel
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(label)
        }
    }
}