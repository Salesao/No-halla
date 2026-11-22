# No-halla Gate — listing copy

## Chrome Web Store

**Name:** No-halla Gate

**Short description (EN, ≤132):**
Blocks the domains you list when your public IPv4 is untrusted. Fail-closed, per-domain access, no telemetry.

**Short description (RU, ≤132):**
Блокирует домены из списка, когда публичный IPv4 не доверенный. Fail-closed, доступ по доменам, без телеметрии.

**Category:** Privacy & Security

**Detailed description (EN):**

No-halla Gate blocks the domains you choose whenever your public IPv4 address is not in your trusted list. It is a standalone browser extension; the macOS No-halla app is not required.

- Pick the domains to protect. The extension asks for access to each domain separately.
- Trust IPv4 addresses or CIDR ranges, and add the current IP with one click.
- Fail-closed: if the IP check fails, listed domains stay blocked.
- See the verdict, current IP, trusted count and last check in the popup.
- Optional background check, off by default; one-shot checks still run on startup and from the popup.
- English and Russian UI with light, dark and high-contrast design tokens.

Settings and the last verdict stay in browser storage. The only outbound request is the configured HTTPS IP-check endpoint.

Honest limits: the first request after an IP change can still reach a site; an already-cached PWA may continue from its own cache; other extensions can override the block; private windows require explicit permission; disabling the extension removes all rules.

**Detailed description (RU):**

No-halla Gate блокирует выбранные домены, когда публичный IPv4-адрес не входит в доверенный список. Это самостоятельное расширение браузера; macOS-приложение No-halla не требуется.

- Выберите домены для защиты. Доступ запрашивается отдельно для каждого домена.
- Доверяйте IPv4-адресам или CIDR-диапазонам; текущий IP добавляется одной кнопкой.
- Fail-closed: если проверка IP не удалась, домены из списка остаются заблокированными.
- В popup видны вердикт, текущий IP, число доверенных адресов и время последней проверки.
- Опциональная фоновая проверка выключена по умолчанию; разовые проверки работают при старте и из popup.
- Интерфейс EN/RU, токены светлой, тёмной и контрастной темы.

Настройки и последний вердикт хранятся в браузере. Единственный внешний запрос — настроенный HTTPS-эндпоинт проверки IP.

Честные ограничения: первый запрос после смены IP может ещё дойти до сайта; уже закэшированное PWA может работать из своего кэша; другие расширения могут перебить блокировку; для приватных окон нужно явное разрешение; отключение расширения удаляет все правила.

## Firefox AMO

**Name:** No-halla Gate

**Summary (EN, ≤250):**
Blocks a list of domains when your public IPv4 is untrusted or unverifiable. Fail-closed, per-domain access, local settings, EN/RU.

**Summary (RU, ≤250):**
Блокирует список доменов, когда публичный IPv4 не доверенный или не проверяется. Fail-closed, доступ по доменам, локальные настройки, EN/RU.

**Categories:** Privacy & Security
**Tags:** security, privacy, ip, domains, blocking

**Description (EN):**

No-halla Gate is a standalone Firefox extension that blocks the domains you list whenever your public IPv4 address is not in your trusted list.

- Add domains; Firefox asks for access to each domain.
- Trust IPv4 addresses or CIDR ranges; add the current IP from the popup or settings.
- Fail-closed: if the IP check fails, listed domains stay blocked.
- Popup status, current IP, trusted count, last check and domain management.
- Optional background check (off by default); one-shot checks on startup and from the UI.
- English and Russian; package-only assets; no telemetry.

The only outbound request is the configured HTTPS IP-check endpoint. Settings and the last verdict stay in `browser.storage.local`.

Honest limits: the first request after an IP change can still reach a site; an already-cached PWA may continue from its cache; other extensions can override the block; private windows require the extension to be allowed there; disabling the extension removes all rules.

**Description (RU):**

No-halla Gate — самостоятельное расширение Firefox, которое блокирует выбранные домены, когда публичный IPv4-адрес не входит в доверенный список.

- Добавьте домены; Firefox запросит доступ к каждому домену.
- Доверяйте IPv4-адресам или CIDR-диапазонам; текущий IP добавляется из popup или настроек.
- Fail-closed: если проверка IP не удалась, домены из списка остаются заблокированными.
- Статус, текущий IP, число доверенных адресов, последняя проверка и управление списком в popup.
- Опциональная фоновая проверка (по умолчанию выключена); разовые проверки при старте и из интерфейса.
- Интерфейс EN/RU; только ресурсы пакета; без телеметрии.

