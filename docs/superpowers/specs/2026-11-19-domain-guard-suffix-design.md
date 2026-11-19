# Domain guard: suffix blocking with a local DNS proxy

Date: 2026-11-19
Status: draft for owner approval
Owner decisions: approach B; block sites only while the IP is not proven trusted.

## Intent

Blocked sites are a fail-safe, not a permanent block. When No-halla cannot prove
that the current public IP is trusted, every configured domain and all of its
subdomains must stop resolving. When trust is restored, everything resolves
again. One list entry must cover a whole family (`youtube.com` blocks
`m.youtube.com`, `www.youtube.com`, `rr1---sn-….googlevideo.com` is a different
family and needs its own entry).

The previous always-on behavior (D45) inverted this and is reverted.

## Current state

- `ProtectionEngine.domainGuardActive` blocks in every state while protection
  is enabled, including `protected` (D45). The owner wants the pre-D45 model.
- `DomainBlocklist.hostnames` expands bare/`www.` pairs, but `/etc/hosts` has no
  wildcards: every subdomain is a separate entry.
- `NoHallaDomainGuard` is an installed root LaunchDaemon that polls
  `domain-guard.json` and rewrites a marked `/etc/hosts` section.
- A spike tried `/etc/resolver/<domain>` scoped resolvers. macOS registered the
  entry (`scutil --dns`) but mDNSResponder sent no query to the local responder,
  and names still resolved. The test could not force a full resolver reload
  without root. The mechanism is unverified on this macOS and was rejected.

## Goals

1. Block only while the IP is not proven trusted: `initializing`, `checking`,
   `grace`, `frozen`, `unknown`.
2. Release the block in `protected`, `paused`, `disabled`, and when setup is
   incomplete.
3. One suffix entry blocks the domain and every subdomain, system-wide.
4. No new interactive `sudo` at runtime; the existing root daemon performs
   privileged work.
5. Every path that turns the block off (trusted IP, pause, off, graceful quit,
   uninstall, daemon crash) restores DNS and removes the hosts section.
6. Keep the existing exact-host hosts mechanism as a fast, proven baseline.

## Non-goals

- Intercepting DNS-over-HTTPS or per-app resolvers.
- Packet filtering, SNI inspection, per-app blocking, kill switch.
- Blocking by TLD or IP literal.
- Caching or filtering DNS content.
- A new Network Extension or Apple entitlement.

## Anti-goals

- Leaving `127.0.0.1` in system DNS after the guard releases.
- Overwriting DNS values that No-halla did not save.
- Silently claiming suffix blocking works when the proxy or DNS switch failed.

## Constraints

- macOS 13+; Swift 5.9 language mode; system frameworks and public CLIs only.
- The helper is ad-hoc signed; updating it requires one administrator install.
  The owner asked to avoid interactive sudo, so this is a one-time step at
  deployment, not part of normal operation.
- The app stays unprivileged; only the root daemon touches `/etc/hosts`,
  system DNS and the proxy socket.
- Vivaldi/Chromium and other apps using DNS-over-HTTPS bypass system DNS; the UI
  keeps stating this.

## Approaches considered

- **A. `/etc/resolver/<domain>` scoped resolvers.** Smallest change, true suffix
  routing, no new listener. Rejected: the spike could not confirm that
  mDNSResponder honors the entry; queries went to the default resolver even
  with a live local responder. Shipping it risks a silent no-op.
- **B. Local DNS proxy + system DNS switch (chosen).** The helper listens on
  loopback, answers `NXDOMAIN` for blocked suffixes, forwards everything else to
  the network's real DNS servers, and points system DNS at itself only while the
  block is active. Deterministic suffix matching, testable locally, no reliance
  on undocumented resolver selection. Cost: a new failure mode (proxy down means
  no DNS) and more code.
- **C. Network Extension DNS proxy/content filter.** The Apple-approved path but
  needs an Apple-granted entitlement and non-ad-hoc signing, which the current
  distribution model does not have.

## Design

### 1. Activation semantics

`domainGuardActive` returns:

- `false` for `config.protection.enabled == false`, `setupIncomplete`, `paused`,
  `disabled`;
