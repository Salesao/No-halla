# No-halla Gate for Firefox

A standalone Firefox extension (Manifest V3) that blocks a list of domains when
your **public IPv4 address** is not in your trusted list. It is a separate
artifact next to the macOS No-halla app: the app is not required, is not
modified by the extension, and does not read or write the extension state.

This is the Firefox port of the Chrome artifact in `extension/`. Behavior,
storage schema, fail-closed policy, and UI are the same; the platform layer
uses Firefox event pages, `browser.*` promise APIs, and Firefox DNR rules.

- Minimum Firefox: **140** (MV3 event page with an ES-module background,
  `optional_host_permissions`, and the built-in data-collection declaration)
- Vanilla JavaScript ES modules; no build step, no npm dependencies
- English / Russian UI, light / dark / high-contrast design tokens
- All outbound traffic is limited to the configured HTTPS IP-check endpoint

## Install

### Temporary (development)

1. Open `about:debugging#/runtime/this-firefox`.
2. Choose **Load Temporary Add-on…** and select
   `extension-firefox/manifest.json` (or any file in the directory).
3. The add-on stays loaded until Firefox restarts. **Reload** re-reads the
   manifest and permissions.

### Signed (permanent)

AMO signing is required for permanent installation outside Developer Edition /
Nightly with signature checks disabled. Manifest V3 requires the fixed add-on
ID declared in `browser_specific_settings.gecko.id` (`gate@nohalla.dev`).

- **Listed (public AMO listing):** upload a zip of `extension-firefox/` at
  <https://addons.mozilla.org/developers/>, or run
  `web-ext sign --api-key=… --api-secret=… --channel=listed`. Listed versions
  get automatic updates through AMO.
- **Unlisted (self-distribution):** the same flow with `--channel=unlisted`.
  Updates for a self-distributed XPI need an `update_url`, or the next version
  can be submitted to AMO for signing.
- AMO accepts a plain `.zip`; `web-ext` is optional. If you use it, build the
  archive from the `extension-firefox/` directory so `manifest.json` is at the
  zip root.

The extension is not published in the Chrome Web Store and has no Chrome
build output.

## First run

1. Open the extension settings (toolbar icon → **Settings**, or
   `about:addons` → No-halla Gate → Preferences).
2. Click **Add current IP** to trust the IP you are on now.
3. Add the domains you want to protect. Firefox asks for access to each
   domain; allow it. Denying the prompt leaves the domain out of the list and
   shows a short error.

The toolbar popup shows the same domain list and can add or remove domains.
Adding a domain asks Firefox for site access directly from the popup. If
Firefox closes the popup while the prompt is visible, the grant is still picked
up by the background event page and the domain is saved. The popup also has an
**Add current IP** control and an **Add current site** control that adds the
domain of the active tab.

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
abort controller.

**When a check runs.**

- When a request to a listed domain is observed (`browser.webRequest` watches
  only the domains in the list; at most one check every 3 s, in-flight checks
  are deduplicated).
- On browser startup and extension install/update.
- On **Check now** and on the blocked page.
- Optionally, in the background. **Background check is off by default.** When
  enabled, an alarm runs at the chosen interval. Firefox does not clamp the
  interval; `periodInMinutes` is passed to the platform timer as-is. Firefox
  may still delay an alarm while the browser is busy or asleep, and alarms do
  not survive a browser restart — the background page recreates the alarm on
  every cold start. Off is the owner's decision: the extension checks when you
  actually open a listed site.

**Blocking.** Declarative Net Request dynamic rules are built per domain:

- navigation and frames → redirect to the packaged blocked page;
- every other resource type → blocked.

`requestDomains` covers the domain and its subdomains. The redirect target is
an absolute `moz-extension://…/ui/blocked.html?domain=…` URL: Firefox has no
`redirect.extensionPath` query strings, and the query keeps the blocked domain
visible even when Firefox redirects before `webRequest` observes the
navigation. When the gate closes (or a blocked domain is added), already-open
tabs of listed domains are reloaded once so an SPA cannot keep running from its
in-memory state; the reload hits the redirect rule and shows the blocked page.
Rules are verified with `getDynamicRules()` after every update. If the update
is rejected or the verification does not match, the extension reports
`unknown`/degraded and never claims trust. Rules persist across browser
restarts and extension updates. Firefox allows 5,000 dynamic rules; the
500-domain cap produces at most 1,000.

