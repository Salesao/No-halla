//
//  MenuBarIconMapping.swift
//  NoHalla
//
//  Maps a derived UI status to its menu bar template glyph (design/ICONS.md).
//  The mapping lives here (s1-wiring) because it depends on UIStatus.
//

import Foundation

extension DesignTokens {
    /// Menu bar imageset name for a UI status (ICONS.md).
    static func menuBarImageName(for status: UIStatus) -> String {
        switch status {
        case .protected:
            return "MenuBarProtected"
        case .checking, .grace:
            return "MenuBarGrace"
        case .frozen:
            return "MenuBarFrozen"
        case .unknown, .setup:
            return "MenuBarUnknown"
        case .paused, .disabled, .bypassing:
            return "MenuBarOff"
        }
    }

    /// VoiceOver label key for a menu bar status (design/ACCESSIBILITY.md).
    static func menuBarAccessibilityKey(for status: UIStatus) -> String {
        switch status {
        case .protected:
            return "ui.no-halla-protected"
        case .checking:
            return "ui.no-halla-checking-ip"
        case .grace:
            return "ui.no-halla-waiting-for-vpn"
        case .frozen:
            return "ui.no-halla-apps-frozen"
        case .unknown:
            return "ui.no-halla-can-t-verify-ip"
        case .setup:
            return "ui.no-halla-add-a-trusted-ip"
        case .paused, .disabled:
            return "ui.no-halla-protection-off"
        case .bypassing:
            return "ui.no-halla-bypassing"
        }
    }
}