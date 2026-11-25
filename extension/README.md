# No-halla Gate

A standalone Chrome extension (Manifest V3) that blocks a list of domains when
your **public IPv4 address** is not in your trusted list. It is a separate
artifact next to the macOS No-halla app: the app is not required, is not
modified by the extension, and does not read or write the extension state.

- Minimum Chrome: **121**
- Vanilla JavaScript ES modules; no build step, no npm dependencies
- English / Russian UI, light / dark / high-contrast design tokens
- All outbound traffic is limited to the configured HTTPS IP-check endpoints
  (the main one plus any fallbacks you add)

## Install (unpacked)

1. Open `chrome://extensions` and enable **Developer mode**.
2. Choose **Load unpacked** and select the `extension/` directory.
3. Open the extension settings (puzzle-piece menu → No-halla Gate → Settings).
4. Click **Add current IP** to trust the IP you are on now.
5. Add the domains you want to protect. Chrome asks for access to each domain;
   allow it. Denying the prompt leaves the domain out of the list.

The toolbar popup shows the same domain list and can add or remove domains.
Adding a domain asks Chrome for site access directly from the popup. If Chrome
does not show the prompt (a known popup limitation) or you dismiss it, the
domain is not added and a short error appears; add it from Settings instead. If
the popup closes while the prompt is visible, the grant is still picked up and
the domain is saved. The popup also has an **Add current IP**
control and an **Add current site** control that adds the domain of the active
tab.

The extension is not published in the Chrome Web Store.

## How it works

**Trust signal.** A `fetch` to the configured endpoint (default
`https://ipinfo.io/ip`) returns the public IPv4 address as plain text. The
address is strictly parsed as IPv4 and matched against the trusted list
(`a.b.c.d` or CIDR `/0`–`/32`). Result:

| Verdict | Meaning | Gate |
| --- | --- | --- |
| `trusted` | address matches the trusted list | open |
| `untrusted` | valid IPv4, not in the list | closed |
| `unknown` | network/timeout/non-200/HTTP redirect/IPv6/invalid body/empty trusted list | closed |

`unknown` is never treated as trusted. The request uses
`cache: "no-store"`, `credentials: "omit"`, `redirect: "error"` and a 2.5 s
abort controller. A transport failure (`TypeError`, for example
`ERR_CONNECTION_CLOSED`) is retried once inside a 4 s budget; a timeout, a
non-2xx response, a redirect and an unparseable body are not retried.

**Tab-context check.** When a tab of a listed domain is already open, the same
HTTPS check runs inside that tab (`chrome.scripting.executeScript`, isolated
world) instead of the extension service worker, so it uses the network path
the page actually uses. That verdict is authoritative; the service-worker check
runs when no listed tab is available, the tab is restricted, or the endpoint
does not allow cross-origin reads. A failed tab check never opens the gate.

**Fallback endpoints.** The main endpoint can be picked from a preset list or
typed (HTTPS only; the body must be a plain IPv4). Up to eight extra endpoints
can be added from the preset list. Each automatic check uses one available
endpoint in rotation: a valid IPv4 (trusted or untrusted) is final; a network
error, non-2xx, redirect or unparseable body cools that endpoint down and the
next check tries another; if no endpoint is available the verdict is
`unknown`/closed. A valid untrusted address is never retried against another
endpoint. The in-tab check uses the same endpoint; if its request fails for
CORS or transport, the service worker may try that endpoint once. A 429/403 is
not repeated in the same check. The in-tab check skips known presets that do
not send `Access-Control-Allow-Origin` (they are used by the background path
only). HTTP-only services such as `ip-api.com` are not offered: a plaintext
answer could be rewritten in transit. Each enabled endpoint sees your IP.
Presets and their CORS capability live in `src/endpoints.js`.

**When a check runs.**

