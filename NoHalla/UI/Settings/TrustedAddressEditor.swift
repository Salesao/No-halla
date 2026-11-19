//
//  TrustedAddressEditor.swift
//  NoHalla
//
//  Sheet to add/edit a trusted IP or CIDR (design §7.4, FR-10/27). Inline CIDR
//  validation; an invalid value is never saved.
//

import SwiftUI

struct TrustedAddressEditor: View {
    let original: String?
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var value: String = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacing3) {
            Text(L10n.string(original == nil ? "status.setup" : "ui.edit-trusted-ip"))
                .font(.system(size: DesignTokens.typeTitle, weight: .semibold))
                .foregroundStyle(DesignTokens.text)
            TextField(L10n.string("ui.enter-an-ipv4-or-cidr-address"), text: $value)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)
            if let error = error {
                Text(error)
                    .font(.system(size: DesignTokens.typeSmall))
                    .foregroundStyle(DesignTokens.red)
            }
            HStack {
                Spacer()
                Button(L10n.string("action.cancel"), action: onCancel)
                    .buttonStyle(.bordered)
                    .tint(DesignTokens.text)
                Button(L10n.string("ui.save")) { save() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(DesignTokens.spacing4)
        .frame(width: 400)
        .background(DesignTokens.bg)
        .tint(DesignTokens.action)
        .onAppear { value = original ?? "" }
    }

    private func save() {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard CIDRRange(trimmed) != nil else {
            error = L10n.string("ui.enter-a-valid-ipv4-or-cidr-address")
            return
        }
        onSave(trimmed)
    }
}

#Preview {
    TrustedAddressEditor(original: "203.0.113.5", onSave: { _ in }, onCancel: {})
}