**Fail-closed start.** On every background-page start the rule state is
`unknown` even if the stored last verdict says `trusted`. Rules stay installed
(or are installed) until a fresh check proves trust and their removal is
verified. A damaged config never removes rules.

**Master switch off** removes every rule. Turning it back on re-checks.
**Empty trusted list** means nothing is trusted: listed domains are blocked
with the setup reason until you add an address.

## Permissions

| Permission | Why |
| --- | --- |
| `declarativeNetRequest` | dynamic block/redirect rules; block stays active even if a later site grant is revoked |
| `webRequest` | observe requests to listed domains only (no blocking, no request bodies) |
| `storage` | config and UI state in `browser.storage.local` |
| `alarms` | the optional background check |
| `activeTab` | read the active tab URL when you click the toolbar icon, for **Add current site** |

No `notifications`, no `webRequestBlocking`, no `<all_urls>` in
`host_permissions`. Host access is requested per domain when you add it, plus
the IP-check endpoint origin. The manifest declares
`optional_host_permissions` as a pattern so those per-domain prompts are
possible; at install only the default endpoint origin (`https://ipinfo.io/*`)
is granted, and no site access is.

`declarativeNetRequest` is used instead of the Firefox-specific
`declarativeNetRequestWithHostAccess`. Firefox requires host access for the
frame redirect either way, but only the plain permission lets `block` rules act
without it. If a site grant is revoked later in `about:addons`, observation and
the redirect stop for that domain, yet subresource blocking keeps working
instead of failing open. Frame redirects still require the per-domain grant
that the extension requests when the domain is added. Firefox lists
`declarativeNetRequest` in the install prompt; the generated rules only match
the domains you add, never every site.

`web_accessible_resources` matches all sites only so the blocked page can be
loaded after a redirect for any listed domain; it grants no network access.
Firefox has no `use_dynamic_url`, so the `moz-extension://` URL is stable for
the lifetime of the profile.

## Firefox data-collection declaration

Firefox 140+ shows the built-in data-collection consent from
`browser_specific_settings.gecko.data_collection_permissions`. The manifest
declares `required: ["none"]`: the extension does not send any data payload to
its author or a third party, and it has no telemetry, accounts, analytics, or
crash reporting.

The configured IP-check endpoint necessarily sees the source IP of its own
HTTPS request, as any request to that server does. The returned address is
matched against the trusted list and stored in `browser.storage.local` inside
the browser; it is not sent anywhere else. The default endpoint is
`https://ipinfo.io/ip`; changing it changes which third party sees the request.
This is documented in the Privacy section and should be restated in the AMO
submission notes.

## Honest limits

1. **The first request can leak.** A browser extension cannot see a
   connection's IP before it is made. After the public IP changes, the first
   request to a listed domain may still reach the site; the check it triggers
   blocks the rest. "Never a single request" is not achievable.
2. **No background check by default.** If the IP changes while you are not
   opening listed sites, nothing detects it until the next listed request,
   browser start, popup open, or "Check now".
3. **Firefox event pages sleep.** Firefox stops the background page after
   inactivity. Listed-domain requests, alarms, and UI messages wake it; a check
   cannot run while it is asleep.
4. **Event-page and CacheStorage responses** are not covered by DNR. An
   already-cached PWA can keep working from its own cache. Navigation and new
   requests are covered, including the normal HTTP cache.
5. **Already-received responses** cannot be recalled.
6. **Endpoint failure blocks.** If the endpoint is down, rate-limited, or
   returns something other than a plain IPv4, the verdict is `unknown` and the
   gate stays closed. Change the endpoint or add the current IP.
7. **Other extensions can override the block.** An `allow` rule wins over
   `block`, and Firefox resolves conflicting rules across extensions by its own
   precedence rules. This cannot be detected by the extension.
8. **Private windows.** Private windows are protected only if the extension is
   allowed there. Enable it in `about:addons` → No-halla Gate → **Details** →
   **Run in Private Windows** → **Allow**. Firefox has no API to do this from
   the extension. Firefox private windows share the same extension instance.
9. **Dual-stack and TLS interception.** The endpoint may answer over IPv6 while
   site traffic uses IPv4 (different egress), or a corporate proxy with a
   trusted root CA may rewrite the answer. Both can produce a false `trusted`.
   The macOS app has the same limit; one endpoint is used by owner decision.