- When a navigation to a listed domain is observed (`chrome.webRequest` watches
  only main-frame/sub-frame requests for the listed domains; a recent verdict
  is reused for 30 s, and in-flight checks are deduplicated).
- On browser startup and extension install/update.
- On **Check now** and on the blocked page.
- While the active tab is a visible listed domain, a content script asks for a
  check about every 5 seconds while the window has focus and the gate is trusted,
  so an IP change is noticed without a navigation.
  The script is registered only for granted listed domains and only while the
  background check is on; the background ignores ticks from any other tab.
- Optionally, in the background. **Background check is off by default.** When
  enabled, a 30 s alarm checks only while the active tab is a listed domain
  (even if the window is minimized or occluded). Switching to another tab or
  domain makes no automatic request. Chrome may still delay an alarm. Off is
  the owner's decision: the extension checks when you actually open a listed
  site.

**Blocking.** Declarative Net Request dynamic rules are built per domain:

- navigation and frames → redirect to the packaged blocked page;
- every other resource type → blocked (`ERR_BLOCKED_BY_CLIENT`).

`requestDomains` covers the domain and its subdomains. When the gate closes (or
a blocked domain is added), already-open tabs of listed domains are reloaded
once so an SPA cannot keep running from its in-memory state; the reload hits
the redirect rule and shows the blocked page. Rules are verified with
`getDynamicRules()` after every update. If the update is rejected or the
verification does not match, the extension reports `unknown`/degraded and never
claims trust. Rules persist across browser restarts.

**Fail-closed start.** On every cold service-worker start the rule state is
`unknown` even if the stored last verdict says `trusted`. Rules stay installed
(or are installed) until a fresh check proves trust and their removal is
verified. A damaged config never removes rules.

**Master switch off** removes every rule. Turning it back on re-checks.
**Empty trusted list** means nothing is trusted: listed domains are blocked
with the setup reason until you add an address.

## Permissions

| Permission | Why |
| --- | --- |
| `declarativeNetRequest` | dynamic block/redirect rules |
| `webRequest` | observe requests to listed domains only (no blocking, no request bodies) |
| `storage` | config and UI state in `chrome.storage.local` |
| `alarms` | the optional background check |
| `activeTab` | read the active tab URL when you click the toolbar icon, for **Add current site** |
| `scripting` | run the IP check inside an already-open listed tab (isolated world) and register the visible-tab heartbeat |

No `notifications`, no `webRequestBlocking`, no `<all_urls>` in
`host_permissions`. Host access is requested per domain when you add it, plus each IP-check endpoint
origin (the manifest grants only the default `https://ipinfo.io/*`; adding a
fallback asks for its host). The manifest declares `optional_host_permissions`
as a pattern so those per-domain prompts are possible; at install only the
default endpoint origin (`https://ipinfo.io/*`) is granted, and no site access
is. `web_accessible_resources` matches all sites only so the blocked page
can be loaded after a redirect for any listed domain; it grants no network
access and uses `use_dynamic_url: true`.

## Honest limits

1. **The first request can leak.** MV3 cannot see a connection's IP before it
   is made. After the public IP changes, the first request to a listed domain
   may still reach the site; the check it triggers blocks the rest. "Never a
   single request" is not achievable by a browser extension.
2. **No background check by default.** If the IP changes while you are not
   opening listed sites, nothing detects it until the next listed request,
   browser start, popup open, or "Check now".
3. **Service-worker and CacheStorage responses** are not covered by DNR. An
   already-cached PWA can keep working from its own cache. Navigation and new
   requests are covered, including the normal HTTP cache.
4. **Already-received responses** cannot be recalled.
5. **Endpoint failure blocks.** If the endpoint is down, rate-limited, or
   returns something other than a plain IPv4, the verdict is `unknown` and the
   gate stays closed. Change the endpoint or add the current IP.
6. **Other extensions can override the block.** An `allow` rule wins over
   `block`, and rules from an extension installed later take precedence. This
   cannot be detected outside unpacked development (`getMatchedRules`).
