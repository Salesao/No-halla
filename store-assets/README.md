# No-halla Gate — store listing assets

Generated from the real extension UI and CSS, with the browser API mocked only
for storage/messages. The artwork uses `design/exports/gate-scene.png`, the app
icon and the existing design tokens. No extension file is changed by this
directory.

Generated 2026-11-22. Every image is PNG24 (no alpha) unless noted.

## Chrome Web Store

| Field | File | Size |
| --- | --- | --- |
| Store icon | `icons/no-halla-gate-128.png` | 128×128 (with alpha) |
| Screenshots (EN) | `chrome/en/1-protected-1280x800.png` … `4-unknown-1280x800.png` | 1280×800 |
| Screenshots (RU) | `chrome/ru/1-protected-1280x800.png` … `4-unknown-1280x800.png` | 1280×800 |
| Small promo tile (EN) | `chrome/small-promo-en.png` | 440×280 |
| Small promo tile (RU) | `chrome/small-promo-ru.png` | 440×280 |
| Marquee (EN) | `chrome/marquee-promo-en.png` | 1400×560 |
| Marquee (RU) | `chrome/marquee-promo-ru.png` | 1400×560 |

Chrome accepts 1280×800 or 640×400 screenshots, at least one and up to five.
The promo tile and marquee are optional. Upload the EN or RU set to match the
listing language; the four screenshots are ordered as a story.

## Firefox AMO

| Field | File | Size |
| --- | --- | --- |
| Icon | `icons/no-halla-gate-128.png` | 128×128 |
| Screenshots (EN) | `firefox/en/1-protected-1280x800.png` … `4-unknown-1280x800.png` | 1280×800 |
| Screenshots (RU) | `firefox/ru/1-protected-1280x800.png` … `4-unknown-1280x800.png` | 1280×800 |

AMO recommends 1280×800 (1.6:1) and allows up to ten images. The Firefox set
uses Firefox-specific copy (`about:addons`, “Firefox asks for access…”, the
Firefox alarm wording and the Firefox leak note); the Chrome set uses Chrome
wording. Do not mix the sets.

## What each screenshot shows

1. **Protected** — popup with a trusted IP, three listed domains, master switch,
   current IP, trusted count and last check.
2. **Blocked page** — a listed site replaced by the packaged block page, with
   the reason, current IP, last check and “Check again”.
3. **Settings** — domains, trusted IPv4/CIDR addresses, endpoint, language and
   the optional background check.
4. **Unknown** — fail-closed status when the IP check fails: listed domains
   stay blocked.

Sample domains (`linear.app`, `notion.so`, `figma.com`) and addresses
(`203.0.113.7`, `198.51.100.24`, `198.51.100.0/24`) are neutral examples from
the documentation ranges.

## Regenerate

The builder uses the real `extension/` and `extension-firefox/` pages and
locales, serves them locally, and captures with headless Chrome:

```sh
python3 -m http.server 8765 --bind 127.0.0.1
node store-assets/build.mjs
```

`build.mjs` writes the mock pages, presets and scenes under `store-assets/src/`,
the intermediate captures under `store-assets/src/renders/`, the final PNGs,
and `store-assets/manifest.json` with dimensions and SHA-256 hashes.
`/opt/homebrew/bin/magick` and Google Chrome are required.

The Orca embedded-browser screenshot path was tried first and returned
`CDP error (Page.captureScreenshot): Screenshot timed out — the browser page did
not draw a frame`; the deterministic headless-Chrome path above replaced it.

## Listing copy

Use `store-assets/listing-copy.md` for the short and long descriptions in EN/RU,
category/tag suggestions and the privacy note.