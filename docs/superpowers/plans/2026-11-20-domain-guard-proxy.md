# Domain guard proxy implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Block configured domain suffixes with a loopback HTTP/HTTPS proxy and a reversible system-proxy switch, independent of DNS-over-HTTPS.

**Architecture:** The root helper keeps the exact-host `/etc/hosts` fallback, runs a loopback HTTP proxy that refuses `CONNECT`/absolute-URI requests for blocked suffixes, and points the system web/secure proxy at it only while the IP is not proven trusted. A persisted manifest restores the previous proxy state on release, crash restart, or uninstall.

**Tech Stack:** Swift 5.9 language mode, macOS 13+, Network.framework or BSD sockets, `/usr/sbin/networksetup`, XcodeGen, ad-hoc signing.

**Spec:** `docs/superpowers/specs/2026-11-20-domain-guard-proxy-design.md`

## Global Constraints

- `AGENTS.md`: no test target, no `scripts/test.sh`, no TDD workflow. Verify with throwaway standalone harnesses and the manual matrix.
- Universal Release build via `./scripts/build.sh`; `arm64` and `x86_64`.
- Ad-hoc signing; Hardened Runtime; App Sandbox off; helper runs as root from launchd.
- The helper reads only the user-owned `domain-guard.json` with lstat checks; privileged paths come from the root-owned `guard.plist`.
- English code and docs; UI copy from `design/copy.json`, regenerated with `scripts/gen-strings.py`.
- Commits: one conventional line, 30–50 characters, lowercase present-tense verb.
- Do not run the active daemon path in a harness: it changes the system proxy. Use `--dry-run` or an injected command runner.
- The engine semantics, `www.` normalization, suffix matching, and hosts fallback are already implemented and stay.

## Review Focus

1. A service with an unreadable proxy state — leave it untouched, report degraded, never overwrite an unsaved value.
2. A release after a crash — the manifest is restored before anything else, and the exact enabled/server/port state returns.
3. A blocked `CONNECT` and a blocked absolute-form HTTP request — both answer 403 and close; allowed requests tunnel byte-for-byte.
4. Malformed, oversized, or slow requests — dropped without killing the listener.
5. A new service appearing while active — captured and persisted before it is switched; VPN/PPP/utun services are never touched.

---

### Task 1: Shared status and proxy-restore models

**Files:**
- Modify: `NoHalla/Core/Guard/DomainGuardStatus.swift`
- Harness: throwaway `/tmp/h1/main.swift`

**Interfaces:**
- `enum DomainGuardProxyMode: String, Codable { case active, unavailable, degraded }`
- `struct DomainGuardStatus: Codable, Equatable { var protocolVersion: Int; var proxyMode: DomainGuardProxyMode; var proxySwitched: Bool; var reason: String; var updatedAt: Date }`
- `struct ProxyRestoreManifest: Codable, Equatable { struct Service: Codable, Equatable { var name: String; var webEnabled: Bool; var webServer: String; var webPort: Int; var secureEnabled: Bool; var secureServer: String; var securePort: Int }; var schemaVersion: Int; var services: [Service] }`
- `enum DomainGuardProtocol { static let version = 4; static let statusURL: URL; static let manifestURL: URL }` (`guard-status.json`, `proxy-restore.json`).

- [ ] **Step 1:** Harness round-trips both types and asserts `version == 4`.
- [ ] **Step 2:** Run it; expect a missing-type error.
- [ ] **Step 3:** Implement the types; no I/O.
- [ ] **Step 4:** Run the harness; expect `ok`.
- [ ] **Step 5:** Commit `feat(guard): add proxy status models`.

---

### Task 2: Loopback HTTP/HTTPS proxy

**Files:**
- Create: `NoHallaDomainGuard/HTTPProxy.swift`
- Harness: `/tmp/h2/main.swift` + Python client/echo server
- Delete after Task 5: `DNSMessage.swift`, `DNSProxy.swift`

**Interfaces:**
- `final class HTTPProxy { init(port: UInt16, suffixes: [String]); func start() throws; func update(suffixes: [String]); func stop() }`

- [ ] **Step 1:** Harness on port 18844 with `suffixes: ["youtube.com"]`: blocked `CONNECT m.youtube.com:443` → 403; allowed `CONNECT example.com:PORT` tunnels to a local echo server; blocked absolute HTTP → 403; allowed absolute HTTP reaches a local HTTP server with an origin-form request line; malformed request dropped; listener still answers.
- [ ] **Step 2:** Compile/run; expect missing `HTTPProxy`.
- [ ] **Step 3:** Implement: bind loopback, read headers up to 64 KB, parse `CONNECT` and absolute-form, `DomainBlocklist.isBlocked`, 403 response, connect + relay, 10 s connect/5 min idle, no caching.
- [ ] **Step 4:** Re-run the harness; expect PASS.
- [ ] **Step 5:** Commit `feat(guard): add loopback HTTP proxy`.

---

### Task 3: System proxy capture, switch, and restore

**Files:**
- Create: `NoHallaDomainGuard/SystemProxy.swift`
- Harness: `/tmp/h3/main.swift`

**Interfaces:**
- Reuse `CommandRunning`, `ProcessRunner`, `NetworkServiceInfo`, `SystemEnvironment.services()` from the current `SystemDNS.swift` (move them here).
- `enum ProxyApplyResult: Equatable { case applied; case unavailable(String); case degraded(String) }`
- `final class SystemProxyManager { init(runner: CommandRunning, services: [NetworkServiceInfo], manifestURL: URL, dryRun: Bool); func captureAndSwitch(port: UInt16) -> ProxyApplyResult; func reconcile(port: UInt16) -> ProxyApplyResult; func restore() -> Bool; var isActive: Bool }`

