# Domain guard suffix blocking implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Block each configured domain and all of its subdomains only while No-halla cannot prove a trusted IP, with a loopback DNS proxy and a reversible system DNS switch.

**Architecture:** The root guard daemon stays the only privileged component. It keeps the exact-host `hosts` section as a fallback, answers `NXDOMAIN` for blocked suffixes from a loopback proxy, forwards everything else to the network's real resolvers, and points enabled hardware services at itself only while the block is active. A persisted manifest restores every service on release, crash restart, or uninstall.

**Tech Stack:** Swift 5.9 language mode, macOS 13+, SystemConfiguration, Network.framework or BSD sockets, `/usr/sbin/networksetup`, XcodeGen, ad-hoc signing.

**Spec:** `docs/superpowers/specs/2026-11-19-domain-guard-suffix-design.md`

## Global Constraints

- `AGENTS.md`: no test target, no `scripts/test.sh`, no TDD workflow. Verify with throwaway standalone harnesses and the 20-scenario manual matrix; record release results in the README or PR.
- Universal Release build via `./scripts/build.sh`; `arm64` and `x86_64`.
- Ad-hoc signing; Hardened Runtime on; App Sandbox off; helper runs as root from launchd.
- The helper reads only the user-owned `domain-guard.json` with lstat checks; privileged paths come from the root-owned `guard.plist`.
- English code and docs; UI copy comes from `design/copy.json` and is regenerated with `scripts/gen-strings.py`.
- Commits follow `docs/commit.md`: one conventional line, 30–50 characters, lowercase present-tense verb.
- Do not run the daemon's active path in a harness: it changes system DNS. Use `--dry-run` or injected command runners.

## Review Focus

1. A service already pointing at loopback, or a saved upstream equal to loopback — the proxy must never forward to itself; the guard stays exact-host only.
2. Network change or VPN reconnect while blocked — the new service is captured before it is switched, and release restores it.
3. Helper restart with loopback still in system settings — restore the manifest before re-applying the block.
4. A malformed, truncated, or oversized DNS packet, and TCP framing — drop it; the daemon must not crash.
5. A service whose current DNS cannot be read — leave it untouched, report degraded, never overwrite an unsaved value.

---

### Task 1: Suffix rules and `www.` normalization

**Files:**
- Modify: `NoHalla/Core/Guard/DomainBlocklist.swift`
- Harness: throwaway `/tmp/domain-rules.swift` (not committed)

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `static func normalize(_ raw: String) -> String?` — now strips a leading `www.` when the remainder is a valid name with at least two labels.
  - `static func normalized(_ raw: [String]) -> [String]` — unchanged signature, uses the new normalization.
  - `static func hostnames(for domains: [String]) -> [String]` — domain plus its `www.` counterpart.
  - `static func isBlocked(host: String, suffixes: [String]) -> Bool` — true when `host` equals a suffix or ends with `.` plus a suffix.

- [ ] **Step 1: Write the failing harness**

