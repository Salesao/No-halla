# Domain guard: suffix blocking with a local HTTP proxy

Date: 2026-11-20
Status: draft for owner approval
Supersedes: `2026-11-19-domain-guard-suffix-design.md` (approach B, defeated by Happ's tunnel DoH)
Owner decisions: approach A; block sites only while the IP is not proven trusted.

## Intent

Blocked sites are a fail-safe, not a permanent block. When No-halla cannot prove
that the current public IP is trusted, every configured domain and all of its
subdomains must stop loading. When trust is restored, everything works again.
One list entry covers a whole family.

The previous DNS design failed live: Happ installs an unscoped DNS-over-HTTPS
resolver as part of its tunnel, so `mDNSResponder` bypassed the `127.0.0.1`
nameserver and cached answers kept working. DNS is not a controllable layer on
this machine.

## Goals

1. Block only in `initializing`, `checking`, `grace`, `frozen`, `unknown`;
   release in `protected`, `paused`, `disabled`, and setup-incomplete.
2. One suffix entry blocks the domain and every subdomain.
3. Work regardless of DNS-over-HTTPS, Happ's tunnel DNS, or the system cache.
4. No new interactive sudo at runtime; the existing root daemon does the work.
5. Every release path restores the previous proxy settings.
6. Never report `active` when the proxy or the system-proxy switch did not take.

## Non-goals

- Blocking apps that ignore the system proxy (native clients, `curl`).
- Packet filtering, SNI inspection, TLS decryption, per-app blocking.
- DNS filtering, kill switch, VPN client, Network Extension.
- Blocking by TLD or IP literal.

## Anti-goals

- Leaving `127.0.0.1` in the system proxy after release.
- Overwriting proxy values that No-halla did not save.
- Claiming suffix blocking when the proxy is not reachable or the system proxy
  is not pointed at it.

## Current state

- The helper is installed as protocol 3 and currently runs the DNS proxy and
  system-DNS switch. That code is replaced; the installed binary needs one
  administrator reinstall at the end.
- `DomainBlocklist` already normalizes a leading `www.` and matches suffixes.
- The engine already uses the fail-safe activation model (D47).
- `/etc/hosts` exact entries stay as a fallback.
- Happ (bundle `su.ffg.happ`) applies a DoH resolver with its tunnel; its
  routing profile exposes Remote/Tunnel DNS type and IP, but no global
  encrypted-DNS switch. Approach A does not depend on that setting.

## Approaches considered

- **A. Local HTTP/HTTPS proxy + system proxy switch (chosen).** The helper
  listens on loopback, the system web/secure proxy points at it while blocking,
  `CONNECT host:port` is checked by suffix. DoH, Happ DNS, and the system cache
  are irrelevant because the browser never resolves the blocked name itself.
  Cost: apps that ignore the system proxy bypass; the proxy is a fail-closed
  dependency for proxies users.
- **B. DNS proxy + system DNS switch.** Implemented and rejected live: Happ's
  unscoped tunnel DoH bypassed it and cached answers ignored the switch.
- **C. Network Extension DNS proxy/content filter.** Proper system-wide
  interception, but needs an Apple-granted entitlement and non-ad-hoc signing;
  out of the current distribution model.
- **D. SNI filter with packet redirection.** Would cover any app, but macOS
  packet redirection loses the original destination, needs divert/TUN, QUIC
  handling, and heavy pf state. Too risky for this project.

## Design

### 1. Activation semantics

Unchanged from D47: `domainGuardActive` is true only for `initializing`,
`checking`, `grace`, `frozen`, `unknown`; false for `protected`, `paused`,
`disabled`, master-off, setup-incomplete. Graceful quit publishes `active:false`.

### 2. Suffix normalization

Unchanged: a leading `www.` is dropped when the remainder is a valid name;
`isBlocked` matches the root or a `.root` descendant; a trailing root dot is
ignored. The 256-entry cap is an explicit error at add/import.

### 3. Hosts fallback

The marked `/etc/hosts` section stays for exact names (apex + `www.`), covers the
window before the proxy is used, and keeps exact blocking if the proxy cannot
start. It is removed on release.

### 4. Loopback HTTP/HTTPS proxy

- Listens on `127.0.0.1:<port>` (default 8844), loopback only.
- HTTPS: parse `CONNECT host:port`; if the host equals or ends with a blocked
  suffix, answer `403` and close; otherwise connect to the target and relay
  bytes both ways.
- HTTP: parse the absolute request line, check the host, rewrite the request
  line to origin-form, forward, and stream the response.
- No decryption, no caching, no authentication; header cap 64 KB, connect
  timeout 10 s, idle timeout 5 min, unknown methods rejected.
- If the port cannot be bound, report `unavailable`, keep hosts only, and do not
  touch the system proxy.
- Suffixes are refreshed from the same `domain-guard.json` poll as hosts.

### 5. System proxy switch and restore

- Before switching, capture `-getwebproxy` and `-getsecurewebproxy` for every
  enabled hardware service, persist them atomically, then set both to
  `127.0.0.1:<port>` with `networksetup`.
- VPN/PPP/utun services are skipped; a service discovered while active is
  captured before it is switched; an unreadable service is left untouched and
  reported `degraded`.
- On release, restore each saved state exactly: enabled/disabled, server, port.
  Remove the manifest only after a successful restore. A crashed helper keeps
  the block (fail-closed); launchd restarts it and the manifest survives.
- If the manifest is missing or corrupt, disable the system proxy for the
  affected services rather than leaving loopback.
- Uninstall restores from the manifest; if the helper binary is gone, the
  uninstaller reads the manifest with `plutil`.

### 6. Lifecycle and status

- Start: restore a stale manifest first; if the state is active, write hosts,
  start the proxy, switch the system proxy, write status. If inactive, restore
  and remove hosts.
- Crash: `KeepAlive` restarts; active state re-applies. Graceful quit releases.
- `SIGTERM`: restore and exit.
- Protocol 4. `--version` prints `domainGuardProtocol=4`; the app requires 4 and
  offers Reinstall otherwise.
- Status file (root-owned, 0644): `{protocolVersion, proxyMode:
  active|unavailable|degraded, proxySwitched, reason, updatedAt}`. The app
  reads it and warns when suffix mode is unavailable or degraded.

### 7. UI copy

- One entry blocks the domain and all subdomains while protection cannot prove a
  trusted IP.
- The block uses the system proxy: apps that ignore it (some native clients,
  `curl`) are not covered; already-open connections keep working.
- DoH is no longer a caveat for proxied browsers; the helper explains the
  proxy-based model instead.

### 8. Verification

Code-level (no sudo):
- Suffix rules and normalization (already passing).
- HTTP proxy on a high port: blocked CONNECT → 403; allowed CONNECT tunnels to a
  local echo server; absolute-form HTTP is forwarded with an origin-form line;
  malformed/oversized requests are dropped; the listener stays alive.
- Fake `networksetup` runner: capture/restore web and secure proxy states,
  skip VPN services, refuse unreadable services, restore after a new service
  appears.

Live (after one helper reinstall), with Happ connected:
- Trusted IP: no hosts markers, system proxy unchanged, sites load.
- Untrusted IP: hosts markers, `scutil --proxy` shows `127.0.0.1:8844`,
  `m.youtube.com` and a random `*.youtube.com` fail, `google.com` loads.
- Trusted again, pause, off, graceful quit: proxy settings restored exactly; a
  leak check finds no `127.0.0.1` in `networksetup -getwebproxy`/`securewebproxy`.
- Helper `kill -9` (owner/admin): launchd restart re-applies.
- Uninstall: proxy settings restored, hosts clean.

## Risks

- Apps that ignore the system proxy bypass the block; documented.
- If the proxy dies and launchd cannot restart it, proxied apps lose network
  until restore (fail-closed).
- Already-open connections and cached pages keep working until reload/restart.
- A system proxy may conflict with another proxy app; No-halla saves and
  restores the exact previous state, and refuses to switch if it cannot read it.
- One administrator reinstall is required to replace protocol 3.

## What is left to the builder

- Proxy request parser details and connection lifecycle.
- Manifest format for web/secure proxy state.
- Exact wording and placement of the degraded warning.
- Ordering of hosts/proxy writes during activation and release.