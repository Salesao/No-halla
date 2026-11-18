---
name: "No-halla"
description: "Compact native macOS controls for app protection."
colors:
  primary: "#1b5ec4"
  primary-dark: "#2865c6"
  primary-contrast: "#004aab"
  blue: "#1557ad"
  blue-dark: "#94bcff"
  blue-contrast: "#004aab"
  on-action: "#ffffff"
  fjord: "#16323b"
  fjord-dark: "#0e1f26"
  fjord-light: "#2a4a55"
  fjord-light-dark: "#1c333d"
  bronze: "#b5763a"
  bronze-dark: "#d9a066"
  metal-light: "#d9a066"
  metal-light-dark: "#e8be8a"
  bone: "#e8e0d0"
  ember: "#c65a3a"
  ember-dark: "#d9765a"
  green: "#196542"
  green-dark: "#88ddb1"
  green-contrast: "#12582e"
  orange: "#854600"
  orange-dark: "#ffc784"
  orange-contrast: "#713d00"
  red: "#a42338"
  red-dark: "#ffa1af"
  red-contrast: "#930000"
  bg: "#f5f6fa"
  bg-dark: "#0e1f26"
  bg-contrast: "#ffffff"
  surface: "#ffffff"
  surface-dark: "#1c333d"
  text: "#182130"
  text-dark: "#f2f5fa"
  text-contrast: "#141414"
  muted: "#515f72"
  muted-dark: "#a9b8c4"
  muted-contrast: "#393939"
  line: "#d9e0eb"
  line-dark: "#2e4a52"
  line-contrast: "#6b6b6b"
  chrome: "#eef1f7"
  chrome-dark: "#14252d"
  chrome-contrast: "#ffffff"
  control: "#f0f3f8"
  control-dark: "#24404b"
  control-contrast: "#ffffff"
  control-line: "#7b889c"
  control-line-dark: "#7e8da3"
  control-line-contrast: "#6b6b6b"
typography:
  hero:
    fontFamily: "-apple-system,BlinkMacSystemFont,\"SF Pro Display\",sans-serif"
    fontSize: "23px"
    fontWeight: 650
    lineHeight: 1.16
  title:
    fontFamily: "-apple-system,BlinkMacSystemFont,\"SF Pro Display\",sans-serif"
    fontSize: "17px"
    fontWeight: 650
    lineHeight: 1.2
    letterSpacing: "-0.015em"
  body:
    fontFamily: "-apple-system,BlinkMacSystemFont,\"SF Pro Text\",sans-serif"
    fontSize: "13px"
    fontWeight: 400
    lineHeight: 1.38
  label:
    fontFamily: "-apple-system,BlinkMacSystemFont,\"SF Pro Text\",sans-serif"
    fontSize: "11px"
    fontWeight: 600
    lineHeight: 1.2
  caption:
    fontFamily: "-apple-system,BlinkMacSystemFont,\"SF Pro Text\",sans-serif"
    fontSize: "11px"
    fontWeight: 400
  mono:
    fontFamily: "\"SF Mono\",ui-monospace,monospace"
    fontSize: "13px"
    fontWeight: 400
rounded:
  control: "6px"
  card: "10px"
  window: "14px"
  pill: "11px"
spacing:
  space-4: "4px"
  space-8: "8px"
  space-12: "12px"
  space-16: "16px"
  space-24: "24px"