```swift
import Foundation
var failures = 0
func check(_ got: String?, _ want: String?, _ label: String) {
    if got != want { print("FAIL \(label): \(String(describing: got)) != \(String(describing: want))"); failures += 1 }
}
check(DomainBlocklist.normalize("https://www.youtube.com/watch"), "youtube.com", "www apex")
check(DomainBlocklist.normalize("www.com"), "www.com", "www.com stays")
check(DomainBlocklist.normalize("mail.example.com"), "mail.example.com", "subdomain stays")
check(DomainBlocklist.normalized(["https://www.youtube.com", "youtube.com"]).description,
      ["youtube.com"].description, "dedupe after strip")
check(DomainBlocklist.hostnames(for: ["youtube.com"]).description,
      ["youtube.com", "www.youtube.com"].description, "hosts pair")
precondition(DomainBlocklist.isBlocked(host: "m.youtube.com", suffixes: ["youtube.com"]))
precondition(DomainBlocklist.isBlocked(host: "youtube.com", suffixes: ["youtube.com"]))
precondition(!DomainBlocklist.isBlocked(host: "notyoutube.com", suffixes: ["youtube.com"]))
precondition(!DomainBlocklist.isBlocked(host: "youtube.com.evil.test", suffixes: ["youtube.com"]))
exit(failures == 0 ? 0 : 1)
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `swiftc -O NoHalla/Core/Guard/DomainBlocklist.swift /tmp/domain-rules.swift -o /tmp/domain-rules && /tmp/domain-rules`
Expected: compile error for the missing `isBlocked` or a FAIL for `www apex`.

- [ ] **Step 3: Implement the rule**

In `normalize`, after the hostname is validated, strip `www.` only when `normalize` of the remainder succeeds (so `www.com` stays). Add `isBlocked` comparing lowercased `host` with `host == suffix || host.hasSuffix("." + suffix)`.

- [ ] **Step 4: Run the harness**

Run: `swiftc -O NoHalla/Core/Guard/DomainBlocklist.swift /tmp/domain-rules.swift -o /tmp/domain-rules && /tmp/domain-rules`
Expected: exit 0, no output.

- [ ] **Step 5: Commit**

```bash
git add NoHalla/Core/Guard/DomainBlocklist.swift
git commit -m "feat(guard): block domain suffixes and normalize www"
```

---

### Task 2: Shared status and restore models

**Files:**
- Create: `NoHalla/Core/Guard/DomainGuardStatus.swift`
- Harness: throwaway `/tmp/guard-models.swift`

**Interfaces:**
- Consumes: Foundation.
- Produces:
  - `enum DomainGuardSuffixMode: String, Codable { case active, unavailable, degraded }`
  - `struct DomainGuardStatus: Codable, Equatable { var protocolVersion: Int; var suffixMode: DomainGuardSuffixMode; var dnsSwitched: Bool; var reason: String; var updatedAt: Date }`
  - `enum DomainGuardProtocol { static let version = 2; static let statusURL: URL; static let manifestURL: URL }`
  - `struct DNSRestoreManifest: Codable, Equatable { struct Service: Codable, Equatable { var name: String; var servers: [String] }; var schemaVersion: Int; var services: [Service]; var upstreams: [String] }`

- [ ] **Step 1: Write the failing harness**

```swift
import Foundation
let status = DomainGuardStatus(protocolVersion: 2, suffixMode: .degraded, dnsSwitched: true, reason: "port busy", updatedAt: Date(timeIntervalSince1970: 0))
let decoded = try! JSONDecoder().decode(DomainGuardStatus.self, from: JSONEncoder().encode(status))
precondition(decoded == status)
let manifest = DNSRestoreManifest(schemaVersion: 1, services: [.init(name: "Wi-Fi", servers: [])], upstreams: ["192.168.1.1"])
precondition(try! JSONDecoder().decode(DNSRestoreManifest.self, from: JSONEncoder().encode(manifest)) == manifest)
precondition(DomainGuardProtocol.version == 2)
print("ok")
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `swiftc -O NoHalla/Core/Guard/DomainGuardStatus.swift /tmp/guard-models.swift -o /tmp/guard-models && /tmp/guard-models`
Expected: compile error, types not found.

- [ ] **Step 3: Implement the models**

Add the types with the exact fields above. `statusURL` is `/Library/Application Support/NoHalla/guard-status.json`; `manifestURL` is `/Library/Application Support/NoHalla/dns-restore.json`. No I/O in this file.

- [ ] **Step 4: Run the harness**

Run: `swiftc -O NoHalla/Core/Guard/DomainGuardStatus.swift /tmp/guard-models.swift -o /tmp/guard-models && /tmp/guard-models`
Expected: `ok`.

- [ ] **Step 5: Commit**

```bash
git add NoHalla/Core/Guard/DomainGuardStatus.swift
git commit -m "feat(guard): add status and restore models"
```

---

### Task 3: DNS message parsing and loopback proxy

**Files:**
- Create: `NoHallaDomainGuard/DNSMessage.swift`
- Create: `NoHallaDomainGuard/DNSProxy.swift`
- Harness: throwaway `/tmp/dns-harness.swift` and `/tmp/fake-upstream.py`

**Interfaces:**
- Consumes: `DomainBlocklist.isBlocked(host:suffixes:)`.
- Produces:
  - `enum DNSMessage { static func questionName(_ packet: Data) -> (name: String, end: Int)?; static func nxdomain(for packet: Data) -> Data?; static func servfail(for packet: Data) -> Data? }`
  - `final class DNSProxy { init(port: UInt16, upstreamPort: UInt16 = 53, suffixes: [String], upstreams: [String]); func start() throws; func update(suffixes: [String], upstreams: [String]); func stop() }`

