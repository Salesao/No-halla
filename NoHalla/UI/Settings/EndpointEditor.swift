//
//  EndpointEditor.swift
//  NoHalla
//
//  Sheet to add or edit an IP-check endpoint (design §7.4, FR-8/27, NFR-8).
//  Inline HTTPS validation; an invalid value is never saved. Known endpoints
//  are offered in a menu; the text field still accepts a custom URL.
//

import SwiftUI

struct EndpointEditor: View {
    let original: String
    let title: String
    let validate: ((String) -> String?)?
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var value: String = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacing3) {
            Text(title)
                .font(.system(size: DesignTokens.typeTitle, weight: .semibold))
                .foregroundStyle(DesignTokens.text)
            HStack {
                Menu(L10n.string("ui.known-endpoints")) {
                    ForEach(IPCheckEndpoint.presets, id: \.self) { preset in
                        Button(preset) { value = preset }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Spacer()
            }
            TextField(L10n.string("ui.use-an-https-endpoint-that-returns-an-ip-address"), text: $value)
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
        .frame(width: 440)
        .background(DesignTokens.bg)
        .tint(DesignTokens.action)
        .onAppear { value = original }
    }

    private func save() {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard IPCheckEndpoint.isValid(trimmed) else {
            error = L10n.string("ui.enter-a-valid-https-url")
            return
        }
        if let message = validate?(trimmed) {
            error = message
            return
        }
        onSave(trimmed)
    }
}

#Preview {
    EndpointEditor(
        original: "https://ipinfo.io/ip",
        title: L10n.string("ui.edit-ip-check-endpoint"),
        validate: nil,
        onSave: { _ in },
        onCancel: {}
    )
}