components:
  button-primary:
    backgroundColor: "{colors.primary}"
    textColor: "{colors.on-action}"
    typography: "{typography.body}"
    rounded: "{rounded.control}"
    height: "28px"
    padding: "4px 14px"
  button-secondary:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.text}"
    typography: "{typography.body}"
    rounded: "{rounded.control}"
    height: "28px"
    padding: "4px 14px"
  button-plain:
    backgroundColor: "transparent"
    textColor: "{colors.blue}"
    typography: "{typography.body}"
    rounded: "{rounded.control}"
    height: "28px"
    padding: "4px 3px"
  button-destructive:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.red}"
    typography: "{typography.body}"
    rounded: "{rounded.control}"
    height: "28px"
    padding: "4px 14px"
  button-disabled:
    backgroundColor: "{colors.line}"
    textColor: "{colors.muted}"
    typography: "{typography.body}"
    rounded: "{rounded.control}"
    height: "28px"
    padding: "4px 14px"
  protection-badge:
    textColor: "{colors.green}"
    typography: "{typography.label}"
    rounded: "{rounded.pill}"
    height: "22px"
    padding: "3px 8px"
  protection-badge-warning:
    textColor: "{colors.orange}"
  protection-badge-unknown:
    textColor: "{colors.orange}"
  protection-badge-frozen:
    textColor: "{colors.red}"
  protection-badge-neutral:
    textColor: "{colors.muted}"
  network-ledger:
    backgroundColor: "{colors.surface}"
    rounded: "{rounded.card}"
    padding: "8px 12px"
  network-field:
    textColor: "{colors.text}"
    height: "23px"
  app-row:
    textColor: "{colors.text}"
    typography: "{typography.body}"
    height: "44px"
  app-row-frozen:
    textColor: "{colors.red}"
  search-field:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.text}"
    typography: "{typography.body}"
    rounded: "{rounded.control}"
    padding: "0px 8px"
    height: "29px"
  settings-tab:
    textColor: "{colors.muted}"
    typography: "{typography.caption}"
    rounded: "{rounded.control}"
    width: "82px"
    height: "44px"
  settings-tab-selected:
    textColor: "{colors.blue}"
    typography: "{typography.label}"
  gate-rule:
    height: "1px"
  gate-scene:
    rounded: "{rounded.window}"
  countdown:
    backgroundColor: "{colors.line}"
    height: "5px"
---

# Design System: No-halla

## Overview