- [ ] **Step 1:** Fake runner: `-getwebproxy Wi-Fi` → `Enabled: No\nServer: \nPort: 0\n`; `-getsecurewebproxy Wi-Fi` → `Enabled: Yes\nServer: corporate\nPort: 3128\n`; `-getwebproxy Office VPN` never called. Assert capture, set both to `127.0.0.1:18844`, restore `web off` and `secure corporate:3128`, VPN untouched, unreadable service → degraded.
- [ ] **Step 2:** Run; expect missing `SystemProxyManager`.
- [ ] **Step 3:** Implement command parsing, manifest persistence before the first set, exact restore, new-service capture, loopback refusal (never save `127.0.0.1` as an original), dry-run logging.
- [ ] **Step 4:** Run; expect `ok`.
- [ ] **Step 5:** Commit `feat(guard): switch and restore system proxy`.

---

### Task 4: Helper orchestration

**Files:**
- Modify: `NoHallaDomainGuard/GuardRunner.swift`
- Modify: `NoHallaDomainGuard/main.swift`
- Harness: temp plist + `--once --dry-run --port 18844`

**Interfaces:**
- `GuardRunner` consumes `HTTPProxy`, `SystemProxyManager`, `SystemEnvironment`.
- CLI: `--version` prints `domainGuardProtocol=4`; `--restore` restores the manifest; `--once`; `--dry-run`; hidden `--port`.

- [ ] **Step 1:** Replace the DNS members with the proxy manager/proxy; startup restores a stale manifest first.
- [ ] **Step 2:** Active: write hosts, start the proxy, capture/switch the system proxy, publish `proxyMode`. Inactive: restore, remove hosts, publish unavailable.
- [ ] **Step 3:** On proxy bind failure: hosts only, `unavailable`, do not touch the system proxy.
- [ ] **Step 4:** `SIGTERM`: restore proxy, remove hosts, exit.
- [ ] **Step 5:** Dry-run harness: pre-existing manifest → restore line before switch; hosts marked; status `proxyMode:active`; no `networksetup` change.
- [ ] **Step 6:** Commit `feat(guard): orchestrate HTTP proxy and restore`.

---

### Task 5: Remove the DNS mechanism and rebuild the app

**Files:**
- Delete: `NoHallaDomainGuard/DNSMessage.swift`, `DNSProxy.swift`, `SystemDNS.swift`
- Modify: `NoHalla/UI/Settings/DomainGuardInstaller.swift` (status field names)
- Modify: `NoHalla/UI/Settings/SettingsProtectionView.swift`
- Modify: copy and README
- Harness: none

- [ ] **Step 1:** Delete the DNS files and any `NSDNS`/upstream references; keep `CommandRunning`, `ProcessRunner`, `NetworkServiceInfo`, `SystemEnvironment.services()` in `SystemProxy.swift`.
- [ ] **Step 2:** Update the app to `DomainGuardProxyMode`/`proxySwitched`; the warning reads `proxyMode` and reason; protocol 4 shows Reinstall for older helpers.
- [ ] **Step 3:** Copy: one entry = domain + subdomains; the system proxy covers browsers that honor it; apps ignoring it bypass; already-open connections persist. README: proxy mechanism, restore guarantees, Happ DoH is irrelevant for proxied apps, one-time reinstall.
- [ ] **Step 4:** `python3 scripts/gen-strings.py && ./scripts/build.sh`; expect `BUILD SUCCEEDED`, universal, helper answers 4.
- [ ] **Step 5:** Commit `refactor(guard): replace DNS with HTTP proxy`.

---

### Task 6: Uninstall restores the proxy

**Files:**
- Modify: `NoHalla/Resources/uninstall-domain-guard.sh`

- [ ] **Step 1:** Bootout, run `"$HELPER" --restore`; fallback: parse `proxy-restore.json` with `plutil` and call `networksetup -setwebproxy`/`-setsecurewebproxy` or the `-state off` commands; on parse failure, print the manifest path and exit before deleting.
- [ ] **Step 2:** Remove helper, plist, `guard.plist`, both JSON files, hosts section.
- [ ] **Step 3:** `bash -n`; commit `fix(guard): restore proxy on uninstall`.

---

### Task 7: Universal build and live matrix with Happ

**Files:** README result only.

- [ ] **Step 1:** `./scripts/build.sh`; `lipo -info`; bundled helper `--version` = 4.
- [ ] **Step 2:** Owner runs the installer once (protocol 3 → 4).
- [ ] **Step 3:** With Happ connected:
  1. Trusted IP: no hosts markers, `scutil --proxy` unchanged, sites load.
  2. Untrusted: hosts markers, `scutil --proxy` shows `127.0.0.1:8844` for web and secure, `m.youtube.com`/random `*.youtube.com` fail in Vivaldi, `google.com` loads.
  3. Trusted again, pause, off, quit: exact proxy state restored; no `127.0.0.1` left.
  4. `kill -9` helper (owner/admin): launchd restart re-applies.
  5. Uninstall: proxy restored, hosts clean.
- [ ] **Step 4:** Record results in README/PR; commit docs.

## Own calls

- Loopback proxy default port 8844; hidden `--port` for harnesses.
- System proxy applies to hardware services only; VPN/PPP/utun skipped.
- Hosts fallback stays.
- A dead proxy fails closed for proxied apps; non-proxy apps keep working.
- Uninstaller uses `plutil` if the helper is already gone.