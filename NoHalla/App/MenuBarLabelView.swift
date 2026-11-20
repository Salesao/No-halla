//
//  MenuBarLabelView.swift
//  NoHalla
//
//  Menu bar glyph + VoiceOver label. C3:
//  observes the shared AppState so the glyph and spoken status update whenever
//  the engine snapshot changes — without opening the popover and without a
//  second engine. Image and label derive from the same uiStatus.
//

import SwiftUI

struct MenuBarLabelView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Image(DesignTokens.menuBarImageName(for: appState.uiStatus))
            .renderingMode(.template)
            .accessibilityLabel(L10n.string(DesignTokens.menuBarAccessibilityKey(for: appState.uiStatus)))
    }
}

#Preview {
    MenuBarLabelView(appState: AppState.preview(.protected))
}