- `true` for `initializing`, `checking`, `grace`, `frozen`, `unknown`;
- `false` for `protected`.

`publishSnapshot` publishes the effective suffix list with the flag; graceful
quit keeps writing `active:false`.

### 2. Suffix normalization

- A leading `www.` is stripped when the list is normalized, so
  `https://www.youtube.com` is stored and displayed as `youtube.com`. A suffix
  root covers its own apex and descendants.
- Other subdomains stay as typed (`mail.example.com` blocks only that subtree).
- Existing config entries are passed through the same normalization on load;
  the effective list is deduplicated and capped (256).
- The cap is enforced at the add/import boundary with an explicit error; the
  effective list is never silently truncated below what the UI lists. A
  hand-edited config that exceeds it is clamped and logged.
- `DomainBlocklist.hostnames` keeps producing apex + `www.` for the hosts
  fallback.

### 3. Hosts fallback

The daemon continues to write the marked `/etc/hosts` section for the same
active domains (apex + `www.`). It costs nothing, covers the window before the
DNS switch is visible, and keeps exact blocking if the proxy cannot start. The
section is removed whenever the block is released.

### 4. DNS proxy

The helper hosts a small DNS responder:

- UDP and TCP on `127.0.0.1:53`, loopback only.
- Parse the question name; if it equals or ends with `.<blocked-suffix>`, return
  `NXDOMAIN` (QR=1, RA=1, RCODE=3, no answers).
- Otherwise forward the raw query to the saved upstream DNS servers, first
  responding one wins, 2 s timeout, return `SERVFAIL` if none answers.
- Cap message size (4096 bytes), drop malformed packets, no recursion beyond the
  saved upstreams, no outbound listener.
- If `127.0.0.1:53` is already bound (e.g. dnsmasq), do not fight it: log
  `suffix mode unavailable`, keep hosts-only blocking, and do not switch DNS.
- Keep the blocking suffix set in memory, refreshed from the same
  `domain-guard.json` poll as the hosts section.

### 5. System DNS switch and restore

- Upstream servers are snapshotted before the first switch from
  SystemConfiguration (`State:/Network/Global/DNS`), which includes
  DHCP-provided servers; `networksetup -getdnsservers` is used only to record
  what each service must be restored to. The union of the active primary
  resolvers is used, first responding upstream wins.
- Loopback upstreams (`127.0.0.1`, `::1`) are rejected. If no non-loopback
  upstream remains, the daemon does not switch DNS: it keeps hosts-only
  blocking and reports `suffixMode: unavailable`.
- Service set: enabled services only (names prefixed `*` are skipped). Services
  backed by VPN/PPP/utun interfaces are left untouched so their own resolvers
  keep working; hardware and bridge services are switched.
- A service discovered after activation is captured and persisted *before* it
  is switched. If its current value cannot be read, it is left alone and the
  daemon reports `suffixMode: degraded`; it never overwrites a value it did not
  save.
- Set every selected service to `127.0.0.1` (`networksetup -setdnsservers`).
- Persist a restore manifest under `/Library/Application Support/NoHalla/`
  before the first change, so a crash cannot lose the original values.
- On release: restore each saved value (`-setdnsservers … Empty` for DHCP),
  remove the manifest and hosts section.
- On every poll: if active and a service is not pointing at `127.0.0.1`,
  reapply; if inactive and the manifest exists, restore. This covers network
  changes and VPN reconnects.
- If the saved value is missing or corrupt, restore that service to `Empty`
  (DHCP) rather than leaving loopback.
- VPN-supplied scoped DNS can take precedence for tunnel traffic. That is a
  documented limitation; the poll re-applies but cannot override a VPN's own
  resolver.

### 6. Lifecycle and crash safety

- Daemon start: read state. Active → ensure proxy, reapply DNS, write hosts.
  Inactive → restore any manifest, remove hosts, leave the proxy idle.
- Daemon `SIGTERM` (uninstall/stop): restore DNS and remove the hosts section.
- Daemon crash: launchd `KeepAlive` restarts it; the persisted manifest plus the
  still-active state reapply the block. If the app is gone and the state was
  released, the next start restores.