- [ ] **Step 1: Write the failing message harness**

```swift
import Foundation
var query = Data([0x12,0x34,0x01,0x00,0x00,0x01,0x00,0x00,0x00,0x00,0x00,0x00])
for part in "m.youtube.com".split(separator: ".") { query.append(UInt8(part.utf8.count)); query.append(contentsOf: part.utf8) }
query.append(contentsOf: [0,0,1,0,1])
precondition(DNSMessage.questionName(query)?.name == "m.youtube.com")
let nx = DNSMessage.nxdomain(for: query)!
precondition(nx[3] & 0x0F == 3)
precondition(nx[6] == 0 && nx[7] == 0 && nx[8] == 0 && nx[9] == 0)
precondition(DNSMessage.questionName(Data([0,1,2])) == nil)
print("ok")
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `swiftc -O NoHallaDomainGuard/DNSMessage.swift /tmp/dns-harness.swift -o /tmp/dns-harness && /tmp/dns-harness`
Expected: compile error, type not found.

- [ ] **Step 3: Implement `DNSMessage`**

Parse QDCOUNT=1, read length-prefixed labels, cap the packet at 4096 bytes, reject pointer loops in the question. Build `NXDOMAIN` by copying the question, setting QR=1, RA=1, RCODE=3, and zeroing AN/NS/AR counts. Build `SERVFAIL` the same way with RCODE=2.

- [ ] **Step 4: Run the message harness**

Run: `swiftc -O NoHallaDomainGuard/DNSMessage.swift /tmp/dns-harness.swift -o /tmp/dns-harness && /tmp/dns-harness`
Expected: `ok`.

- [ ] **Step 5: Implement `DNSProxy`**

Bind UDP and TCP on `127.0.0.1:<port>` with Network.framework listeners. On each message: parse the question; if `isBlocked`, send the `NXDOMAIN` answer; else forward the raw bytes to the upstreams in order with a 2 s timeout and return the first response; send `SERVFAIL` when none answers. TCP uses the two-byte length prefix. Unknown or malformed packets are dropped. `update` replaces the suffix and upstream arrays under a lock.

- [ ] **Step 6: Run the proxy harness**

Start a fake upstream on `127.0.0.1:15354` with `/tmp/fake-upstream.py` that answers A `203.0.113.7`. Instantiate `DNSProxy(port: 15353, suffixes: ["youtube.com"], upstreams: ["127.0.0.1"])` with upstream port injection (`upstreamPort` parameter) and send three UDP queries with a throwaway client: `m.youtube.com` → RCODE 3; `example.com` → RCODE 0 with `203.0.113.7`; a malformed two-byte packet → no response and the process stays alive. Repeat one query over TCP.
Expected: all four checks pass; proxy still answers after the malformed packet.

- [ ] **Step 7: Commit**

```bash
git add NoHallaDomainGuard/DNSMessage.swift NoHallaDomainGuard/DNSProxy.swift
git commit -m "feat(guard): add loopback DNS proxy"
```

---

### Task 4: System DNS capture, switch, and restore

**Files:**
- Create: `NoHallaDomainGuard/SystemDNS.swift`
- Harness: throwaway `/tmp/dns-settings.swift`

**Interfaces:**
- Consumes: `DNSRestoreManifest`, `DomainGuardStatus`.
- Produces:
  - `struct NetworkServiceInfo: Equatable { var name: String; var interfaceType: String; var bsdName: String? }`
  - `enum SystemEnvironment { static func services() -> [NetworkServiceInfo]; static func upstreams() -> [String] }`
  - `protocol CommandRunning { func run(_ executable: String, _ arguments: [String]) -> (status: Int32, output: String) }`
  - `enum DNSApplyResult: Equatable { case applied([String]); case unavailable(String); case degraded(String) }`
  - `final class SystemDNSManager { init(runner: CommandRunning, services: [NetworkServiceInfo], upstreams: [String], manifestURL: URL, dryRun: Bool); func captureAndSwitch() -> DNSApplyResult; func reconcile() -> DNSApplyResult; func restore() -> Bool; var isActive: Bool }`

- [ ] **Step 1: Write the failing settings harness**

Fake services: `Wi-Fi` (`Ethernet`, `en0`), `Office VPN` (`PPP`, `ppp0`), `Thunderbolt Bridge` (`Bridge`, `bridge0`).
Fake runner: `-getdnsservers Wi-Fi` → `There aren't any DNS Servers set on Wi-Fi.`; `-getdnsservers Thunderbolt Bridge` → `192.168.1.1\n`; set calls → status 0.
Assert: capture stores an empty Wi-Fi list and the bridge list, switches both with `-setdnsservers … 127.0.0.1`, never queries or switches the VPN service, `restore()` sets Wi-Fi to `Empty` and the bridge to `192.168.1.1`, and upstreams containing only `127.0.0.1` produce `.unavailable` with no set call.

