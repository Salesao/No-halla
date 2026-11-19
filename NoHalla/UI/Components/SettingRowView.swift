//
//  SettingRowView.swift
//  NoHalla
//
//  Shared settings row (design/COMPONENTS.md): a label lane with helper text
//  beneath the label and a trailing control aligned on the trailing edge.
//

import SwiftUI

struct SettingRowView<Content: View>: View {
    let label: String
    var helper: String? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .center, spacing: DesignTokens.spacing3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: DesignTokens.typeBody))
                    .foregroundStyle(DesignTokens.text)
                if let helper = helper {
                    Text(helper)
                        .font(.system(size: DesignTokens.typeSmall))
                        .foregroundStyle(DesignTokens.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: DesignTokens.spacing3)
            content()
        }
        .frame(minHeight: DesignTokens.targetMin)
        .padding(.vertical, DesignTokens.spacing1)
    }
}

#Preview("Setting rows") {
    VStack(spacing: 8) {
        SettingRowView(label: L10n.string("ui.notifications")) {
            Toggle("", isOn: .constant(true)).labelsHidden()
        }
        SettingRowView(label: L10n.string("ui.grace-period"), helper: L10n.string("ui.apps-freeze-after-this-delay-when-the-ip-changes")) {
            Slider(value: .constant(5), in: 0...120).frame(width: 160)
        }
    }
    .padding()
    .frame(width: 680)
}