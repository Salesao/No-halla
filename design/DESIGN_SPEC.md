# No-halla design specification

## Direction contract

THESIS — Show the current protection state, its evidence and the action together in one glance.

OWN-WORLD — A dark-first fjord shell uses compact macOS material and native blue controls. A bronze line with 24 strokes separates the title and status from network evidence. Bronze also marks the pill rim, selected tab and frozen row outline. Light uses the same structure.

STORY — Read what happened, confirm the current IP and see which apps are affected. Take the state-specific action without leaving the popover.

FIRST VIEWPORT — At 360 pt, lead with the app name and status pill, then a three-line network ledger, a 44 pt row per app and a full-width contextual control above Settings and Quit. Grace adds a measured linear countdown. Settings group controls under four icon toolbar tabs.

FORM — Operate. seed: none (pinned). “Dark-first brand shell.” “Native macOS first.”

FINISH — unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance

## Navigation

The 18 pt menu bar glyph opens the 360 pt popover. From its footer, Settings opens the 680 × 520 pt settings window and Quit exits immediately or opens confirmation. Add app opens a 480 × 520 pt picker. First launch opens a 560 × 420 pt three-step setup window. Notification permission uses the system prompt after setup.

## Popover states

| State | Evidence the popover shows | Main action |
|---|---|---|
| Checking | Current measurements are pending | Disabled Checking… |
| Protected | Trusted IP and active apps | Pause, with three durations |
| Grace | Untrusted IP and one countdown below the app list | Freeze now, Cancel |
| Frozen | Untrusted IP and the affected apps | Automatic resume when trust returns |
| Unknown | A check failed. Apps may remain frozen per configuration | Retry |
| Paused | Time at which checks restart | Turn on now |
| Disabled | Protection is off | Turn on |
| Setup | A trusted IP is missing | Add current IP |
| Bypassing | Time at which protection resumes | Resume protection |
| Empty | Trusted network with zero selected apps | Choose apps |
| Offline | Network is unavailable | Retry |

Show a monospace IP and interface name in a single network group. Use a dash for an unavailable value. Status comes before the lore sentence in reading order. Use text and a glyph for a status. Each app row is 44 pt and has its own persistent protection switch. Up to four rows fit. Beyond four, scroll the list and keep the action and footer visible. A non-running app remains configured.

## Windows and sheets

- **Onboarding** — introduction with gate illustration, app search and checkbox selection, current or manually entered trusted IP, opt-in launch toggle defaulted on. Finish enables after valid IP is saved. Skip setup returns to the popover and leaves any missing prerequisites visible.
- **General** — launch at login, notifications, language. An error appears under the launch control. A notification permission banner offers Open System Settings.
- **Protection** — grace delay, check cadence, unknown-IP policy, IPv6 detection, VPN requirement, trusted addresses, protected apps. Validate IP/CIDR inline and retain focus on invalid input.
- **Advanced** — edit the IPv4 and IPv6 endpoint lists, restore endpoints, configure manual bypass and log level, export diagnostics through the system save panel, and confirm before resetting.
- **About** — icon, version, tagline, license, repository, version copy and process suspension limitation.
- **App picker** — filter Running and Applications by app name or bundle ID. Duplicate and prohibited system apps are unavailable. Terminal-like apps show a warning. Add enables when at least one eligible app is selected. Use the actual NSWorkspace application icons in SwiftUI.
- **Quit confirmation** — report the frozen app count and place Quit and Resume at the end of the dialog. Cancel returns focus to the trigger.
- **Notifications** — three system presentations with matching actions. Frozen includes the new IP. Resumed confirms trusted recovery. Unknown explains the failed check. Throttle separately per type.

## Interaction rules

| Event or action | Result |
|---|---|
| Network change or wake | Check immediately with debouncing specified by the engine. Preserve state through transient wake updates. |
| Untrusted IP | Start grace. Update the countdown once a second. Freeze immediately on Freeze now. |
| Trusted IP returns or is added | Cancel grace or resume the frozen apps. Refresh the status immediately. |
| Resume all from the freeze notification | Resume apps and show Bypassing until the configured bypass expires. Then check again. |
| Pause | Resume apps and suspend protection for 15 minutes, one hour or until relaunch. Recheck when protection resumes. |
| App starts while frozen | Add its frozen status without a second notification. |
| App exits | Mark Not running and remove the process from the frozen set. |
| IP check fails | Use the configured unknown-IP policy. If freezing is enabled, run grace first and show the resulting app state. |
| Quit while apps are frozen | Confirm, then resume apps before exit. |
| Interface changes with the same trusted IP | Keep apps running as long as the configured VPN requirement is met. |

Use [tokens.json](tokens.json) for the measurements and appearance values, [copy.json](copy.json) for localization, and [HANDOFF.md](HANDOFF.md) to match screen files and Doop frames to SwiftUI views. See [ACCESSIBILITY.md](ACCESSIBILITY.md) for keyboard, appearance and narration behavior.

The HTML demonstrations use reserved example IP addresses and illustrative clock values. Popover heights follow content. System materials and traffic light controls are depicted with opaque CSS for predictable exports. In SwiftUI use the system-provided material, window chrome and controls.

## Verification

Doop rendered all 79 design frames. The 15 offline HTML documents rendered 42 views at the specified point sizes and 2× scale in Chromium. The light and dark passes checked clipping and asset loading without network requests. The flow check covered skipped setup, saving trust, separate IPv6 endpoint editing and keyboard dismissal of Pause. Browser accessibility output reports a distinct name for each app switch. The web detector flags 11 pt captions and contained list edges. Those match the brief's caption size and native grouped rows with insets on each row. The three slider targets measure 28 pt. Four app rows fit, and the fifth scrolls. The paired Doop prototypes retain all 280 interactions. Run the system accessibility checklist on the SwiftUI build.


## Dark-first appearance

The dark popover uses the specified fjord ground #0E1F26, group surface #1C333D and chrome #14252D. Its bronze gate line, status rim and waiting rim have a 1 pt stroke. The selected settings tab has a bronze underline with blue text. The GateScene component scales from the onboarding and About heroes to a small decorative empty-state vignette. Light adapts the same structure with its own palette.

The Doop canvas pairs light and dark pages for Popover, Onboarding, Settings, Sheets & alerts, Notifications, and Identity & accessibility. Dark prototype links stay in the dark appearance. The offline documents open dark by default. The theme query supports light, dark, contrast and system appearance and keeps the choice between views. See [HANDOFF.md](HANDOFF.md) for paired screen links.