- [ ] **Step 2: Run it and confirm it fails**

Run: `swiftc -O NoHallaDomainGuard/SystemDNS.swift NoHalla/Core/Guard/DomainGuardStatus.swift /tmp/dns-settings.swift -o /tmp/dns-settings && /tmp/dns-settings`
Expected: compile error, type not found.

- [ ] **Step 3: Implement the provider and manager**

- `SystemEnvironment.services()` enumerates `SCNetworkServiceCopyAll`, skips disabled services and interface types `PPP`, `IPSec`, `VPN`, and BSD names beginning `utun`, `ppp`, `ipsec`; keeps Ethernet, Wi-Fi, Bridge, Thunderbolt.
- `SystemEnvironment.upstreams()` reads `SCDynamicStoreCopyValue("State:/Network/Global/DNS")["ServerAddresses"]`.
- Read each selected service with `-getdnsservers "<name>"`; parse `There aren't any DNS Servers set` as an empty list.
- Reject `127.0.0.1` and `::1` upstreams; if none remain, return `.unavailable` without switching.
- Persist the manifest atomically before the first set; every later service is captured and persisted before it is switched. Unreadable service → skip, remember `degraded`.
- `restore()` sets each saved service to its list, or `Empty` for an empty list, then removes the manifest.
- `dryRun` logs the command without executing it.

- [ ] **Step 4: Run the harness**

Run: `swiftc -O NoHallaDomainGuard/SystemDNS.swift NoHalla/Core/Guard/DomainGuardStatus.swift /tmp/dns-settings.swift -o /tmp/dns-settings && /tmp/dns-settings`
Expected: `ok`, no `networksetup` call executed.

- [ ] **Step 5: Commit**

```bash
git add NoHallaDomainGuard/SystemDNS.swift
git commit -m "feat(guard): switch and restore system DNS"
```

---

### Task 5: Helper orchestration, version, restore, and status

**Files:**
- Modify: `NoHallaDomainGuard/main.swift`
- Create: `NoHallaDomainGuard/GuardRunner.swift`
- Harness: throwaway `/tmp/guard-runner.swift` plus the built helper with a temp plist

**Interfaces:**
- Consumes: `DomainBlocklist`, `DomainGuardStatus`, `DNSProxy`, `SystemDNSManager`, `SystemEnvironment`.
- Produces:
  - `final class GuardRunner { init(config: GuardConfig, statePath: String, hostsPath: String, statusURL: URL, manifestURL: URL, dryRun: Bool); func runOnce() -> DomainGuardStatus; func restoreOnly() }`
  - CLI: `--version` prints `domainGuardProtocol=2`; `--restore` restores DNS and exits; `--once` applies once; `--dry-run` logs privileged commands.

- [ ] **Step 1: Write the failing version check**

Run: `build/Build/Products/Release/No-halla.app/Contents/MacOS/NoHallaDomainGuard --version`
Expected before the change: it tries to load the plist and exits 2.

- [ ] **Step 2: Handle the modes in `main.swift`**

Before loading `guard.plist`: `--version` prints `domainGuardProtocol=2` and exits 0; `--restore` restores from `DomainGuardProtocol.manifestURL` and exits. `--dry-run` is parsed and passed down.

- [ ] **Step 3: Implement `GuardRunner.runOnce()`**

Order: if a stale manifest exists, restore it first. Read `domain-guard.json`; when inactive, restore, remove the hosts section, write status `suffixMode: unavailable, dnsSwitched: false`; when active, write the hosts section, start the proxy on 53, then construct `SystemDNSManager` with `SystemEnvironment.services()` and `SystemEnvironment.upstreams()` and call `captureAndSwitch()`, then update status. If the proxy cannot bind, keep hosts only and report `unavailable` with the reason. Poll every `pollSeconds` (default 1) and call `reconcile()`.

