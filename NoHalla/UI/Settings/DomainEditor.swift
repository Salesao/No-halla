//
//  DomainEditor.swift
//  NoHalla
//
//  Sheet to add/edit a blocked hostname (D32). Validation is shared with the
//  root helper via DomainBlocklist.normalize; an invalid value is never saved.
//

import SwiftUI

struct DomainEditor: View {
    let original: String?
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var value: String = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacing3) {
            Text(L10n.string("ui.domain-guard-edit"))
                .font(.system(size: DesignTokens.typeTitle, weight: .semibold))
                .foregroundStyle(DesignTokens.text)
            TextField(L10n.string("ui.domain-guard-placeholder"), text: $value)
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
        guard let domain = DomainBlocklist.normalize(value) else {
            error = L10n.string("ui.domain-guard-invalid")
            return
        }
        onSave(domain)
    }
}

#Preview {
    DomainEditor(original: "chatgpt.com", onSave: { _ in }, onCancel: {})
}
