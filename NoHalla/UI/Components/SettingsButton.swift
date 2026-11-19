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

    var body: some View {
        if #available(macOS 14.0, *) {
            SettingsLink {
                Text(label)
            }
            .buttonStyle(.borderless)
        } else {
            Button(label) {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            .buttonStyle(.borderless)
        }
    }
}