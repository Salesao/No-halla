# No-halla

*Valhalla can wait.*

No-halla is a free, open-source macOS menu bar agent that **pauses selected apps when your public IP leaves a trusted realm** and resumes them when a trusted IP returns. It is built for the moment your VPN drops: instead of letting apps quietly talk over an untrusted connection, No-halla puts them on hold (`SIGSTOP`) until your VPN is back.

## What it is — and what it is not

No-halla pauses **user-space execution** of the apps you choose. It is **not a network firewall and not a system kill switch**.

> **`SIGSTOP` ≠ firewall.** While an app is paused, macOS can still send buffered data or finish already-established connections. No-halla does not promise "zero leak". It is a UX-level pause of selected apps, not a packet filter. It does not block the whole network, touch system processes, or protect processes owned by other users or root.

Out of scope (v1): VPN client, `pf`/Network Extension/kext kill switch, whole-network blocking, Windows/Linux, accounts/cloud/telemetry/auto-update, App Store/sandbox.

## Requirements

- macOS 13.0 or later (Apple Silicon and Intel).
- To build: Xcode (15+, tested with 27.2) and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).
- Runs as the current user; **no root required**. App Sandbox is off; Hardened Runtime is on; builds are ad-hoc signed.

## Build and run

```bash
./scripts/build.sh   # xcodegen generate + xcodebuild Release (universal arm64+x86_64, ad-hoc)
./scripts/run.sh     # open build/Build/Products/Release/No-halla.app
```

The watchdog binary is embedded at `No-halla.app/Contents/MacOS/NoHallaWatchdog`.

> **First launch is manual.** This project was implemented without automated tests by owner decision (see `DECISIONS.md`, D2). Run the manual matrix below on a real machine before relying on it. The build is verified statically (compiler typecheck + structural checks); runtime behavior is validated by you.

## How it works

