# No-halla

*Valhalla can wait.*

No-halla is a free, open-source macOS menu bar agent that **pauses selected apps when your public IP leaves a trusted realm** and resumes them when a trusted IP returns. It is built for the moment your VPN drops: instead of letting apps quietly talk over an untrusted connection, No-halla puts them on hold (`SIGSTOP`) until your VPN is back.

## What it is — and what it is not

No-halla pauses **user-space execution** of the apps you choose. It is **not a network firewall and not a system kill switch**.

> **`SIGSTOP` ≠ firewall.** While an app is paused, macOS can still send buffered data or finish already-established connections. No-halla does not promise "zero leak". It is a UX-level pause of selected apps, not a packet filter. It does not block the whole network, touch system processes, or protect processes owned by other users or root. The optional **Blocked sites** guard blocks *hostname resolution* from a user list while the IP is untrusted — still not a packet filter: DNS-over-HTTPS, IP literals and already-resolved connections bypass it.

### Terminal agents (Claude Code, Codex)

Each protected app has a **Freeze** choice: **App** (v1 behaviour — the app's own processes, helpers and XPC services) or **Agent terminals**. The second keeps the app running and stops only the terminal sessions that host a supported CLI agent. No-halla walks the app's process tree, finds an agent attached to a controlling terminal, and freezes the shell session hosting it (`host → login → zsh → agent`) together with the agent's tool calls. That tab becomes inert; the app window, other tabs, builds, ssh and dev servers keep running.

Supported CLIs (`AgentDetector.catalog`): Claude Code (`claude`), OpenAI Codex CLI (`codex`), Google Antigravity CLI (`agy`) and the legacy Gemini CLI (`gemini`), xAI Grok Build (`grok`), GitHub Copilot CLI (`copilot`), Cursor CLI (`cursor-agent`), Factory Droid (`droid`), Amp (`amp`), Kiro CLI (`kiro-cli`), plus the model-agnostic Aider, OpenCode, Crush, Goose and OpenHands.

Why this list: the first group is US vendors that restrict Russia and China, and a CLI inherits its vendor's block — exactly the case where an agent must not keep running on a local IP. As of November 2026: ChatGPT/Codex is unavailable in Russia, mainland China, Belarus, Cuba, Iran, North Korea, Syria and Venezuela (plus Hong Kong and Macau); Claude is unavailable in Russia and mainland China under [Anthropic's supported-regions policy](https://www.anthropic.com/legal/supported-regions); Gemini is unavailable in Russia, Belarus, Iran, Syria, Cuba, North Korea and Afghanistan, with mainland China Workspace-only for personal accounts; Grok is missing from the China and Russia App Stores; [GitHub does not sell or export Copilot to Russia or Belarus](https://docs.github.com/en/site-policy/other-site-policies/github-and-trade-controls); Cursor is reported blocked in Russia. Sources also include the October 2026 availability audits at whizi.io and [x.ai/cli](https://x.ai/cli).

Detection does not rely on the executable name alone: Node-based installs report `node`, so argv is read through `KERN_PROCARGS2`, and a controlling tty is required — Codex's `app-server daemon` and other background helpers are therefore ignored. Agent sessions started while the IP is already untrusted are picked up by the 5 s reconcile pass.

Limits: a frozen client cannot cancel work the server already started — an in-flight model request keeps generating on the provider's side, is billed, and its response is buffered in the kernel socket until `SIGCONT`; `SIGSTOP` prevents the **next** request and the **next** tool call. Agents inside `tmux`/`screen` are not detected, because their process tree hangs off the multiplexer, not the tab's shell.

### Blocked sites (optional domain guard)

Settings → Protection → **Blocked sites** holds a list of hostnames (exact names; `www.` is added automatically). Hostnames can be typed in, imported from a shared package, or dropped as a `.txt`/`.json` list onto the section — the same drop target exists on the onboarding step, invalid entries are skipped, and the result is reported inline. While protection is active and the IP is **not** proven trusted (`checking`, `grace`, `frozen`, `unknown`), No-halla publishes that list and a root LaunchDaemon rewrites the marked section of `/etc/hosts` to `0.0.0.0`/`::1`. When a trusted IP is verified, or Protection is off/paused, the section is removed. A graceful quit releases the block; a crash leaves it in place until the next launch (fail-closed).

The app itself stays unprivileged. Install the helper once:

```bash
sudo bash "/Applications/No-halla.app/Contents/Resources/install-domain-guard.sh"
```

When the helper is missing, Settings → Protection and the onboarding Blocked sites step show **Install…** (runs the bundled script through the system admin prompt) and **Copy command**; after installation they report that the helper is installed. Settings also offers **Uninstall…**, which runs the bundled uninstaller and strips the hosts section; onboarding never removes the helper.

The script copies `NoHallaDomainGuard` to `/usr/local/libexec`, writes `/Library/Application Support/NoHalla/guard.plist` and `/Library/LaunchDaemons/dev.nohalla.NoHallaDomainGuard.plist`, and bootstraps it. `uninstall-domain-guard.sh` removes the daemon, the helper and the hosts section. Only the console user is supported; re-run the installer after moving the app or rebuilding so the helper is refreshed.

Limits: `/etc/hosts` is consulted by the system resolver, so apps that resolve over DNS-over-HTTPS (browsers with secure DNS enabled) or connect to IP literals bypass the block. It is a name-resolution guard, not a packet filter: it cannot inspect SNI, cannot block per app, and does not affect already-resolved connections.

**Shared packages.** A list can be sent to another person as a JSON package: **Import package…** validates the file and shows a preview (name, note, author, how many domains are new versus already blocked) before adding it as a toggleable package; a package can be disabled without deleting it. Drag a package row onto Finder or a chat window to share it, or drop a `.json` file onto the packages section to import — both paths use the same validation and preview. The share button on a package row and **Export list…** for manual entries write the same format:

```json
{
  "schemaVersion": 1,
  "name": "AI services",
  "note": "Blocked in RU/CN",
  "author": "someone",
  "domains": ["chatgpt.com", "claude.ai"]
}
```

Import is treated as untrusted: 1 MB cap, schema check, at most 32 packages and 256 domains each, and every hostname is re-normalized by the app and again by the root helper. A package can only add hosts entries — it carries no executable content and no paths.

Out of scope (v1): VPN client, `pf`/Network Extension/kext kill switch, packet-level filtering, whole-network blocking, Windows/Linux, accounts/cloud/telemetry/auto-update, App Store/sandbox. The hosts-based domain guard above is a name-resolution block, not a packet filter.

## Requirements

- macOS 13.0 or later (Apple Silicon and Intel).
- To build: Xcode (15+, tested with 27.2) and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).
- Runs as the current user; **no root required**. App Sandbox is off; Hardened Runtime is on; builds are ad-hoc signed. The optional domain guard needs one `sudo` install of its LaunchDaemon.