Единственный внешний запрос — настроенный HTTPS-эндпоинт проверки IP. Настройки и последний вердикт хранятся в `browser.storage.local`.

Честные ограничения: первый запрос после смены IP может ещё дойти до сайта; уже закэшированное PWA может работать из своего кэша; другие расширения могут перебить блокировку; для приватных окон расширение должно быть разрешено; отключение расширения удаляет все правила.

## Privacy note (both stores)

Config, domain list and the last verdict are stored locally. The only outbound
request is the configured HTTPS IP-check endpoint (`https://ipinfo.io/ip` by
default); the endpoint sees the source IP of that request, as any HTTPS server
does. No browsing history, domain list, account data or telemetry is sent. The
extension declares `data_collection_permissions.required: ["none"]` in the
Firefox manifest.

If AMO asks for a data-collection category, explain the plain GET: no query,
no custom headers, no body, and the returned address stays in local storage.
The fallback category, if AMO insists, is `locationInfo` (owner decision).

## Chrome Web Store — Privacy practices (English)

Use these texts in the Chrome Web Store dashboard under **Privacy practices**.

### Single purpose

```text
No-halla Gate blocks a user-defined list of domains whenever the current public IPv4 address is not in the user's trusted IPv4/CIDR list.
```

### Permission justifications

**`declarativeNetRequest`**

```text
Used to block the domains the user has explicitly added. For each listed domain, dynamic rules redirect top-level pages and iframes to a packaged block page and block subresources when the last IP verdict is untrusted or unknown. Rules are built only from the user's own domain list; the extension never blocks arbitrary sites. After every update the applied rule IDs are read back and verified.
```

**`webRequest`**

```text
Used for observation only, never for blocking. It watches requests to domains the user explicitly added so a trust check starts when a listed site is opened. The filter contains only those domains and their subdomains. No request bodies or headers are read, no requests are modified, and unrelated browsing traffic is never observed.
```

**`storage`**

```text
Stores the user's configuration and UI state locally: domain list, trusted IPv4/CIDR addresses, IP-check endpoint, language, optional background-check settings, and the last verdict/IP. Data stays in chrome.storage.local; it is not synced and is not sent to the developer.
```

**`alarms`**

```text
Runs the optional background IP check at the interval chosen by the user. Background checking is off by default and no alarm is created unless the user enables it. The alarm is cleared when the user turns the setting off or disables protection.
```

**`activeTab`**

```text
Grants temporary access to the active tab URL only after the user clicks the toolbar icon, so the popup's "Add current site" control can suggest the current domain. It is not used to read browsing history or other tabs.
```

**Host permission `https://ipinfo.io/*`**

```text
The default IP-check endpoint, https://ipinfo.io/ip, returns the public IPv4 address as plain text. The extension performs a GET with no credentials, cache disabled, redirects rejected, and a 2.5-second timeout. Users can configure a different HTTPS endpoint; the extension then requests permission for that origin at runtime.
```

**Optional host permission `*://*/*`**

```text
Declared only to make per-domain permission prompts possible. No site access is granted at install. When the user adds a domain, the extension requests access to that domain and its subdomains; the grant is removed when the domain is removed. The extension never requests all-site access on its own.
```

### Remote code

```text
No. All JavaScript, HTML, CSS, locale files, and icons are packaged in the extension. There is no eval, no remote script loading, and no dynamically fetched executable code.
```

### Data usage

```text
The extension does not collect, sell, or share user data with the developer. Settings and the last verdict remain in chrome.storage.local. The only outbound request is the configured HTTPS IP-check endpoint; that server sees the request's source IP, as any HTTPS server does. The returned IPv4 address is matched and stored locally. No analytics, accounts, telemetry, browsing history, or domain list is transmitted.
```

### Reviewer test instructions

```text
1. Open the extension settings and click "Add current IP".
2. Add a domain such as example.com and allow the per-domain access prompt.
3. Click "Check now" in the popup.
4. To see the blocked page, remove the trusted IP or configure an HTTPS mock endpoint that returns an untrusted IPv4 address.
No account or credentials are required.
```