10. **Disabling the extension** (user or enterprise policy) removes all rules
    immediately. There is no protection outside Firefox.

## Files

```
manifest.json          MV3 manifest (Firefox keys, gecko id, event page)
src/browser.js         `browser.*` namespace wrapper
src/cidr.js            strict IPv4/CIDR parse + match
src/config.js          storage schema, validation, state
src/trust.js           endpoint fetch -> verdict
src/rules.js           DNR rule builder, reconcile, verification
src/background.js      event page: orchestration, triggers, messages, alarms
src/i18n.js            locale loading, t(), document localization
ui/tokens.css          design tokens (light/dark/contrast)
ui/popup.*             status popup
ui/options.*           settings
ui/blocked.*           redirect target (package-only assets)
_locales/{en,ru}/      generated from design/copy.json (gate.* keys)
localization-overrides.json  Firefox-only copy variants
icons/                 16/32/48/128 PNG
README.md, README.ru.md
```

## Localization

`design/copy.json` is the repository's single shared copy source and is not
modified by this artifact. `scripts/gen-firefox-strings.py` reads its `gate.*`
keys, applies `extension-firefox/localization-overrides.json` (Firefox prompt
wording, Firefox alarm behavior, Firefox leak note), and writes
`extension-firefox/_locales/{en,ru}/messages.json`. The override file holds
only browser-specific variants; every other string comes from the shared
source. The generator fails on an unknown override key, a missing or empty
EN/RU value, a named placeholder, or a duplicate message name.

```sh
python3 scripts/gen-firefox-strings.py
```

Do not edit `_locales/*/messages.json` by hand. `scripts/gen-extension-strings.py`
(the Chrome artifact) and the Swift String Catalog are separate and untouched.

## Verification

Tests are not requested for this project (owner mandate). Verification is
static plus a manual matrix.

Static checks (run from the repository root):

```sh
for f in extension-firefox/src/*.js extension-firefox/ui/*.js; do node --check "$f"; done
python3 -m json.tool extension-firefox/manifest.json
python3 -m json.tool extension-firefox/localization-overrides.json
python3 -m json.tool extension-firefox/_locales/en/messages.json
python3 -m json.tool extension-firefox/_locales/ru/messages.json
python3 scripts/gen-firefox-strings.py   # idempotent
```

Manual matrix (Firefox, temporary add-on). Results are recorded per release;
runtime checks are not part of this repository's automated verification.

| # | Scenario | Expected |
| --- | --- | --- |
| 1 | Trusted IP added, listed domain opens | site opens, no rules |
| 2 | Endpoint answering an untrusted IP, listed domain opens | blocked page; subresources blocked |
| 3 | Endpoint returns a non-IPv4 body | `unknown`, blocked page |
| 4 | Browser restart with an untrusted verdict | rules active immediately; still blocked after the fresh check |
| 5 | Master off / on | all listed domains open / block again |
| 6 | Empty trusted list | blocked with setup reason; Add current IP opens the gate |
| 7 | Subdomain of a listed domain | blocked |
| 8 | Page already in HTTP cache | blocked (DNR applies before cache) |
| 9 | Add domain, deny the Firefox prompt | domain not added, error shown |
| 10 | Remove domain | its host permission and rules are removed |
| 11 | Background check on / off | alarm created / cleared; one-shot checks still work |
| 12 | Background page restart after a trusted verdict | rules stay until the fresh check |
| 13 | Config replaced while a check is in flight | old verdict never applied; rules never removed under the new config |
| 14 | Damaged stored config | settings locked, rules untouched, Save rejected; repair + reload unlocks |
| 15 | Check again on the blocked page with a newly trusted IP | navigates back to the original URL |
| 16 | Private window with the add-on not allowed there | documented limitation: no protection there |

To test the IP change without changing networks, point the endpoint at an HTTPS
mock that returns a fixed untrusted address (for example a local server with a
certificate Firefox trusts) and use **Check now**.

## Privacy

Config and state stay in `browser.storage.local` inside the Firefox profile. No
telemetry, accounts, analytics, or auto-update. The only outbound request is
the configured HTTPS IP-check endpoint; the extension stores the returned
address locally and never includes browsing data, domain lists, or identifiers
in that request. The endpoint sees the request's source IP, as it would for any
HTTPS client.