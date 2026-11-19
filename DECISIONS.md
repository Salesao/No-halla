# Decisions

Log of deviations and ambiguous design/implementation decisions with their rationale (per `AGENTS.md`).

## 2026-11-19 — Design brief: dark-first native brand shell

**Decision.** Rework `docs/DESIGN_BRIEF.md` away from strict native minimalism toward a **dark-first native brand shell**, following the system appearance. The established fjord/bronze/gate world is expanded into the UI, not replaced.

**Why.** The previous brief confined the brand (fjord/bronze/bone) to the icon, illustrations and About, while the app UI itself was stock neutral gray (dark bg `#1b1e25`). The product did not feel Norse in use. The owner asked for a less minimalist brief with an accent on the dark theme.

**Approach chosen (owner-approved).**

- Brand layer inside a native frame: native controls (`Form`/`List`/`MenuBarExtra`), status clarity and accessibility stay intact.
- Follow system appearance, **dark-first**: dark is the primary design target and the reference for mockups; light is a full adaptation. Dark is not forced.

**What changed in the brief.**

- Dark shell is fjord-tinted, not neutral gray: bg `#0E1F26`, surface `#1C333D`, chrome `#14252D`, control `#24404B`, separator `#2E4A52`.
- Bronze enters the UI as an identity accent (header gate-line, status-pill rim, selected-tab indicator, frozen-row "waiting" rim). It is never used for text, status meaning, or the primary button.
- Primary action stays the project action blue (`#1B5EC4` light / `#2865C6` dark); semantic status colors use contrast-safe dark tonal variants (`#88DDB1` / `#FFC784` / `#FFA1AF`).
- Gradient ban relaxed: soft tonal fjord gradient allowed on the shell and onboarding/About hero illustrations and the icon metal; never on controls, statuses or text. No neon/glow/glassmorphism.
- Richer hero moments: onboarding step 1 and About get a larger fjord gate illustration and a 22–24 pt SF Pro Display hero title; empty states get a small illustration; the 24-tick ornament recurs as a divider.
- Sections revised: intro, §3, §4, §7, §10 (visual language + new shell tokens), §11, §12, §13, §14, §15.

**What stays (product truth).** Scope, IA, state model, interactions, copy keys, EN/RU, native controls, one-click `Resume all`, semantic color redundancy, and all accessibility requirements (4.5:1 text, 3:1 non-text, 28 pt targets, keyboard, VoiceOver, Increase Contrast / Reduce Transparency / Reduce Motion).

**Contrast verified.** Proposed dark tokens were checked: text/bg 15.5:1, muted/surface 6.5:1, bronze/bg 7.4:1, control-line/control 3.26:1, white/action 5.6:1, semantic variants ≥6.9:1 on surface.