- [ ] **Step 4: Add SIGTERM handling**

`signal(SIGTERM)`: restore DNS, remove the hosts section, exit 0. The launchd `KeepAlive` covers crashes.

- [ ] **Step 5: Write the status atomically**

Write `guard-status.json` on every change and once per poll; create `/Library/Application Support/NoHalla` as root with 0755 when missing; the file is 0644. `--dry-run` writes to the temp path from the test plist.

- [ ] **Step 6: Run the dry-run harness**

Create a temp plist pointing `statePath` and `hostsPath` to `/tmp`, a state with `active:true` and `["www.youtube.com"]`, a pre-existing temp manifest, and run the built helper with `--once --dry-run`. Expected: the restore command for the manifest's service is printed before any switch; hosts file has `youtube.com` and `www.youtube.com`; status `suffixMode` is `active` or the dry-run equivalent; no `networksetup` call changed the machine.

- [ ] **Step 7: Commit**

```bash
git add NoHallaDomainGuard/main.swift NoHallaDomainGuard/GuardRunner.swift
git commit -m "feat(guard): orchestrate proxy and DNS restore"
```

---

### Task 6: Restore fail-open protection semantics

**Files:**
- Modify: `NoHalla/Core/Engine/ProtectionEngine.swift` (`domainGuardActive`, comments)
- Modify: `NoHalla/Core/Config/ConfigStore.swift` (domain normalization already runs on load; keep the cap error surface)
- Modify: `NoHalla/UI/Settings/DomainEditor.swift` and `NoHalla/UI/Settings/SettingsProtectionView.swift` (limit error)
- Modify: `design/copy.json`, `NoHalla/Resources/Localizable.xcstrings` via `scripts/gen-strings.py`

**Interfaces:**
- Consumes: `DomainBlocklist.normalized`.
- Produces: `domainGuardActive` is `false` for `.protected`, `.paused`, `.disabled`, master-off and setup-incomplete; `true` for `.initializing`, `.checking`, `.grace`, `.frozen`, `.unknown`.

- [ ] **Step 1: Revert the activation switch**

In `domainGuardActive`, move `.protected` into the `false` branch and update the comment to the fail-safe model.

- [ ] **Step 2: Add the limit error**

When an add or import would exceed `DomainBlocklist.maxDomains`, show `ui.domain-guard-limit` instead of silently dropping entries. Keep hand-edited config clamped and logged.

- [ ] **Step 3: Regenerate strings and build**

Run: `python3 scripts/gen-strings.py && ./scripts/build.sh`
Expected: `BUILD SUCCEEDED`, universal binary, `215+` keys.

- [ ] **Step 4: Live check with a trusted IP**

Launch the new build; with the public IP still trusted, read `~/Library/Application Support/NoHalla/domain-guard.json` and confirm `"active":false`, and `/etc/hosts` has no No-halla markers. Do not publish an active state in this task: the installed daemon is still the old build until the final acceptance step.

- [ ] **Step 5: Commit**

```bash
git add NoHalla/Core/Engine/ProtectionEngine.swift NoHalla/Core/Config/ConfigStore.swift NoHalla/UI/Settings/DomainEditor.swift NoHalla/UI/Settings/SettingsProtectionView.swift design/copy.json NoHalla/Resources/Localizable.xcstrings
git commit -m "fix(guard): block only while the IP is untrusted"
```

---

### Task 7: App helper-version and degraded-status UI

**Files:**
- Modify: `NoHalla/UI/Settings/DomainGuardInstaller.swift`
- Modify: `NoHalla/UI/Settings/SettingsProtectionView.swift`
- Modify: `NoHalla/UI/Components/DomainGuardInstallView.swift`
- Modify: `design/copy.json`, regenerate the catalog
- Modify: `README.md`

**Interfaces:**
- Consumes: `DomainGuardProtocol`, `DomainGuardStatus`, `DomainGuardInstaller`.
- Produces:
  - `static func protocolVersion() -> Int?` — runs the installed helper with `--version`, parses `domainGuardProtocol=`.
  - `static var isSuffixCapable: Bool` — installed and protocol ≥ 2.
  - `static func readStatus() -> DomainGuardStatus?` — reads the root-owned status file.

- [ ] **Step 1: Implement the version probe**

