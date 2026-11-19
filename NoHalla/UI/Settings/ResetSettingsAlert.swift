//
//  ResetSettingsAlert.swift
//  NoHalla
//
//  Destructive reset confirmation (design §7.4, spec D20 pattern). Native alert
//  with Cancel and the destructive Reset action in platform order.
//

import AppKit

enum ResetSettingsAlert {
    @MainActor
    static func confirm() -> Bool {
        let alert = NSAlert()
        alert.messageText = L10n.string("ui.reset-all-settings")
        alert.informativeText = L10n.string("ui.frozen-apps-will-resume-and-your-preferences-will-return-to-their-defaults")
        alert.alertStyle = .warning
        alert.icon = AppIdentityIcon.image
        let reset = alert.addButton(withTitle: L10n.string("ui.reset-settings"))
        reset.hasDestructiveAction = true
        alert.addButton(withTitle: L10n.string("action.cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }
}
