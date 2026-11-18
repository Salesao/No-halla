# No-halla implementation handoff

The design files and Doop frames define pixels, text, state hierarchy and assets. [IMPLEMENTATION_BRIEF.md](../docs/IMPLEMENTATION_BRIEF.md) defines engine behavior. SwiftUI views inherit macOS controls, materials, keyboard commands and accessibility. Use [tokens.json](tokens.json) for sizing and [copy.json](copy.json) for the EN/RU String Catalog.

Open the [Doop canvas](http://localhost:4300/c/2lgrE5QsCb) for the organized boards and the [prototype](http://localhost:4300/c/2lgrE5QsCb/proto?frame=N5jlKGQlWH) for wired flows. The [onboarding prototype](http://localhost:4300/c/2lgrE5QsCb/proto?frame=EcOSomJbr7) starts from step one. Offline mockups open in dark mode. Append `?theme=system` to follow the system appearance, or use `?theme=dark`, `?theme=light`, or `?theme=contrast`. Supporting states use the `view` parameter in the links below.

## Canvas pages

| Section | Dark | Light |
|---|---|---|
| Popover | [Dark](http://localhost:4300/c/2lgrE5QsCb?page=VhQCHx-t4F) | [Light](http://localhost:4300/c/2lgrE5QsCb?page=nN9fAsKP4i) |
| Onboarding | [Dark](http://localhost:4300/c/2lgrE5QsCb?page=KNbyZgl4MU) | [Light](http://localhost:4300/c/2lgrE5QsCb?page=yqjvqS4gCQ) |
| Settings | [Dark](http://localhost:4300/c/2lgrE5QsCb?page=ycBXMuSOWZ) | [Light](http://localhost:4300/c/2lgrE5QsCb?page=sU-ByIz9LC) |
| Sheets & alerts | [Dark](http://localhost:4300/c/2lgrE5QsCb?page=qiH9NGxqve) | [Light](http://localhost:4300/c/2lgrE5QsCb?page=_yRGjrdrbY) |
| Notifications | [Dark](http://localhost:4300/c/2lgrE5QsCb?page=lkBO2hXDze) | [Light](http://localhost:4300/c/2lgrE5QsCb?page=RS1hOK1_y1) |
| Identity & accessibility | [Dark](http://localhost:4300/c/2lgrE5QsCb?page=KDLmKrUJYG) | [Light](http://localhost:4300/c/2lgrE5QsCb?page=g-IhK7GLtR) |

[Dark prototype](http://localhost:4300/c/2lgrE5QsCb/proto?frame=Tg5Gv1n-l-)

Each section has a light and dark page with matching frame positions. Both appearances use the shared Components page. The dark prototype opens dark destinations for all linked screens. Dark precedes Light on the canvas and is the primary visual reference. Internal offline navigation retains the explicit appearance.

## Screen inventory

| Screen | Offline HTML | Doop frame | Dark Doop frame | SwiftUI view | FR | Tokens and copy |
|---|---|---|---|---|---|---|
| Popover · Protected | [HTML](mockups/popover-protected.html) | [Frame](http://localhost:4300/c/2lgrE5QsCb?frame=N5jlKGQlWH) | [Dark](http://localhost:4300/c/2lgrE5QsCb?frame=Tg5Gv1n-l-) | `PopoverView` | FR-7–14, FR-20–26 | popoverWidth, appRow, statusHeight · status.*, network.*, apps.*, action.*, caption.*, empty.* |
| Popover · Grace | [HTML](mockups/popover-grace.html) | [Frame](http://localhost:4300/c/2lgrE5QsCb?frame=XDSw3Aoesd) | [Dark](http://localhost:4300/c/2lgrE5QsCb?frame=_WvfyGJYtO) | `PopoverView` | FR-7–14, FR-20–26 | popoverWidth, appRow, statusHeight · status.*, network.*, apps.*, action.*, caption.*, empty.* |
| Popover · Frozen | [HTML](mockups/popover-frozen.html) | [Frame](http://localhost:4300/c/2lgrE5QsCb?frame=i6Cr3lTgHf) | [Dark](http://localhost:4300/c/2lgrE5QsCb?frame=9tCQAVsd7q) | `PopoverView` | FR-7–14, FR-20–26 | popoverWidth, appRow, statusHeight · status.*, network.*, apps.*, action.*, caption.*, empty.* |
| Popover · Unknown | [HTML](mockups/popover-unknown.html) | [Frame](http://localhost:4300/c/2lgrE5QsCb?frame=udKORrbP2Z) | [Dark](http://localhost:4300/c/2lgrE5QsCb?frame=WNBOGxEBLJ) | `PopoverView` | FR-7–14, FR-20–26 | popoverWidth, appRow, statusHeight · status.*, network.*, apps.*, action.*, caption.*, empty.* |
| Popover · Paused | [HTML](mockups/popover-paused.html) | [Frame](http://localhost:4300/c/2lgrE5QsCb?frame=tBCUslj0mV) | [Dark](http://localhost:4300/c/2lgrE5QsCb?frame=FvRzVBSEVN) | `PopoverView` | FR-7–14, FR-20–26 | popoverWidth, appRow, statusHeight · status.*, network.*, apps.*, action.*, caption.*, empty.* |
| Popover · Setup | [HTML](mockups/popover-empty.html?view=popover-setup) | [Frame](http://localhost:4300/c/2lgrE5QsCb?frame=1clLdl6JZl) | [Dark](http://localhost:4300/c/2lgrE5QsCb?frame=ZKUQH-wBFq) | `PopoverView` | FR-7–14, FR-20–26 | popoverWidth, appRow, statusHeight · status.*, network.*, apps.*, action.*, caption.*, empty.* |
| Popover · Empty | [HTML](mockups/popover-empty.html) | [Frame](http://localhost:4300/c/2lgrE5QsCb?frame=HUYImENMe1) | [Dark](http://localhost:4300/c/2lgrE5QsCb?frame=Y4bAIRoc03) | `PopoverView` | FR-7–14, FR-20–26 | popoverWidth, appRow, statusHeight · status.*, network.*, apps.*, action.*, caption.*, empty.* |
| Popover · Checking | [HTML](mockups/popover-protected.html?view=popover-checking) | [Frame](http://localhost:4300/c/2lgrE5QsCb?frame=KJz79rppn2) | [Dark](http://localhost:4300/c/2lgrE5QsCb?frame=6dcSXuyPFR) | `PopoverView` | FR-7–14, FR-20–26 | popoverWidth, appRow, statusHeight · status.*, network.*, apps.*, action.*, caption.*, empty.* |
| Popover · Disabled | [HTML](mockups/popover-paused.html?view=popover-disabled) | [Frame](http://localhost:4300/c/2lgrE5QsCb?frame=mudDw0Ys8j) | [Dark](http://localhost:4300/c/2lgrE5QsCb?frame=tt3oQiE2RR) | `PopoverView` | FR-7–14, FR-20–26 | popoverWidth, appRow, statusHeight · status.*, network.*, apps.*, action.*, caption.*, empty.* |
| Popover · Bypass | [HTML](mockups/popover-frozen.html?view=popover-bypass) | [Frame](http://localhost:4300/c/2lgrE5QsCb?frame=smNlqOV5oJ) | [Dark](http://localhost:4300/c/2lgrE5QsCb?frame=jwr68aqL6d) | `PopoverView` | FR-7–14, FR-20–26 | popoverWidth, appRow, statusHeight · status.*, network.*, apps.*, action.*, caption.*, empty.* |
| Popover · First-run | [HTML](mockups/popover-empty.html?view=popover-first-run) | [Frame](http://localhost:4300/c/2lgrE5QsCb?frame=bctBjn_E6B) | [Dark](http://localhost:4300/c/2lgrE5QsCb?frame=wmqWsJkDz_) | `PopoverView` | FR-7–14, FR-20–26 | popoverWidth, appRow, statusHeight · status.*, network.*, apps.*, action.*, caption.*, empty.* |
| Popover · Offline | [HTML](mockups/popover-unknown.html?view=popover-offline) | [Frame](http://localhost:4300/c/2lgrE5QsCb?frame=ZPwV0G-eQ-) | [Dark](http://localhost:4300/c/2lgrE5QsCb?frame=ayXn5tLbu3) | `PopoverView` | FR-7–14, FR-20–26 | popoverWidth, appRow, statusHeight · status.*, network.*, apps.*, action.*, caption.*, empty.* |
| Onboarding · 1 of 3 | [HTML](mockups/onboarding-1.html) | [Frame](http://localhost:4300/c/2lgrE5QsCb?frame=EcOSomJbr7) | [Dark](http://localhost:4300/c/2lgrE5QsCb?frame=P2vx66siZD) | `OnboardingIntroView` | FR-2, FR-3, FR-10, FR-26, FR-29 | onboarding, spacing · onboarding.*, network.*, ui.* |
| Onboarding · 2 of 3 | [HTML](mockups/onboarding-2.html) | [Frame](http://localhost:4300/c/2lgrE5QsCb?frame=9FE5ygadyK) | [Dark](http://localhost:4300/c/2lgrE5QsCb?frame=cMkcKUins9) | `OnboardingAppsView` | FR-2, FR-3, FR-10, FR-26, FR-29 | onboarding, spacing · onboarding.*, network.*, ui.* |
| Onboarding · 3 of 3 | [HTML](mockups/onboarding-3.html) | [Frame](http://localhost:4300/c/2lgrE5QsCb?frame=WQ26JM1mrr) | [Dark](http://localhost:4300/c/2lgrE5QsCb?frame=HpSYUgnIxW) | `OnboardingTrustedRealmView` | FR-2, FR-3, FR-10, FR-26, FR-29 | onboarding, spacing · onboarding.*, network.*, ui.* |
| Onboarding · Trusted IP saved | [HTML](mockups/onboarding-3.html?view=onboarding-trusted) | [Frame](http://localhost:4300/c/2lgrE5QsCb?frame=kOQEikAWc9) | [Dark](http://localhost:4300/c/2lgrE5QsCb?frame=gs2vDB3r2a) | `OnboardingTrustedRealmView` | FR-2, FR-3, FR-10, FR-26, FR-29 | onboarding, spacing · onboarding.*, network.*, ui.* |
| Onboarding · Invalid IP | [HTML](mockups/onboarding-3.html?view=onboarding-invalid) | [Frame](http://localhost:4300/c/2lgrE5QsCb?frame=BNHXMlZDM0) | [Dark](http://localhost:4300/c/2lgrE5QsCb?frame=iGuClE069a) | `OnboardingTrustedRealmView` | FR-2, FR-3, FR-10, FR-26, FR-29 | onboarding, spacing · onboarding.*, network.*, ui.* |
| Settings · General | [HTML](mockups/settings-general.html) | [Frame](http://localhost:4300/c/2lgrE5QsCb?frame=CWy9CQI501) | [Dark](http://localhost:4300/c/2lgrE5QsCb?frame=ulEknzqO5A) | `SettingsGeneralView` | FR-3, FR-27, FR-29–31 | settings, control, card · ui.*, network.*, apps.*, brand.* |
| Settings · Protection | [HTML](mockups/settings-protection.html) | [Frame](http://localhost:4300/c/2lgrE5QsCb?frame=Ap5CuLfDtV) | [Dark](http://localhost:4300/c/2lgrE5QsCb?frame=mLcyWUYkPd) | `SettingsProtectionView` | FR-10, FR-13, FR-14, FR-21, FR-27 | settings, control, card · ui.*, network.*, apps.*, brand.* |
| Settings · Advanced | [HTML](mockups/settings-advanced.html) | [Frame](http://localhost:4300/c/2lgrE5QsCb?frame=1hhs8PSy00) | [Dark](http://localhost:4300/c/2lgrE5QsCb?frame=rYFgsRzK6v) | `SettingsAdvancedView` | FR-8, FR-22, FR-27, FR-32 | settings, control, card · ui.*, network.*, apps.*, brand.* |
| Settings · About | [HTML](mockups/settings-about.html) | [Frame](http://localhost:4300/c/2lgrE5QsCb?frame=hClcsS_3lF) | [Dark](http://localhost:4300/c/2lgrE5QsCb?frame=Jv4kDd0d0H) | `SettingsAboutView` | FR-27, FR-33–36 | settings, control, card · ui.*, network.*, apps.*, brand.* |
| General · Permissions and login error | [HTML](mockups/settings-general.html?view=settings-errors) | [Frame](http://localhost:4300/c/2lgrE5QsCb?frame=NS1mBXpc-1) | [Dark](http://localhost:4300/c/2lgrE5QsCb?frame=gpRzs1U6vb) | `SettingsGeneralView` | FR-3, FR-27, FR-29–31 | settings, control, card · ui.*, network.*, apps.*, brand.* |
| Sheet · Add apps | [HTML](mockups/app-picker.html) | [Frame](http://localhost:4300/c/2lgrE5QsCb?frame=plbkneRLKx) | [Dark](http://localhost:4300/c/2lgrE5QsCb?frame=UqxeAQbLVx) | `AppPickerSheet` | FR-15, FR-17, FR-26, FR-28 | picker, appIcon, targetMin · apps.*, ui.* |
| Sheet · Add disabled | [HTML](mockups/app-picker.html?view=app-picker-empty) | [Frame](http://localhost:4300/c/2lgrE5QsCb?frame=gLaKPFLBK-) | [Dark](http://localhost:4300/c/2lgrE5QsCb?frame=nUneW6BeLj) | `AppPickerSheet` | FR-15, FR-17, FR-26, FR-28 | picker, appIcon, targetMin · apps.*, ui.* |
| Alert · Quit and resume | [HTML](mockups/quit-confirm.html) | [Frame](http://localhost:4300/c/2lgrE5QsCb?frame=_MP2B_kKlw) | [Dark](http://localhost:4300/c/2lgrE5QsCb?frame=NhCfLtVfCP) | `QuitConfirmationAlert` | FR-4, FR-26 | window, targetMin · quit.*, action.cancel |
| Alert · Reset all settings | [HTML](mockups/settings-advanced.html?view=reset-confirm) | [Frame](http://localhost:4300/c/2lgrE5QsCb?frame=y5mW2uudG3) | [Dark](http://localhost:4300/c/2lgrE5QsCb?frame=jmcPcR_qIp) | `ResetSettingsAlert` | FR-27 | window, control · ui.* |
| Sheet · Edit trusted IP | [HTML](mockups/settings-protection.html?view=trusted-ip-edit) | [Frame](http://localhost:4300/c/2lgrE5QsCb?frame=Yomai3gKFD) | [Dark](http://localhost:4300/c/2lgrE5QsCb?frame=ub2deIyheG) | `TrustedAddressEditor` | FR-10, FR-27 | window, control, mono · network.*, ui.* |
| Sheet · Edit IPv4 endpoint 1 | [HTML](mockups/settings-advanced.html?view=endpoint-edit) | [Frame](http://localhost:4300/c/2lgrE5QsCb?frame=5UXXlXYHVl) | [Dark](http://localhost:4300/c/2lgrE5QsCb?frame=O-qMfFkZMp) | `EndpointEditor` | FR-8, FR-27 | window, control, mono · ui.* |
| Sheet · Edit IPv4 endpoint 2 | [HTML](mockups/settings-advanced.html?view=endpoint-ipv4-2) | [Frame](http://localhost:4300/c/2lgrE5QsCb?frame=-x1juRXg1k) | [Dark](http://localhost:4300/c/2lgrE5QsCb?frame=ARAM-SfegD) | `EndpointEditor` | FR-8, FR-27 | window, control, mono · ui.* |
| Sheet · Edit IPv4 endpoint 3 | [HTML](mockups/settings-advanced.html?view=endpoint-ipv4-3) | [Frame](http://localhost:4300/c/2lgrE5QsCb?frame=GhiVD8nnjq) | [Dark](http://localhost:4300/c/2lgrE5QsCb?frame=esyYrNHXH2) | `EndpointEditor` | FR-8, FR-27 | window, control, mono · ui.* |
| Sheet · Edit IPv4 endpoint 4 | [HTML](mockups/settings-advanced.html?view=endpoint-ipv4-4) | [Frame](http://localhost:4300/c/2lgrE5QsCb?frame=BlhGGm0Esm) | [Dark](http://localhost:4300/c/2lgrE5QsCb?frame=qRY1lBL3Z8) | `EndpointEditor` | FR-8, FR-27 | window, control, mono · ui.* |
| Sheet · Edit IPv6 endpoint 1 | [HTML](mockups/settings-advanced.html?view=endpoint-ipv6-1) | [Frame](http://localhost:4300/c/2lgrE5QsCb?frame=lyDFraOhmS) | [Dark](http://localhost:4300/c/2lgrE5QsCb?frame=d-orntaAt5) | `EndpointEditor` | FR-8, FR-27 | window, control, mono · ui.* |
| Sheet · Edit IPv6 endpoint 2 | [HTML](mockups/settings-advanced.html?view=endpoint-ipv6-2) | [Frame](http://localhost:4300/c/2lgrE5QsCb?frame=GruFw6iWAD) | [Dark](http://localhost:4300/c/2lgrE5QsCb?frame=8TgWa_nUd_) | `EndpointEditor` | FR-8, FR-27 | window, control, mono · ui.* |
| Sheet · Invalid HTTPS endpoint | [HTML](mockups/settings-advanced.html?view=endpoint-invalid) | [Frame](http://localhost:4300/c/2lgrE5QsCb?frame=ExTzITRzFk) | [Dark](http://localhost:4300/c/2lgrE5QsCb?frame=D8jnveqhuB) | `EndpointEditor` | FR-8, FR-27 | window, control, mono · ui.* |
| Notification · Frozen | [HTML](mockups/popover-frozen.html?view=notification-frozen) | [Frame](http://localhost:4300/c/2lgrE5QsCb?frame=LReuLhWfTG) | [Dark](http://localhost:4300/c/2lgrE5QsCb?frame=hpQ2cVtTRe) | `NotificationCoordinator` | FR-29 | appIcon · notification.*, action.* |
| Notification · Resumed | [HTML](mockups/popover-protected.html?view=notification-resumed) | [Frame](http://localhost:4300/c/2lgrE5QsCb?frame=NKTI67FFfB) | [Dark](http://localhost:4300/c/2lgrE5QsCb?frame=C7BMm3wIGJ) | `NotificationCoordinator` | FR-29 | appIcon · notification.*, action.* |
| Notification · Unknown | [HTML](mockups/popover-unknown.html?view=notification-unknown) | [Frame](http://localhost:4300/c/2lgrE5QsCb?frame=1iD6_jzs6y) | [Dark](http://localhost:4300/c/2lgrE5QsCb?frame=dhCe2__nlH) | `NotificationCoordinator` | FR-29 | appIcon · notification.*, action.* |
| Identity · App icon and menu bar | [HTML](mockups/settings-about.html?view=brand) | [Frame](http://localhost:4300/c/2lgrE5QsCb?frame=aQg0SzeaxF) | [Dark](http://localhost:4300/c/2lgrE5QsCb?frame=kDZeH7nmKw) | `AppIcon / MenuBarIcon` | FR-33–36 | menuBar, colors.fjord, colors.bronze · brand.*, ui.no-halla-* |
| Popover · Frozen / Dark | [HTML](mockups/popover-frozen.html?view=popover-dark) | [Frame](http://localhost:4300/c/2lgrE5QsCb?frame=9tCQAVsd7q) | — | `PopoverView` | FR-7–14, FR-20–26 | popoverWidth, appRow, statusHeight · status.*, network.*, apps.*, action.*, caption.*, empty.* |
| Popover · Grace / Russian | [HTML](mockups/popover-grace.html?view=popover-ru) | [Frame](http://localhost:4300/c/2lgrE5QsCb?frame=JeuHb7_bGB) | [Dark](http://localhost:4300/c/2lgrE5QsCb?frame=o3yh6kQq5c) | `PopoverView` | FR-7–14, FR-20–26 | popoverWidth, appRow, statusHeight · status.*, network.*, apps.*, action.*, caption.*, empty.* |
| Popover · Protected / Increase contrast | [HTML](mockups/popover-protected.html?view=popover-contrast) | [Frame](http://localhost:4300/c/2lgrE5QsCb?frame=V6b_doMU8d) | — | `PopoverView` | FR-7–14, FR-20–26 | popoverWidth, appRow, statusHeight · status.*, network.*, apps.*, action.*, caption.*, empty.* |
| Settings · Protection / Dark | [HTML](mockups/settings-protection.html?view=settings-dark) | [Frame](http://localhost:4300/c/2lgrE5QsCb?frame=mLcyWUYkPd) | — | `SettingsProtectionView` | FR-10, FR-13, FR-14, FR-21, FR-27 | settings, control, card · ui.*, network.*, apps.*, brand.* |

## Asset installation

| Asset | Import |
|---|---|
| [App icon](exports/appicon-1024.png) and [editable source](exports/appicon.svg) | Asset catalog `AppIcon.appiconset`. Create each required macOS marketing and application size from the source. |
| [Menu bar SVG](exports/menubar-icons.svg) | Five template images. Names and symbol IDs are in [ICONS.md](ICONS.md). |
| [Brand reference](exports/brand-sheet.svg) | Reference art for the gate and About ornament. The brand source and fallback rules are in [BRAND.md](BRAND.md). |
| Application icons | Obtain them through NSWorkspace in the SwiftUI app. |

## Technical names

| Field | Value |
|---|---|
| Display name | No-halla |
| Target and module | NoHalla |
| Bundle ID | dev.nohalla.NoHalla |
| Watchdog bundle ID | dev.nohalla.NoHallaWatchdog |
| Application Support directory | NoHalla |

The Doop interactions demonstrate transitions with sample data. The offline mocks also implement local input and search feedback. Timed checks, user preferences, system panels and process actions are defined in the implementation brief. [Accessibility checks](ACCESSIBILITY.md) include the checks to run on the native build. [Open questions](OPEN_QUESTIONS.md) records the decisions that still need confirmation.