1. On first launch, a three-step onboarding lets you pick apps, trust your VPN's IP (or a CIDR range), and enable launch at login.
2. No-halla watches the network (`NWPathMonitor`, `SCDynamicStore`, wake) and periodically checks your public IPv4/IPv6 against configurable HTTPS endpoints (quorum per family).
3. If the IP is trusted → **Protected**. If it becomes untrusted → a configurable **grace** countdown → **Frozen** (`SIGSTOP` to the app's processes, helpers and children inside its `.app` bundle). If the IP cannot be verified → **Unknown** (freezes after grace when *Freeze when unknown* is on).
4. When a trusted IP returns → apps resume (`SIGCONT`). Manual **Resume all** opens a bypass window; **Pause** suspends protection for 15 min / 1 hour / until relaunch.
5. Safety: every signal verifies the process id **and start time** (PID-reuse guard); a deny-list (self, watchdog, PID 1, system processes, other users' processes) and a strict `.app` path-prefix are enforced before each signal.
6. Reliability: a `kqueue` watchdog resumes frozen apps within ~2 s if No-halla crashes; startup recovers stale frozen records; quit / `SIGTERM` / `SIGINT` resume everything and clear state.

Config and state live in `~/Library/Application Support/NoHalla/` (`config.json`, `state.json`, atomic writes).

## Appearance and freeze behavior

No-halla shows a shield in the menu bar and (by owner preference) an icon in the Dock; clicking the Dock icon opens Settings. When an app is frozen, its windows are **minimized to the Dock** so it does not sit on screen looking hung, and restored when resumed.

Minimizing another app's windows needs **Accessibility permission**: on the first freeze macOS prompts you to grant it (System Settings → Privacy & Security → Accessibility → enable No-halla). Without it, No-halla falls back to hiding the app instead of minimizing. You can still use the app fully without this permission.

A note on the freeze principle: an app can freeze even when your current IP is trusted, if the IP cannot be *verified* (the check endpoints did not reach quorum → `unknown`) and *Freeze when unknown* is on (default). The trusted IP must be successfully verified to stay Protected; you can turn off *Freeze when unknown* in Settings → Protection if you prefer.

## Crash recovery and its limitation

No-halla records each process it intends to freeze **before** sending `SIGSTOP`, so a crash cannot leave a stopped app unrecorded. If No-halla crashes, the embedded watchdog resumes the recorded apps within ~2 s; the next launch also recovers any stale records. Both paths verify the process id **and start time** before sending `SIGCONT`, so a reused pid is never signaled (D29, FR-41/42).

**Ownership limitation (accepted).** The record proves *which* process was frozen, not *who* paused it. In a narrow window — No-halla wrote the record but crashed before issuing `SIGSTOP`, and another agent (for example a debugger) independently paused the same process inside a protected app bundle — recovery may resume a pause No-halla did not create. This residual risk is accepted by design (full recovery is prioritized). It is narrowed by the safety rules (only processes inside a selected `.app`, owned by you, not system/deny-listed). **Recommendation:** avoid using debuggers or other third-party pauses on protected apps while No-halla is active. See `DECISIONS.md` (D29).

## Launch at login

Settings → General → *Launch at login* uses `SMAppService.mainApp`. With an ad-hoc signature macOS may refuse registration; the error is shown inline and the toggle is not changed silently.

## Manual verification matrix (run and check off)

| # | Scenario | Expected | ✓ |
|---|---|---|---|
| 1 | VPN on, trusted IP | Protected, apps active | ☐ |
| 2 | Disable VPN, IP changes | Grace → Frozen, `ps` shows `T` | ☐ |
| 3 | Restore VPN | Protected, apps resumed | ☐ |
| 4 | Launch a new instance while Frozen | Frozen within 2 s | ☐ |
| 5 | Quit while frozen | Confirmation, then resume all | ☐ |
| 6 | `kill -9` No-halla while frozen | Watchdog resumes apps | ☐ |
| 7 | Sleep / wake | Check after wake, no false freeze | ☐ |
| 8 | Wi-Fi → Ethernet, same IP | No freeze | ☐ |
| 9 | All endpoints unreachable | Unknown, then freeze after grace (default) | ☐ |
| 10 | Add current IP while frozen | Apps resume | ☐ |
| 11 | Pause 1 hour | No freeze, status shows end time | ☐ |
| 12 | Resume all on a bad IP | Bypass 5 min, then freeze again | ☐ |
| 13 | IPv6 leak (if enabled) | IP treated as untrusted | ☐ |
| 14 | Run without admin | Works without root | ☐ |
| 15 | Cursor/Claude with helpers | Helper processes also `T` | ☐ |
| 16 | Remove an app from the list while frozen | Its process resumes | ☐ |
| 17 | Corrupt the config manually | Defaults, banner, app keeps working | ☐ |
| 18 | About | No-halla, tagline, version, MIT shown | ☐ |
| 19 | Menu bar | 5 states distinguishable, template rendering in light/dark | ☐ |
| 20 | Switch language EN/RU | All strings incl. lore switch without clipping | ☐ |

Also verify accessibility on the live build: VoiceOver labels, keyboard focus order, Increase Contrast / Reduce Transparency / Reduce Motion (see `design/ACCESSIBILITY.md`).

## Troubleshooting

- **An app stays paused after No-halla is gone.** Resume it manually: `kill -CONT <pid>` (find the pid in Activity Monitor; a paused process shows state `T`). The watchdog and startup recovery normally handle this automatically.
- **Apps freeze on a trusted network.** Your IP may not be in the trusted list, or IPv6 is leaking (Settings → Protection → Check IPv6). On IPv6-egress hosts the default dual-stack v4 endpoints may return no IPv4 answer → Unknown → freeze (see `DECISIONS.md`, R29); add a dedicated IPv4 endpoint such as `https://api.ipify.org` in Settings → Advanced, or adjust *Freeze when unknown*.
- **IP check services blocked (e.g. regional).** Add your own HTTPS endpoint that returns a plain-text IP or JSON `{"ip": ...}` in Settings → Advanced.
- **Launch at login won't enable.** Ad-hoc signing may be rejected by `SMAppService`; the inline error explains it. Re-sign with a valid identity if needed.
- **Esc does not close the popover.** `MenuBarExtra(.window)` has limited Esc handling on macOS 13; this is a known accessibility gap (D23). Click the menu bar icon to toggle.

## Privacy

No telemetry, analytics, accounts or auto-update. The only outbound traffic is to the configured HTTPS IP-check endpoints. IP addresses are masked in logs outside debug level (`203.0.113.x`). Diagnostics export (Settings → Advanced) is local and user-initiated; nothing is sent automatically.

## Removal

1. Quit No-halla (it resumes any frozen apps first).
2. Turn off *Launch at login* in Settings → General (or remove the login item in System Settings → General → Login Items).
3. Delete `No-halla.app`.
4. Optionally remove `~/Library/Application Support/NoHalla/`.

## License

MIT — see [LICENSE](LICENSE).