7. **The service worker sleeps.** MV3 stops it after inactivity. Listed-domain
   requests and alarms wake it; a check cannot run while it is asleep.
8. **Incognito.** Private windows are protected only if the extension is
   allowed in incognito. Chrome has no API to enable this from the extension;
   enable it in `chrome://extensions` → No-halla Gate → Details → Allow in
   incognito. Split incognito mode runs a separate instance.
9. **Dual-stack and TLS interception.** The endpoint may answer over IPv6 while
   site traffic uses IPv4 (different egress) or a corporate proxy with a
   trusted root CA may rewrite the answer. Both can produce a false `trusted`.
   The macOS app has the same limit; one endpoint is used by owner decision.
10. **The tab-context check needs an open listed tab and a CORS-capable
    endpoint.** With no listed tab open (for example, every listed page is
    already redirected to the blocked page), the service-worker path is used.
    Chrome treats the in-tab request as cross-origin, so a custom endpoint must
    send `Access-Control-Allow-Origin`; `ipinfo.io` does. Chrome adds the
    guarded tab's origin (`Origin: https://listed.example`) to that request;
    the extension suppresses the `Referer`. If both contexts are wrong, the
    gate stays closed.
11. **The heartbeat runs only while the active tab is a visible listed
    domain, its window has focus, and the gate is trusted.** Switching to
    another tab or domain stops automatic checks entirely; while the gate is
    closed the heartbeat is ignored and the 30 s alarm covers a hidden or
    unfocused window. A tab that is already on the blocked page has no
    heartbeat, so recovery from there is manual. An active visible and focused
    listed tab makes about twelve checks a minute; failed endpoints cool down
    and the remaining backoff applies.
12. **Every fallback endpoint is another trust source.** Each enabled endpoint
    sees your IP; each check uses one endpoint, so a failed endpoint cools down
    for the next check instead of adding attempts. The in-tab request and one
    background retry of the same endpoint can add up to 2 s each; every enabled
    endpoint host must be granted. If no endpoint is available or the answer is
    invalid, the verdict is `unknown` and the gate stays closed. The in-tab
    check skips endpoints without CORS, so those are used by the background
    path only.
13. **Disabling the extension** (user or enterprise policy) removes all rules
    immediately. There is no protection outside Chrome.

## Files

```
manifest.json          MV3 manifest
src/cidr.js            strict IPv4/CIDR parse + match
src/config.js          storage schema, validation, state
src/endpoints.js       HTTPS endpoint presets and CORS capability
src/trust.js           endpoint fetch -> verdict
src/probe.js           same check inside an open listed tab (fallback: SW)
src/tick.js            active-tab 5 s heartbeat (registered dynamically)
src/rules.js           DNR rule builder, reconcile, verification
src/sw.js              orchestration, triggers, messages, alarms, permissions
src/i18n.js            locale loading, t(), document localization
ui/tokens.css          design tokens (light/dark/contrast)
ui/popup.*             status popup
ui/options.*           settings
ui/blocked.*           redirect target (package-only assets)
_locales/{en,ru}/      generated from design/copy.json (gate.* keys)
icons/                 16/32/48/128 PNG
README.md, README.ru.md
```

UI copy is generated from the repository's single source `design/copy.json`:

```sh
python3 scripts/gen-extension-strings.py
```

Do not edit `_locales/*/messages.json` by hand. The Swift app's String Catalog
and `scripts/gen-strings.py` are not part of this artifact.

## Verification

Tests are not requested for this project (owner mandate). Verification is
static plus the manual matrix below.

Static checks (run from the repository root):

```sh
for f in extension/src/*.js extension/ui/*.js; do node --check "$f"; done
python3 -m json.tool extension/manifest.json
python3 -m json.tool extension/_locales/en/messages.json
python3 -m json.tool extension/_locales/ru/messages.json
python3 -m json.tool design/copy.json
python3 scripts/gen-extension-strings.py
xcodegen generate && ./scripts/build.sh   # macOS app must stay green
```