Run `/usr/local/libexec/nohalla-domain-guard --version` with a 2 s timeout; return `nil` on launch failure or an unparsable line. Do not cache across launches.

- [ ] **Step 2: Show the warning and reinstall**

In Settings → Protection → Blocked sites: when installed but not suffix-capable, show `ui.domain-guard-reinstall` with a Reinstall button calling the existing installer; when the status file reports `unavailable` or `degraded`, show `ui.domain-guard-suffix-warning` with the reason. When the helper is missing, the existing install view stays.

- [ ] **Step 3: Update copy and README**

Add the two keys to `design/copy.json` (EN/RU), regenerate, and update the README's Blocked sites section: one entry covers the family, the block is active only while trust is unproven, DNS-over-HTTPS and existing connections bypass it, the helper needs one reinstall.

- [ ] **Step 4: Build and inspect**

Run: `python3 scripts/gen-strings.py && ./scripts/build.sh`; launch the app and open Settings → Protection in both languages. Expected: the new strings render, no missing-key fallback, the Reinstall state appears when the installed helper is older.

- [ ] **Step 5: Commit**

```bash
git add NoHalla/UI/Settings/DomainGuardInstaller.swift NoHalla/UI/Settings/SettingsProtectionView.swift NoHalla/UI/Components/DomainGuardInstallView.swift design/copy.json NoHalla/Resources/Localizable.xcstrings README.md
git commit -m "feat(settings): warn about helper suffix support"
```

---

### Task 8: Uninstall restores DNS

**Files:**
- Modify: `NoHalla/Resources/uninstall-domain-guard.sh`
- Modify: `README.md`

**Interfaces:**
- Consumes: the helper's `--restore` mode and `dns-restore.json`.
- Produces: uninstall restores every saved service, removes the manifest, status file, helper, plist, and the hosts section.

- [ ] **Step 1: Restore after stopping the daemon**

In the uninstaller, run `launchctl bootout "system/$LABEL"` first, then:
- if `"$HELPER"` exists, run `"$HELPER" --restore`;
- otherwise, if `dns-restore.json` exists, read each saved service with `plutil -extract services.$i.name raw -o -` and each server with `plutil -extract services.$i.servers.$j raw -o -`, then call `networksetup -setdnsservers "<name>" <servers…>` or `Empty` when the list is empty. On any parse failure, print the manifest path and exit non-zero **before** deleting anything, so a manual restore is still possible.
Then delete the helper, plist, `guard.plist`, `dns-restore.json`, `guard-status.json`, and the hosts section.

- [ ] **Step 2: Check the script**

Run: `bash -n NoHalla/Resources/uninstall-domain-guard.sh`
Expected: exit 0. The destructive path is exercised live in Task 9; do not run it as part of this task.

- [ ] **Step 3: Commit**

```bash
git add NoHalla/Resources/uninstall-domain-guard.sh README.md
git commit -m "fix(guard): restore DNS on uninstall"
```

---

### Task 9: Universal build and live acceptance

**Files:**
- Modify: `README.md` (manual matrix result)
- No code changes.

- [ ] **Step 1: Build**

Run: `./scripts/build.sh`
Expected: `BUILD SUCCEEDED`; `lipo -info` shows `x86_64 arm64`; the helper is at `Contents/MacOS/NoHallaDomainGuard`.

- [ ] **Step 2: One-time helper reinstall (owner)**

The owner runs the bundled installer once (administrator prompt). This is the only privileged step; normal operation is daemon-only, and no further sudo is needed.

- [ ] **Step 3: Live matrix**

1. Trusted IP: no hosts markers, real DNS in `scutil --dns`, sites load.
2. Untrusted IP: hosts markers, system DNS `127.0.0.1`, `m.youtube.com` fails, `google.com` works, `youtube.com` fails.
3. Return to trusted: saved DNS restored for every service; no `127.0.0.1` left; sites load.
4. Pause and off: same restore.
5. Graceful quit: restore.
6. `kill -9` the helper: launchd restarts; active state re-applies; the block stays.
7. Network change or VPN reconnect while blocked: the new service is captured and switched; release restores it.
8. Uninstall: DNS restored, hosts clean.

- [ ] **Step 4: Record**

Write the matrix result in the README or the PR, per `AGENTS.md`; commit only documentation.

```bash
git add README.md
git commit -m "docs: record domain guard acceptance results"
```