## Build and run

```bash
./scripts/build.sh   # xcodegen generate + xcodebuild Release (universal arm64+x86_64, ad-hoc)
./scripts/run.sh     # open build/Build/Products/Release/No-halla.app
./scripts/package.sh # build + dist/No-halla-<version>.dmg and .zip (with SHA-256)
```

The watchdog binary is embedded at `No-halla.app/Contents/MacOS/NoHallaWatchdog`.

To repeat the first-run experience, build the current version and run:

```bash
./scripts/reset-app.py            # stop, clear user data, and reopen onboarding
./scripts/reset-app.py --dry-run  # preview without changing anything
```

The reset disables launch at login and clears No-halla's configuration, recovery state, preferences, caches and saved window state. It waits for the app and watchdog to stop and refuses to remove a recovery state that still lists frozen processes. The lock file is kept. The optional system domain guard remains installed, and macOS notification permission is not reset.

> **First launch is manual.** This project was implemented without automated tests by owner decision. Run the manual matrix below on a real machine before relying on it. The build is verified statically (compiler typecheck + structural checks); runtime behavior is validated by you.

## How it works

1. On first launch, a four-step onboarding lets you choose how trust is decided (IP whitelist or VPN tunnel), pick apps and what each freezes (the app itself or only the agent terminal sessions it hosts), trust your VPN's IP (or skip it in VPN mode), optionally add blocked hostnames (typed or dropped as a list), and enable launch at login.
2. No-halla watches the network (`NWPathMonitor`, `SCDynamicStore`, wake) and periodically learns your public IPv4 through configurable HTTPS endpoints (default: `https://ipinfo.io/ip`). IPv6 is not checked (owner decision). On split-tunnel hosts several endpoints may see different public addresses; every observed address is checked against your trusted list — so every configured endpoint must route through your VPN tunnel, otherwise its answer leaks the real IP and freezes the apps. The refresh icon in the network card forces an immediate check; a spinner is shown while it is pending, even if the resulting IP and status do not change.
3. If all observed IPs are trusted → **Protected**. If any observed IP is not trusted → a configurable **grace** countdown (factory default 1 s) → **Frozen**. Per app, *Freeze* is either **App** (`SIGSTOP` to the app's processes, helpers and children inside its `.app` bundle) or **Agent terminals** (the app keeps running; only terminal sessions hosting Claude Code/Codex are stopped). If no IP can be verified → **Unknown** (freezes after grace when *Freeze when unknown* is on). Editing the trusted list (add, remove, or *Add current IP*) restarts protection immediately: countdowns and manual-resume bypass windows are dropped and a fresh check runs, while a frozen set stays frozen until the verdict. The master Protection switch lives on the dashboard.
4. When a trusted IP returns → apps resume (`SIGCONT`). Manual **Resume all** opens a bypass window; **Pause** suspends protection for 15 min / 1 hour / until relaunch.
5. Safety: every signal verifies the process id **and start time** (PID-reuse guard); a deny-list (self, watchdog, PID 1, system processes, other users' processes) and a strict `.app` path-prefix are enforced before each signal. Agent-terminal targets are the exception to the path rule: they are authorized by a live process-tree edge from a process inside the bundle, and still pass the deny-list and identity checks.
6. Reliability: a `kqueue` watchdog resumes frozen apps within ~2 s if No-halla crashes; startup recovers stale frozen records; quit / `SIGTERM` / `SIGINT` resume everything and clear state.

Config and state live in `~/Library/Application Support/NoHalla/` (`config.json`, `state.json`, atomic writes).

## Appearance and freeze behavior

No-halla opens a **main window** (like a regular app) on launch and from the Dock: it shows onboarding first, then the protection dashboard (status, network, protected apps, actions) with a Settings button. A shield also stays in the menu bar for quick popover access. Clicking the Dock icon shows the main window. When an app is frozen, its windows are **minimized to the Dock** so it does not sit on screen looking hung, and restored when resumed.

Minimizing another app's windows needs **Accessibility permission**: on the first freeze macOS prompts you to grant it (System Settings → Privacy & Security → Accessibility → enable No-halla). Without it, No-halla falls back to hiding the app instead of minimizing. You can still use the app fully without this permission.

A note on the freeze principle: an app can freeze even when your current IP is trusted, if the IP cannot be *verified* (no endpoint answered → `unknown`) and *Freeze when unknown* is on. The trusted IP must be successfully observed to stay Protected; you can turn off *Freeze when unknown* in Settings → Protection if you prefer. Endpoints disagreeing with each other is not an error: on a split-tunnel host they may legitimately see different egress addresses, and every one of them must be in the trusted list.

## Crash recovery and its limitation

No-halla records each process it intends to freeze **before** sending `SIGSTOP`, so a crash cannot leave a stopped app unrecorded. If No-halla crashes, the embedded watchdog resumes the recorded apps within ~2 s; the next launch also recovers any stale records. Both paths verify the process id **and start time** before sending `SIGCONT`, so a reused pid is never signaled (D29, FR-41/42).

**Ownership limitation (accepted).** The record proves *which* process was frozen, not *who* paused it. In a narrow window — No-halla wrote the record but crashed before issuing `SIGSTOP`, and another agent (for example a debugger) independently paused the same process inside a protected app bundle — recovery may resume a pause No-halla did not create. This residual risk is accepted by design (full recovery is prioritized). It is narrowed by the safety rules (only processes owned by you that live inside a selected `.app` or descend from a process inside it, not system/deny-listed). **Recommendation:** avoid using debuggers or other third-party pauses on protected apps while No-halla is active.

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
| 13 | Endpoint bypassing the tunnel (split-tunnel DIRECT rule) | Its answer is untrusted → grace → freeze | ☐ |
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
- **Apps freeze on a trusted network.** One of the public addresses observed by the endpoints may not be in the trusted list — with domain-routed split tunneling, an endpoint whose domain matches a DIRECT rule (commonly `api.ipify.org`, `ifconfig.me`) sees your real IP instead of the VPN's. Use an endpoint that routes through the tunnel (the default `https://ipinfo.io/ip` does on typical rule sets), or fix the VPN client's rules so all IP-check domains go through the tunnel. **Add current IP** trusts every observed address, but trusting a dynamic real IP is fragile.
- **IP check services blocked (e.g. regional).** Replace the endpoint in Settings → Advanced with your own HTTPS URL that returns a plain-text IP or JSON `{"ip": ...}` — and make sure its domain routes through your VPN tunnel.
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