**Follow-up (completed).** The [Doop canvas](http://localhost:4300/c/2lgrE5QsCb?page=VhQCHx-t4F), the 15 offline HTML references, `DESIGN.md` and the handoff now use the dark-first shell. Light status fills use 4% tint to keep the bronze rim at 3:1 or better. Settings rails use the control boundary token at 28 pt hit height. Four app rows fit before internal scrolling. All 280 Doop prototype interactions were preserved.

## 2026-11-19 — v1 implementation (orca-pod run e1363f11, plan-v1)

Implementation of M1–M6 across three reviewed stages (S1 core, S2 processes+reliability, S3 UI+brand+docs). Decisions below reference the approved specification (`docs/superpowers/specs/2026-11-19-no-halla-v1-spec.md`) and plan (`docs/superpowers/plans/2026-11-19-no-halla-v1.md`).

### Owner-mandated scope deviation

- **D2 — Tests excluded.** By explicit owner mandate, no unit/integration tests are written, changed or run; no test targets and no `scripts/test.sh` are created; no TDD. This deviates from brief §4/§8.10/§9/NFR-6. Verification is static: `xcodegen generate` + `xcodebuild` Release universal typecheck + structural checks (plutil/test/grep). The 20-scenario manual matrix and runtime VoiceOver/contrast checks are the owner's checklist in README (D6). The app is not launched by the pipeline.

### Specification decisions implemented

- **D9 — Assets.** AppIcon generated from `design/exports/appicon-1024.png` via `sips` (all macOS sizes); the five menu bar glyphs split from `menubar-icons.svg` into template imagesets by `scripts/gen-assets.py` (python3 stdlib); GateScene SVG asset. The `qlmanage` rasterization fallback was not needed (SVG renders in the catalog).
- **D11 — `logLevel`.** Added `logLevel: info|debug` (default `info`) to the config schema (brief §5.4 extension) for the Advanced → Log level control.
- **D12 — Language in-process.** System/English/Русский selection applies without relaunch via `L10n` reading the selected `.lproj` bundle; "Apply language change" button. System panels stay on the system language.
- **D13 — Layout additions.** `Core/Logging/`, `Core/Notifications/`, `Core/Process/ProcessControlling.swift` (seam), `UI/Theme/`, `UI/Localization/`, `App/AppState.swift` added to brief §4 layout.
- **D14 — Diagnostics.** ZIP via system `/usr/bin/zip`; last-15-min logs via `OSLogStore(scope: .currentProcessIdentifier)` (`position(date:)` + `getEntries(at:)`), best-effort with an `export-notes.txt` note when unavailable (ad-hoc bundle risk); config/state/versions included; no automatic sending.
- **D16 — `.gitignore`.** Created with `build/`, `DerivedData/`, `.DS_Store`, `NoHalla.xcodeproj`, `.orca-pod/`; also `graphify-out/` and `.impeccable/` (generated tool artifacts).
- **D17 — XcodeGen.** Installed via Homebrew (2.47.0).
- **D19 — Check interval.** Range 10–120 s, default 30 (design §7.4).
- **D20 — Quit confirmation.** Shown only when apps are frozen; native alert; after confirm resume all + clear state + stop watchdog.
- **D21 — About.** Version 0.1.0, tagline, MIT; `LICENSE` MIT; README per brief §4.
- **D22 — Additive strings.** `design/copy.json` extended additively (144→155 keys) and the catalog regenerated. Parameterized mock literals: `caption.resumeBypass` (%d), `ui.checking-resumes-at-14-32` (%@), `ui.2-apps-selected` (%d), `ui.version-0-1-0` (%@); normalized `{app}`/`{family}` → %@. New keys: `ui.corrupt-config-title/body` (FR-38), `ui.log-level-info/debug`, `ui.unit-seconds/minutes`, `ui.protection-toggle-helper` (D27), `ui.language-english/russian`, `notification.frozen.reason-changed`, `notification.app-count` (%d, R35).
- **D23 — Esc in MenuBarExtra.** `.menuBarExtraStyle(.window)` kept (brief mandate). Esc dismissal is best-effort within MenuBarExtra; if not reachable on macOS 13 it is an accessibility gap noted here and in README.
- **D24 — Grace range 0–120.** Config and slider use 0–120 s (default 5), deviating from the mockup's 0–60; owner-approved.
- **D25 — Cancel during grace.** Immediate re-check → `checking`, no hidden bypass; if still disallowed the countdown restarts.
- **D26 — Repository hidden.** The About Repository row is hidden until a real URL exists; `ui.repository` unused.
- **D27 — Master Protection toggle.** At the top of the Protection tab; off → resume all + `protection.enabled=false` → `disabled`; on → `checking`.
- **D28 — IPv6 lattice.** Quorum per family; any disallowed → disallowed; else any unknown → unknown; else allowed. Unverifiable IPv6 (egress, no quorum) → unknown; known untrusted IPv6 → disallowed; `requireVPNInterface` without tunnel → disallowed.

### Implementation decisions within builder discretion (R18)

- **Watchdog embed.** XcodeGen `embed: true` defaulted to `Contents/Resources`; used dependency `copy: { destination: executables }` so the binary lands in `Contents/MacOS/NoHallaWatchdog` (verified `test -x`).
- **NetworkMonitor.** Brief pseudo-code `NWPathMonitor(requiredInterfaceType: .any)` is not a real API → `NWPathMonitor()`. `SCDynamicStoreInvalidate` is not public → teardown via `SCDynamicStoreSetDispatchQueue(store, nil)`. C callout uses a non-capturing closure literal.
- **IPVerifier family split (R4).** Requests keep the endpoint hostname (native SNI + certificate name check); families separated by the RESPONSE family; an empty family answer set → `noQuorum` → `unknown` (D28). A numeric-IP-literal transport force was rejected after it broke TLS (measured).
- **ProcessEnumerator (R32).** `proc_listallpids`/`proc_listchildpids` return a pid COUNT capped at buffer size; a `capacity + 1` sentinel slot detects truncation (`count > capacity` → grow). Verified to enumerate the full table; the NULL-size hint is avoided (valid only for `proc_listallpids`).
- **Startup recovery (R33).** `recoverStaleFrozen` resumes directly from `state.json` records (identity-check + SIGCONT), then clears state — the controller's in-memory dict is empty after restart.
- **Reconcile (R34).** Resumes frozen processes of apps removed/disabled from protection, in addition to freezing new instances and pruning exited/reused pids.
- **Localized notifications (R35).** Notification bodies use L10n keys only (`notification.frozen.reason-changed`, `notification.app-count`); the `NotificationEvent` seam is unchanged (localized descriptor instead of a real IP).

### Accepted risks carried to the manual matrix / Chief

- **R29 — Dual-stack v4 endpoints.** On a host with IPv6 egress, the default dual-stack v4 endpoints may return no IPv4 answer → `unknown` → freeze when `freezeWhenUnknown` (default). This is FR-11/D28-compatible honest behavior, not a code defect. Remedy is a defaults-level decision: add a dedicated IPv4-only endpoint (e.g. `https://api.ipify.org`, which is A-only) or disable `checkIPv6`/`freezeWhenUnknown` as appropriate. Not reproducible on the build machine (no IPv6 route). Owners can add their own endpoint in Advanced settings.
- **R30 — Recovery nuances.** Recovery signals outside the controller (by design, from persisted records) and clears state after the resume pass; a failed SIGCONT is logged. Identity-check prevents signaling a reused pid. Accepted for the manual matrix.
- **R52 — Notification pluralization.** `notification.app-count` uses `%d` ("1 apps"/"5 приложения"); full RU/EN plural forms via xcstrings plural variations + `String.localizedStringWithFormat` in `L10n` are a follow-up localization refinement (the mixed-language defect itself is fixed by R35).
- Other accepted non-blocking findings (R7–R12, R14–R16, R19–R20, R23–R25, R36–R51) are recorded in the stage review reports under `.orca-pod/reports/plan-v1/`.

## 2026-11-19 — D29: crash recovery semantics (plan-v2 / spec-v2, revision C2)

**Decision (owner-approved, blitz revision C2, option D «Полное восстановление»).** Crash recovery uses **identity-checked intent recovery** (literal brief FR-42): the frozen record is written durably BEFORE `SIGSTOP`; both startup (`ProtectionEngine.recoverStaleFrozen`) and the watchdog (`NoHallaWatchdog` `recoverFrozenProcesses`) resume identity-matched records (pid + process start time), skipping a reused pid. This guarantees **G1** (FR-41/42): every process No-halla stopped is resumed after a crash, including a crash after a successful `SIGSTOP` but before any post-stop confirmation.

**Accepted residual risk (G2 relaxation).** The pre-write intent record is byte-identical whether the subsequent `SIGSTOP` succeeded, failed, or never ran (crash). Identity proves the process, not who stopped it. In the narrow window — intent written, `SIGSTOP` not yet issued / crash before confirmation, and the process independently paused by another agent (e.g. a debugger) inside a protected bundle — recovery may resume a pause No-halla did not create. This residual risk is **accepted by the owner**. Exposure is narrowed by `SafetyGuard` (only processes inside a selected `.app`, owned by the current user, not deny-listed). Recommendation: do not use third-party pauses (debuggers) on protected apps while No-halla is active.

**Rejected alternatives.** B (confirmed-stop journal written only after `SIGSTOP`) leaves a FR-41 gap on crash-after-stop-before-write; C (two-phase journal + `proc_bsdinfo` `SSTOP`/`P_TRACED` heuristic) is best-effort and adds platform complexity. Moving the write after `SIGSTOP` and ignoring pending records are forbidden (they break G1). No new recovery semantics beyond D29.

**Analysis.** `.orca-pod/reports/plan-v1/C2-guarantee-conflict.md` (G1/G2 incompatibility), `chief-attempt4.md` (Chief criterion), spec-v2 D29 / plan-v2 revision C2 (owner decision). The real C2 races (single journal owner, lock-synchronized persist hook, explicit rollback reporting, identity re-check after I/O, inactive-protection guard) were closed in Chief rounds 1–4; D29 resolves the remaining semantic conflict by owner decision, not a code change.

## 2026-11-19 — User-requested UX changes (post-acceptance, direct owner request)

**Decision (owner chose via interactive questions).** Two deviations from the original brief, requested directly by the owner after running the app:
- **Dock icon (deviates from FR-1 / LSUIElement).** `Info.plist` `LSUIElement` set to `false` so No-halla also appears in the Dock (the menu bar shield remains). Clicking the Dock icon with no visible window opens Settings (`applicationShouldHandleReopen`). The app is still primarily a menu bar agent.
- **Minimize frozen apps to the Dock.** On freeze, a protected app's windows are minimized to the Dock (so a frozen app does not sit on screen looking hung); on resume they are restored. Implemented in `Core/Process/WindowMinimizer.swift` via the public Accessibility API (`AXUIElement`, `kAXMinimizedAttribute`), invoked by the engine before `SIGSTOP` (with a short settle delay) and restored after `SIGCONT`. **Requires Accessibility permission** (System Settings → Privacy & Security → Accessibility); the app prompts once on first freeze. Without permission it falls back to hiding the app (`NSRunningApplication.hide/unhide`). Window actions run before freeze / after resume because a frozen app cannot process them.

**Also fixed.** The popover Settings button did not bring the Settings window to the front (an `LSUIElement` agent is not active by default); `openSettings()` now activates the app first.

**Note on the freeze principle (owner question).** A freeze can occur even with a trusted current IP when the IP cannot be *verified* (endpoint quorum not reached → `unknown`) and `freezeWhenUnknown` is on (default). This is FR-11/D28 behavior, not a bug; the trusted IP must be successfully verified to stay Protected. The current IP was in fact added to the trusted list correctly.

## 2026-11-19 — User-requested windowed app experience (direct owner request)

**Decision (owner: «хочу как отдельное открывающееся приложение, как Telegram»).** No-halla now presents a regular main window in addition to the menu bar shield:
- A primary `WindowGroup` opens the main window on launch and from the Dock. `MainWindowView` shows the three-step onboarding until completed, then the protection dashboard with a Settings toolbar button.
- The dashboard content is extracted into a shared `DashboardView` reused by both the main window and the menu bar popover (`PopoverView` is now a thin 360 pt wrapper + Settings/Quit footer).
- Settings opens via the native `SettingsLink` (macOS 14+; `SettingsButton` falls back to activate + `showSettingsWindow:` on macOS 13) — fixes the earlier «Settings button does nothing» (the `sendAction`-only approach was unreliable in a MenuBarExtra configuration).
- Onboarding is embedded in the main window (no separate onboarding Window scene); `OnboardingContainerView.finish()` no longer dismisses — the main window reactively switches to the dashboard once `onboardingCompleted` is true.
- Dock click reopen shows the main window (`applicationShouldHandleReopen` returns true with a WindowGroup).

This deviates from the brief's pure menu bar agent architecture (FR-1/§8.8) by owner request; the menu bar shield and all protection logic are unchanged. Clean universal build green; commit 8968ea9.

## 2026-11-19 — User-requested simple whitelist IP model (direct owner request)

**Decision (owner: «IP в белом списке → работаем; IP не в белом списке → морозим», без лишнего «unknown»).** Simplified the IP decision to the owner's binary model:
- **`freezeWhenUnknown` default `false`** (was `true`): an unverifiable IP (endpoints unavailable) NO LONGER freezes apps — they keep running. Freeze happens only when the current IP is KNOWN and not in the trusted whitelist. The toggle remains in Settings → Protection for flexibility.
- **`quorum` default `1`** (was `2`): a single responding endpoint suffices to determine the IP (no 2-of-4 agreement required). Disagreement between multiple responses still yields unknown (which now does not freeze).
- The owner's existing `config.json` was updated to match (`freezeWhenUnknown=false`, `quorum=1`).

**Tradeoff accepted by owner:** if the VPN drops AND the check endpoints are unreachable, the IP cannot be determined and apps are NOT frozen (protection does not trigger in that moment). Simplicity is prioritized over the fail-safe freeze. Public-IP discovery still requires an external endpoint (the computer cannot know its public IP locally); the simplification is in the decision logic, not in eliminating discovery. Deviates from brief §13 defaults (freezeWhenUnknown=true, quorum=2) by owner request.

## 2026-11-19 — User-requested hybrid protection mode (direct owner request)

**Decision (owner: «переключатель — или по IP, или по VPN-туннелю; запрос чтобы узнать IP — без проблем»).** Added a protection mode switch (`ProtectionSettings.mode`, `ProtectionMode` enum), default `.vpnInterface`:
- **`.vpnInterface` (VPN tunnel, no external query):** the engine decides trust purely locally via `NetworkMonitor.activeVPNInterface()` — a utun/ipsec/ppp/tun interface carrying a GLOBAL address (excludes loopback 127.x/::1 and link-local 169.254.x/fe80::, so system tunnels like iCloud Private Relay are not mistaken for the VPN). VPN present → allowed (Protected); VPN absent → disallowed (grace → freeze). Deterministic, no `unknown` state, no endpoint dependency. Verified on the owner's machine: detects `utun4` (198.18.0.1), ignores link-local-only system utun interfaces.
- **`.ipWhitelist` (public-IP whitelist):** the existing IPVerifier flow (external endpoint learns the current public IP, compared to the trusted list). The owner accepts the external query as the necessary way to learn the public IP. Simplified defaults remain (quorum 1, freezeWhenUnknown false).
- `ProtectionSettings.mode` decodes with a default (`.vpnInterface`) so pre-existing configs without the field still load. `deriveUIStatus` shows `setup` (empty trusted list) only in IP-whitelist mode. The network card shows VPN tunnel status in VPN mode and the IP fields in IP mode. Settings → Protection has a segmented mode picker with per-mode helper text.
- New L10n keys (D22 additive): ui.protection-mode, ui.mode-vpn, ui.mode-ip, ui.mode-vpn-helper, ui.mode-ip-helper, network.vpn, network.vpnConnected, network.vpnDisconnected (165 keys total).

This supersedes the earlier «remove verification entirely» discussion: public-IP matching inherently requires an external query (the computer cannot know its public IP locally), so the hybrid offers a truly query-free VPN-tunnel mode alongside the IP-whitelist mode. Clean universal build green.
