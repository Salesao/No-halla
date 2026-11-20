# No-halla user guide

[Back to No-halla](../README.md) · **English** · [Русский](USER_GUIDE.ru.md)

## Protection settings

| Choose | When to use it | How it works |
| --- | --- | --- |
| **VPN tunnel** | Your VPN can give you a different exit IP each time. | Regular checks look for a locally active tunnel interface. A tunnel can exist even if an individual destination takes a different route. |
| **IP whitelist** | Work requires a known exit address or IPv4 CIDR range. | Each configured HTTPS endpoint reports the public IPv4 it sees. Every valid answer must match the list. An empty trust list leaves protection in setup. |

No-halla checks on network changes and after wake. Defaults are a **30-second** periodic check, **1-second** grace period and **5-minute** manual bypass. IP checks use `https://ipinfo.io/ip` by default. In **Settings → Advanced**, you can add an HTTPS endpoint that returns plain-text IPv4 or JSON such as `{"ip":"203.0.113.5"}`. The public-IP check covers IPv4 only.

If all endpoints are unreachable, running apps keep running by default. Enable **Freeze when IP can’t be verified** in Protection settings to freeze them after grace. Already-frozen apps wait for a trusted result or a manual resume.

During grace, **Cancel** requests another check. Frozen apps resume automatically when trust returns. To run them temporarily on an untrusted connection, select **Resume all** in the freeze notification. **Resume protection** ends that period early. Switching **Protection** off releases the processes until you turn it on again. **Settings → General** controls launch at login, notifications and the English/Russian interface.

**Sleep and wake.** No-halla never freezes apps while the Mac sleeps, and never resumes them mid-sleep on a stale verdict — frozen apps stay frozen until the first check after wake. After wake it checks immediately; a grace countdown from before sleep is restarted only if the fresh check still finds the connection untrusted. In **VPN tunnel** mode a reconnecting VPN gets a few seconds after wake before a missing tunnel can freeze apps. A timed pause (15 minutes or 1 hour) runs on the wall clock: time asleep counts against it, and a pause that expired during sleep ends right after wake. **Until relaunch** pauses are unaffected. If the wake notification is ever missed, No-halla recovers on the next display wake, session unlock, or any action you take in the app; a hard 12-hour limit forces recovery and is logged as an error.

## Terminal agents

During first-run setup, choose **Agent terminals** for each app where you run an agent, such as Orca and macOS Terminal. Open Terminal before the app-selection step to find it under running apps. No-halla finds supported agents attached to a terminal and pauses the hosting shell session and its children, including running tool calls. The host window and tabs without agents stay usable. While protection is in the Frozen state, No-halla scans for new agent sessions every five seconds.

Recognized CLIs include Claude Code, Codex, Antigravity, Gemini, Grok Build, GitHub Copilot, Cursor, Factory Droid, Amp, Kiro, Aider, OpenCode, Crush, Goose and OpenHands. Detached agents and sessions inside `tmux` or `screen` fall outside this detection. [Agent catalog](../NoHalla/Core/Process/AgentDetector.swift)

## Recovery and privacy

Before sending `SIGSTOP`, No-halla records the process identity. It checks ownership, bundle membership (or ancestry for agent sessions), PID and start time. System processes, No-halla and its watchdog are excluded. On quit, SIGTERM or SIGINT, No-halla resumes frozen processes with `SIGCONT`. An embedded watchdog handles crashes, and the next launch checks for stale records. If a debugger independently stopped the same process between recording and freezing it, recovery may also release the debugger’s pause.

Configuration and recovery state are written atomically under `~/Library/Application Support/NoHalla/`. No-halla has no accounts or telemetry. Public-IP lookups contact the configured HTTPS endpoints, including the address lookup on the onboarding trust screen. IPs are masked at normal log levels. **Settings → Advanced → Export diagnostics** writes a local archive containing configuration, state and available recent logs. The archive can include trusted addresses.

## Troubleshooting

| Symptom | What to do |
| --- | --- |
| Apps freeze with the VPN connected | In IP mode, check how your VPN routes each endpoint. A split tunnel can expose your home address to one endpoint. **Add current IP** trusts every address observed in the last check, so verify the route first. |
| An app stays stopped after a crash | Reopen No-halla to run startup recovery. If it is still stopped, identify its PID in Activity Monitor and run `kill -CONT <pid>` for that process. |
| Frozen windows hide instead of minimizing | Enable No-halla in **System Settings → Privacy & Security → Accessibility**. macOS may require a fresh grant after an ad-hoc rebuild. |
| Launch at login fails | Check the inline error in General settings. macOS may reject registration for an ad-hoc signed app. |
| Esc leaves the popover open on macOS 13 | Click the menu bar icon again. |

## Build from source

On macOS with Xcode 15 or later, install XcodeGen and run the build from the repository root.

```bash
brew install xcodegen
./scripts/build.sh
./scripts/run.sh
```

The build script generates the Xcode project from `project.yml` and builds the **NoHalla** scheme for arm64 and x86_64. The resulting `build/Build/Products/Release/No-halla.app` uses ad-hoc signing and Hardened Runtime. The watchdog is embedded at `Contents/MacOS/NoHallaWatchdog`.

To create a DMG, ZIP and checksum file in `dist/`, run `./scripts/package.sh` from a graphical Finder session with Finder automation permission. To repeat onboarding, preview the reset with `./scripts/reset-app.py --dry-run`. Running it without the flag clears your No-halla user data and reopens the app.

## Removal

1. Turn off **Launch at login** in General settings.
2. Quit No-halla so frozen apps resume, then delete **No-halla.app** from Applications.
3. If you also want to delete preferences and recovery files stored in Application Support, remove `~/Library/Application Support/NoHalla/`.
