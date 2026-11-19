# Release verification

Run the following scenarios on a release candidate and record the results in the release PR. All entries below are pending. For the IP scenarios, select **IP whitelist** and add the VPN exit address first.

| # | Try this | Expected result | Checked |
| --- | --- | --- | --- |
| 1 | Connect with a trusted IP | Protected, apps active | ☐ |
| 2 | Disconnect so the IP changes | Grace, then Frozen. The process state includes `T` | ☐ |
| 3 | Restore the trusted connection | Apps resume | ☐ |
| 4 | Launch another protected app while frozen | The new instance freezes within 2 s | ☐ |
| 5 | Quit while frozen | Confirmation, then apps resume | ☐ |
| 6 | Force-quit No-halla with SIGKILL while frozen | Watchdog resumes apps. Separately verify startup recovery with stale state | ☐ |
| 7 | Sleep and wake on a trusted network | Fresh check after wake | ☐ |
| 8 | Switch from Wi-Fi to Ethernet with the same trusted IP | Apps keep running | ☐ |
| 9 | Make all endpoints unreachable while apps are running | Unknown. Apps keep running by default, or freeze after grace if configured | ☐ |
| 10 | Add the current IP while frozen | Apps resume when all observed addresses are trusted | ☐ |
| 11 | Exercise the one-hour pause | Freeze suspended until expiry. Engine scenario, currently no dashboard control | ☐ |
| 12 | Select Resume all in the freeze notification on an untrusted IP | Five-minute bypass by default, then recheck | ☐ |
| 13 | Route one configured endpoint outside the VPN | An untrusted answer triggers grace, then freeze | ☐ |
| 14 | Run app protection as a standard user | Freeze and resume work | ☐ |
| 15 | Freeze Claude or Cursor with bundled helpers | Eligible helpers also show `T` | ☐ |
| 16 | Remove a frozen app from protection | Its processes resume | ☐ |
| 17 | Launch with a malformed config in a disposable profile | Defaults load and a banner appears | ☐ |
| 18 | Open About | Name, tagline, version and MIT license appear | ☐ |
| 19 | Check menu bar icons in light and dark mode | Five status glyphs are distinguishable | ☐ |
| 20 | Switch between English and Russian | Controls and status text fit in both languages | ☐ |

For keyboard, VoiceOver and display settings, see the [accessibility checklist](../design/ACCESSIBILITY.md).

## Site blocker verification history

**Recorded manual check, 20 November 2026.** With Happ connected and the IP trusted, Vivaldi loaded YouTube. On an untrusted IP, the system proxy switched to loopback, `m.youtube.com` was blocked and `google.com` loaded. Restoring trust removed the hosts entries and restored the proxy settings. Pause/off, helper restart, network changes while blocking and uninstall were outside that check.