- Graceful app quit writes `active:false`; the daemon releases within its poll.
- Uninstaller: stop the daemon, restore from the manifest if present, remove the
  hosts section, `/etc/resolver` is not used.

**Helper version gate.** The daemon answers `--version` with
`domainGuardProtocol=<n>` (starting at 2). The app executes
`/usr/local/libexec/nohalla-domain-guard --version` and treats suffix mode as
available only for protocol ≥ 2. With an older helper the app keeps the proven
exact-host behavior, labels the list exact-host, and offers Reinstall. The
state schema stays `{schemaVersion, active, domains}`, so an old daemon never
fails to decode it.

**Status channel.** The daemon writes
`/Library/Application Support/NoHalla/guard-status.json` (directory 0755
root:wheel, file 0644, atomic) with
`{protocol, suffixMode: active|unavailable|degraded, dnsSwitched, reason,
updatedAt}`. The app only reads it; the root daemon is the sole writer, so
there is no race with the user-owned `domain-guard.json`. Settings → Protection
shows a warning when suffix mode is unavailable or degraded.

**Fail-closed policy.** A crash keeps the block, which is the intended
fail-safe. Decided: there is no expiry — the block stays until the state file
says otherwise or the helper is uninstalled, and the status file records how
long it has been active. Ordinary domains keep resolving because the proxy
forwards them; only the listed sites stay closed.

### 7. UI copy

- Blocked sites helper: one entry covers the domain and all subdomains; the
  block applies only while protection cannot prove a trusted IP (and not while
  paused/off); DNS-over-HTTPS clients and already-resolved connections bypass it.
- README: same model, the DNS-switch mechanism, the restore guarantees, and the
  failure modes.
- Onboarding step 4 and its intro line updated to the restored semantics.

### 8. Verification

Code-level (no sudo):

- Domain normalization/suffix matching unit harness, including
  `https://www.youtube.com` → `youtube.com`, `mail.example.com` kept,
  `www.com` not collapsing to `com`.
- Proxy parser/matcher harness on a high port: blocked suffix → NXDOMAIN,
  other names forwarded, upstream failure → SERVFAIL, malformed packets dropped.

Live (after the one-time helper reinstall):

- Trusted IP: no hosts markers; `scutil --dns` shows the real servers; sites
  load.
- Untrusted IP: hosts markers present; system DNS `127.0.0.1`; `m.youtube.com`
  and a random `*.youtube.com` fail; `google.com` resolves; `youtube.com` fails.
- Back to trusted: original DNS restored, markers gone, sites load.
- Graceful quit, pause, off, daemon `kill -9` + launchd restart, uninstall, and
  a network change while active all end with the correct DNS state.
- Self-reference: with a user loopback resolver already on `127.0.0.1:53`, or a
  saved upstream equal to loopback, the daemon must not switch DNS and must
  report `unavailable`.
- New service while blocked: it is captured, persisted, switched, and restored
  to its original values on release; an unreadable service is left untouched
  and reported `degraded`.
- Old helper: `--version` below 2 yields exact-host behavior and a Reinstall
  prompt, never a suffix claim.
- Leak check: no `127.0.0.1` remains in `networksetup -getdnsservers` for any
  service after release.

## Risks and open points

- One administrator install is required to deploy the new helper; there is no
  way to update a root daemon without it.
- If the proxy dies and launchd cannot restart it, DNS fails closed (network-wide)
  until restore. KeepAlive plus restore-on-start is the mitigation.
- `networksetup -setdnsservers` persists in the service configuration, not just
  the running session; restore-on-start and the manifest are mandatory, not
  best-effort.
- VPN clients that install their own scoped resolvers may bypass the proxy.
- DoH remains a deliberate blind spot.
- `networksetup` parsing is brittle across macOS versions; the builder keeps it
  narrow and never switches a service whose current value was not captured.
  Upstream discovery uses SystemConfiguration rather than parsing `scutil`.

## What is left to the builder

- Exact proxy concurrency model and packet parsing structure.
- Where the suffix matcher and normalization live so the app and helper share
  one implementation.
- The precise manifest format and restore retry policy.
- Ordering of hosts and DNS writes during activation/release.
- The wording and placement of the degraded-suffix warning in Settings.