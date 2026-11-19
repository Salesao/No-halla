# UI components

| Component | Variants and states | Implementation |
|---|---|---|
| Button | Primary, secondary, plain, destructive, disabled. Fit or full width | Native macOS button styles. Use blue for Resume all. Use destructive role for Reset only. Minimum target 28 pt. |
| GateRule | 1 pt bronze line with 24 strokes | Decorative SVG divider under the popover header and in About. Hidden from assistive technology. |
| GateScene | Hero, About panel, empty-state vignette | Share the amber gateway artwork from `exports/gate-scene.png`. Keep its square composition visible, treat it as decoration, and keep actions outside the image. |
| Protection badge | Success, checking, grace/bypass, frozen, unknown/setup, off | State glyph plus semantic label inside a 1 pt decorative bronze rim. Wrap at long translations and reserve the lore line separately. |
| Network field | Default, monospace, trusted | Trailing values. Label pairs are read together. Use a separate refresh button with a descriptive label. |
| App row | Active, frozen, not running. Protection on and off | 44 pt row and 20 pt icon. Switch label includes the app name. Toggle changes protection without removing the row. A frozen row uses a 1 pt waiting rim alongside its Frozen label. |
| Search field | Empty, typing, no matches | Native search style. Filter the mock list by name and bundle ID. |
| Picker row | Checked, unchecked, added, protected-system app, warning | Native checkbox. Expose the warning and disabled reason through Accessibility. |
| Settings toolbar | Selected, hovered, focused | Four icon-and-text tabs. Keep the selected icon and text blue. Add a 1 pt bronze underline. |
| Setting row | Switch, slider, select, text/action, validation | Use a shared label lane and controls aligned on the trailing edge. Add helper text under its label. |
| Sheet / alert | App pick, edit, confirm quit, confirm reset | Use system sheets and alerts. Keep Cancel and default action in the platform's normal order. |
| Countdown | 0–60 seconds in the design | Linear bar plus text. At Reduce Motion, snap the bar on each tick. |

Use visible keyboard focus with a 2 pt outline in HTML and system focus effects in SwiftUI. Hover conveys the hit area. Preserve accessible names in disabled states. Short labels can use the 6 pt control corner. Use 10 pt for groups and natural material containers. Use standard macOS window rounding.
