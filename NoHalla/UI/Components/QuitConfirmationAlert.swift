//
//  QuitConfirmationAlert.swift
//  NoHalla
//
//  Native quit confirmation (spec D20, FR-4, design §7.7). Shown only when
//  frozen apps exist; confirming resumes them and stops protection.
//

import AppKit

/// Presents the quit confirmation and reports the user's choice.
enum QuitConfirmationAlert {
    /// Returns `true` when the user confirms quitting (frozen apps resume).
    /// The alert runs modally on the main actor; the first button is the
    /// default "Quit and Resume" action, the second is Cancel (native order).
    @MainActor
    static func confirm(frozenCount: Int) async -> Bool {
        let alert = NSAlert()
        alert.messageText = L10n.string("quit.title")
        alert.informativeText = L10n.string("quit.body", frozenCount)
        alert.addButton(withTitle: L10n.string("quit.confirm"))
        alert.addButton(withTitle: L10n.string("action.cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }
}