[Doop page map](design/HANDOFF.md#canvas-pages)

**Creative North Star: "The gate holds"**

No-halla shows the current protection state, its evidence and the next action in one glance. It uses compact macOS materials, grouped rows and native controls so an IP change is easy to read and act on.

The dark reference uses deep fjord for the shell and lifted fjord tones for groups and controls. A 1 pt bronze line with 24 strokes separates the popover header from network evidence. The rim, active-tab underline and waiting outline reuse the same bronze. The menu bar uses a monochrome template glyph.

**Key Characteristics:**

- Protection status leads the reading order.
- Network evidence and app states stay together.
- System blue identifies the main action and interactive controls.
- Dark is the default mockup reference. The app uses the system appearance, with light and Increase Contrast adaptations.

The visual values here mirror the offline references. The `primary` token is `action` in the project source. Appearance suffixes identify dark and Increase Contrast overrides. Chrome separates window toolbars and footers from content. The control surface and control boundary distinguish interactive elements from group dividers. Unlisted overrides inherit the light value. CSS pixels represent the reference dimensions in macOS points. [Source tokens](design/tokens.json) · [Brand](design/BRAND.md) · [Doop canvas](http://localhost:4300/c/2lgrE5QsCb)

## Colors

### Primary

- **Action Blue** fills the default action with an Action Label foreground. Use it for Resume all and enabled switches in HTML references.
- **Link Blue** identifies links, plain actions, settings selection and visible focus.

### Secondary

- **Deep Fjord** grounds the icon, art and dark shell. **Fjord Ridge** defines illustration depth and dark group surfaces.
- **Shield Bronze** defines the metal, gate line, pill rim, active tab underline and waiting rim. **Bronze Highlight** and **Bone** pick out the rim and line work. **Ember** is an occasional illustration accent.

### Tertiary

- **Trusted Green** identifies protected status and trusted network values.
- **Warning Amber** identifies grace, bypass and uncertainty.
- **Frozen Red** marks frozen apps, invalid fields and destructive Reset.

### Neutral

- **Window Ground** and **Group Surface** are tonal levels for the window and the grouped rows in the reference.
- **Primary Label** carries titles and values. **Secondary Label** carries helper text, captions and quiet states. **Separator** defines group boundaries and row divisions.

**The State Color Rule.** Pair each semantic color with a readable state label and a distinct glyph wherever a state glyph is shown.

## Typography

- **Hero** uses SF Pro Display at 23 pt, semibold, in onboarding and About.
- **Title** uses the system face at 17 pt, semibold. HTML uses the pinned system stack with the recorded title weight and tracking.
- **Body** uses SF Pro Text at 13 pt for settings, actions and app rows.
- **Label** and **caption** use SF Pro Text at 11 pt. Labels carry group or status information. Captions carry lore and supporting details in secondary text.
- **Technical values** use SF Mono at 13 pt with tabular numerals for the IP and interface. Keep settings measurements aligned with their controls.

Use sentence case for labels and actions. Let longer strings wrap at the native type size. Use the supplied English and Russian strings. [Copy catalog](design/copy.json)

## Layout

The 360 pt popover uses 16 pt outer padding and a 4 pt spacing rhythm. Place the app name and protection pill above the supporting caption. Group the current IP, VPN interface and trust result above the app list. Keep the state-specific action above the Settings and Quit footer. Give a single primary action the full content width.

App rows measure 44 pt. Allow 178 pt for four 44 pt app rows and two 1 pt group edges. Cap the visible app list at four rows and scroll the list when it grows. Keep the action and footer available. Settings (680 × 520 pt), onboarding (560 × 420 pt) and the app picker (480 × 520 pt) use native window or sheet layouts. In settings, align helper text with its label and controls with the trailing edge of each group. [Screen and view mapping](design/HANDOFF.md)

## Elevation & Depth

**The Platform Material Rule.** Use macOS for popover material, window chrome and elevation. In static mockups, use opaque fjord levels and an optional restrained shell gradient. Keep controls and status fills flat.

Use opaque surfaces with Reduce Transparency. Preserve the stronger separator in Increase Contrast. Keep flat group surfaces visually distinct from the window ground.

## Shapes

Use a small corner (6 pt) in HTML control references, a soft corner (10 pt) for group boundaries and the window reference radius (14 pt) on window-like mockup surfaces. Use an 11 pt radius on the 22 pt status pill and allow its label to wrap. Render the 18 pt menu bar glyph as a macOS template image. [Icon source and mappings](design/ICONS.md)

## Components

### Buttons and fields

Primary, secondary, plain, destructive and disabled buttons use native styles in SwiftUI. Choose fit or full width to suit the action area. Reset uses the destructive role. During checks, preserve the disabled action's accessible name. Show the system focus effect in SwiftUI and a 2 pt focus outline in HTML. Use a labeled, native-style search field in the app picker and show IP validation beside the affected field.

### Protection badge and countdown

The status pill pairs a short label with its state glyph inside a decorative 1 pt bronze rim. Keep the caption separate and in secondary text. Announce meaningful changes politely. Grace pairs the remaining time with a linear progress bar that updates once a second. With Reduce Motion, snap the bar on each tick. Keep icon state changes still.

### Network ledger and app row

Trailing network values align across the group. Set the IP and interface in monospace, use a dash for unavailable values and give Refresh its own accessible control name. Each app row carries a 20 pt app icon, visible app name, readable state and a switch named for the app. The installed app supplies icons through NSWorkspace. A switch changes the app's protection and keeps the row in place. Frozen rows have a 1 pt bronze waiting rim alongside the semantic Frozen label.

### Settings toolbar, groups and sheets

Give native sliders a target of at least 28 pt high. Use four icon-and-text tabs. Selected text and icon stay blue, with a 1 pt bronze underline. Group related settings with aligned control lanes and dividers. Use native sheets and alerts with standard action order. Keep keyboard focus visible and return it to the trigger when a sheet closes. [Component notes](design/COMPONENTS.md) · [Accessibility and keyboard behavior](design/ACCESSIBILITY.md)

## Do's and Don'ts

- Do keep Resume all and Quit visible in every applicable state.
- Do maintain 4.5:1 text contrast, a visible focus indicator and a 28 × 28 pt minimum pointer target.
- Do review dark first, then light, Increase Contrast, Reduce Transparency and Reduce Motion.
- Do preserve complete English and Russian labels at 360 pt and restore focus after closing a sheet.
- Keep bronze decorative. Use semantic colors for status text and blue for the primary action.
- Don't use red for Resume all or other safe actions.
- Don't add custom window chrome, decorative shadows or nested cards.
- Don't replace functional labels with lore or use rune glyphs in text.
