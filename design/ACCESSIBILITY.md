# Accessibility

- Read protection status before the lore caption. Use a polite announcement on meaningful changes. Avoid announcements for every countdown tick.
- Present each app name, whether it is running, its frozen state and whether protection is on. Tell users why a system app is unavailable in the picker.
- Use native focus order from the heading through network controls, app rows, main action and footer. Tab and Shift-Tab move focus. Space toggles a switch or checkbox. Escape dismisses the popover, sheet or open Pause menu. Restore focus to the trigger after a sheet closes.
- Keep a 28 × 28 pt minimum pointer target and text contrast of at least 4.5:1. Draw distinctions in text and shape. Control boundaries against the control surface measure 3.23:1 in light and 3.26:1 in dark. The default action label has 6.10:1 in light and 5.57:1 in dark. Secondary text on the default window surface has 6.02:1 and 8.32:1.
- Keep slider targets at least 28 pt high. Use lighter badge tint in light mode so the bronze rim has at least 3:1 contrast against its fill.
- Bronze ornament is hidden from accessibility APIs. In dark mode, bronze on fjord ground measures 7.38:1, and on group surfaces it measures 5.77:1. The state is read from the label and glyph.
- Use native label/separator colors and focus effects. In Increase Contrast, use the contrast outline token on mockups and preserve borders in SwiftUI. With Reduce Transparency, choose an opaque material fallback. With Reduce Motion, show countdown ticks and skip optional transitions.
- Let line breaks accommodate longer translations. Use the Russian grace frame for a 360 pt width example. Keep buttons and section labels in the layout at that width.
- Review all native controls and VoiceOver on a real macOS build. HTML captures verify the stated layouts and types, and provide examples of accessible labels and keyboard behavior.

| Menu bar state | VoiceOver label |
|---|---|
| Protected | No-halla, protected |
| Checking | No-halla, checking IP |
| Grace | No-halla, waiting for VPN |
| Frozen | No-halla, apps frozen |
| Unknown | No-halla, can’t verify IP |
| Setup | No-halla, add a trusted IP |
| Paused / disabled | No-halla, protection off |
| Bypass | No-halla, bypassing |