Manual matrix (Chrome, unpacked extension; results are recorded per release).
An automated smoke run on 2026-11-21 used a throwaway CDP harness (not part of
this repository) with Chrome for Testing 156, a local HTTPS IP mock and a test
copy of the manifest that statically granted two `example.com` hosts and
`127.0.0.1`; **51/51 checks passed**. The harness drove the real service
worker, rules, blocked page, popup and options page, including a config change
during a slow check and a damaged config. Interactive
permission prompts and split incognito mode remain manual.

| # | Scenario | Expected | Status |
| --- | --- | --- | --- |
| 1 | Trusted IP added, listed domain opens | site opens, no rules | PASS (smoke) |
| 2 | Endpoint answering an untrusted IP, listed domain opens | blocked page; subresources blocked | PASS (smoke: untrusted list; mock optional) |
| 3 | Endpoint returns a non-IPv4 body | `unknown`, blocked page | PASS (smoke) |
| 4 | Browser restart with an untrusted verdict | rules active immediately; still blocked after the fresh check | PASS (smoke) |
| 5 | Master off / on | all listed domains open / block again | PASS (smoke) |
| 6 | Empty trusted list | blocked with setup reason; Add current IP opens the gate | PASS (smoke) |
| 7 | Subdomain of a listed domain | blocked | PASS (smoke) |
| 8 | Page already in HTTP cache | blocked (DNR applies before cache) | PASS (smoke: after restart) |
| 9 | Add domain, deny Chrome prompt | domain not added, error shown | NOT RUN — needs the interactive prompt |
| 10 | Remove domain | its host permission and rules are removed | PARTIAL (smoke: rules removed; permission removal not observable in the test manifest) |
| 11 | Background check on / off | alarm created / cleared; one-shot checks still work | PASS (smoke) |
| 12 | Cold service-worker start after a trusted verdict | rules stay until the fresh check | PASS (smoke: rules present on cold start) |
| 13 | Config replaced while a check is in flight | old verdict never applied; rules never removed under the new config | PASS (smoke: stale check discarded, rules stayed) |
| 14 | Damaged stored config | settings locked, rules untouched, Save rejected; repair + reload unlocks | PASS (smoke) |
| 15 | Guarded tab open; the tab path and the service-worker path would get different endpoint answers | verdict comes from the tab-context check; with no listed tab the service-worker check decides | PASS (throwaway CDP harness 2026-11-24: 5/5) |
| 16 | Active visible listed tab; listed tab in the background; active tab not listed | heartbeat checks about every 2 s; a background listed tab and a non-listed active tab make no automatic request (the 30 s alarm also requires an active listed tab) | PASS (throwaway CDP harness 2026-11-24) |
| 17 | Main endpoint fails or returns an invalid body; fallback returns a trusted IP; a valid untrusted IP appears on another endpoint | rotation uses the next endpoint; the first valid IPv4 is final; an untrusted address is not retried elsewhere; all attempts fail → `unknown`/closed; the in-tab check skips non-CORS presets | PASS (throwaway Node + CDP harness 2026-11-24) |

To test the IP change without changing networks, point the endpoint at an HTTPS
mock that returns a fixed untrusted address (for example a local server with a
certificate Chrome trusts) and use **Check now**.

## Privacy

Config and state stay in `chrome.storage.local`. No telemetry, accounts, or
auto-update. The only outbound requests are the configured HTTPS IP-check
endpoints: the main endpoint plus any fallbacks you add. Each enabled endpoint
sees your IP; when the check runs from an open listed tab, Chrome also sends
that tab's origin in the `Origin` header and the extension suppresses the
`Referer`. The visible-tab heartbeat only asks for that same check; it sends
no data of its own. Diagnostics are not uploaded anywhere.