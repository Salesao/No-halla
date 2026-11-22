#!/usr/bin/env node
// Build listing assets for No-halla Gate from the real extension UI.
// No npm dependencies. Renders mock extension pages through the local extension
// CSS/JS, then composes store screenshots and banners with headless Chrome.
//
// Prerequisite: a static server for the repo root on 127.0.0.1:8765
//   python3 -m http.server 8765 --bind 127.0.0.1
// Run: node store-assets/build.mjs

import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import {
  copyFileSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const OUT = join(ROOT, "store-assets");
const SRC = join(OUT, "src");
const RENDERS = join(SRC, "renders");
const CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const MAGICK = "/opt/homebrew/bin/magick";
const BASE = "http://127.0.0.1:8765";
const NOW = Date.UTC(2026, 10, 22, 9, 30, 0);
const LANGS = ["en", "ru"];

const BUILDS = {
  chrome: {
    dir: "extension",
    label: "Chrome",
    browseUrl: "chrome://extensions",
    icon: join(ROOT, "extension", "icons", "icon128.png"),
  },
  firefox: {
    dir: "extension-firefox",
    label: "Firefox",
    browseUrl: "about:addons",
    icon: join(ROOT, "extension-firefox", "icons", "icon128.png"),
  },
};

const SCENES = [
  {
    id: "1-protected",
    shot: "popup-protected",
    kind: "popup",
    theme: "light",
    shotW: 360,
    shotH: 660,
    page: "popup",
    preset: "protected",
  },
  {
    id: "2-blocked",
    shot: "blocked",
    kind: "browser",
    theme: "dark",
    shotW: 700,
    shotH: 520,
    page: "blocked",
    preset: "blocked",
    url: "https://linear.app/workspace",
  },
  {
    id: "3-settings",
    shot: "options",
    kind: "browser",
    theme: "light",
    shotW: 680,
    shotH: 660,
    page: "options",
    preset: "options",
    urlKey: "browse",
  },
  {
    id: "4-unknown",
    shot: "popup-unknown",
    kind: "popup",
    theme: "dark",
    shotW: 360,
    shotH: 660,
    page: "popup",
    preset: "unknown",
  },
];

const COPY = {
  en: {
    "1-protected": {
      kicker: "STATUS AT A GLANCE",
      title: "Your IP is trusted.<br>The gate is open.",
      lede: "No-halla Gate blocks the sites you list whenever your public IPv4 address is not in your trusted list.",
      chips: ["IPv4 / CIDR", "Per-domain access", "EN / RU"],
    },
    "2-blocked": {
      kicker: "FAIL-CLOSED BY DESIGN",
      title: "The gate stays closed.",
      lede: "When your IP is untrusted or cannot be verified, listed sites do not load. No silent bypass.",
      chips: ["Frames redirected", "Subresources blocked", "No telemetry"],
    },
    "3-settings": {
      kicker: "YOUR LIST, YOUR RULES",
      title: "Choose exactly what is protected.",
      lede: "Domains, trusted addresses, endpoint, language and the optional background check stay in your browser.",
      chips: ["500 domains", "64 trusted addresses", "Local storage"],
    },
    "4-unknown": {
      kicker: "NO ANSWER MEANS BLOCKED",
      title: "Unknown is not trusted.",
      lede: "If the IP check fails, the status turns to “Can’t verify IP” and listed domains stay blocked.",
      chips: ["Fail-closed", "No false trusted", "Check again"],
    },
    small: {
      brand: "NO-HALLA GATE",
      title: "The gate stays closed.",
      lede: "Blocks listed sites when your public IP is untrusted.",
    },
    marquee: {
      kicker: "FAIL-CLOSED DOMAIN BLOCKING",
      title: "Listed sites close when your IP is untrusted.",
      lede: "A standalone extension for Firefox and Chrome. One HTTPS IP check, per-domain access, no telemetry.",
      chips: ["IPv4 / CIDR", "Per-domain access", "EN / RU"],
    },
  },
  ru: {
    "1-protected": {
      kicker: "СТАТУС ВСЕГДА НА ВИДУ",
      title: "Ваш IP доверенный.<br>Ворота открыты.",
      lede: "No-halla Gate блокирует сайты из списка, когда публичный IPv4-адрес не входит в доверенный список.",
      chips: ["IPv4 / CIDR", "Доступ по домену", "EN / RU"],
    },
    "2-blocked": {
      kicker: "FAIL-CLOSED ПО УМОЛЧАНИЮ",
      title: "Ворота остаются закрытыми.",
      lede: "Если IP недоверенный или проверка не удалась, сайты из списка не загружаются. Тихих обходов нет.",
      chips: ["Фреймы перенаправляются", "Сабресурсы блокируются", "Без телеметрии"],
    },
    "3-settings": {
      kicker: "ВАШ СПИСОК — ВАШИ ПРАВИЛА",
      title: "Выберите, что защищать.",
      lede: "Домены, доверенные адреса, эндпоинт, язык и фоновая проверка остаются в браузере.",
      chips: ["500 доменов", "64 адреса", "Локальное хранилище"],
    },
    "4-unknown": {
      kicker: "НЕТ ОТВЕТА — ЗНАЧИТ БЛОКИРОВКА",
      title: "Неизвестный IP не считается доверенным.",
      lede: "Если проверка IP не удалась, статус «Не удаётся проверить IP», а домены из списка остаются заблокированными.",
      chips: ["Fail-closed", "Без ложного доверия", "Проверить снова"],
    },
    small: {
      brand: "NO-HALLA GATE",
      title: "Ворота остаются закрытыми.",
      lede: "Блокирует сайты из списка, когда публичный IP не доверенный.",
    },
    marquee: {
      kicker: "FAIL-CLOSED БЛОКИРОВКА ДОМЕНОВ",
      title: "Сайты из списка закрываются, когда IP не доверенный.",
      lede: "Самостоятельное расширение для Firefox и Chrome. Одна HTTPS-проверка IP, доступ по доменам, без телеметрии.",
      chips: ["IPv4 / CIDR", "Доступ по домену", "EN / RU"],
    },
  },
};

function ensureDir(path) {
  mkdirSync(path, { recursive: true });
}

function writeFile(path, content) {
  ensureDir(dirname(path));
  writeFileSync(path, content);
}

function run(command, args) {
  execFileSync(command, args, { stdio: "ignore" });
}

function makeConfig(lang, overrides = {}) {
  return {
    schemaVersion: 1,
    enabled: true,
    domains: ["linear.app", "notion.so", "figma.com"],
    trustedAddresses: ["203.0.113.7"],
    endpoint: "https://ipinfo.io/ip",
    language: lang,
    backgroundCheck: false,
    backgroundIntervalSeconds: 30,
    ...overrides,
  };
}

const PRESETS = {};
for (const lang of LANGS) {
  PRESETS[`protected-${lang}`] = {
    config: makeConfig(lang),
    state: { lastVerdict: "trusted", lastIP: "203.0.113.7", lastCheckAt: NOW, degraded: false },
    checkVerdict: "trusted",
    checkIP: "203.0.113.7",
    uiLanguage: lang,
  };
  PRESETS[`blocked-${lang}`] = {
    config: makeConfig(lang),
    state: { lastVerdict: "untrusted", lastIP: "198.51.100.24", lastCheckAt: NOW, degraded: false },
    checkVerdict: "untrusted",
    checkIP: "198.51.100.24",
    blockedDomain: "linear.app",
    blockedUrl: "https://linear.app/workspace",
    uiLanguage: lang,
  };
  PRESETS[`unknown-${lang}`] = {
    config: makeConfig(lang),
    state: { lastVerdict: "unknown", lastIP: null, lastCheckAt: NOW, degraded: false },
    checkVerdict: "unknown",
    checkIP: null,
    uiLanguage: lang,
  };
  PRESETS[`options-${lang}`] = {
    config: makeConfig(lang, {
      trustedAddresses: ["203.0.113.7", "198.51.100.0/24"],
      backgroundCheck: true,
      backgroundIntervalSeconds: 60,
    }),
    state: { lastVerdict: "trusted", lastIP: "203.0.113.7", lastCheckAt: NOW, degraded: false },
    checkVerdict: "trusted",
    checkIP: "203.0.113.7",
    uiLanguage: lang,
  };
}

writeFile(
  join(SRC, "presets.js"),
  `window.MOCK_PRESETS = ${JSON.stringify(PRESETS, null, 2)};\n`
);

writeFile(
  join(SRC, "mock-browser.js"),
  `// Mock browser.* API for static listing screenshots. The extension UI and CSS
// are the real ones; only storage/message transport is replaced.
(function () {
  const presets = window.MOCK_PRESETS || {};
  const params = new URLSearchParams(location.search);
  const preset = presets[params.get("preset")] || presets["protected-en"];
  if (!preset) return;
  const build = location.pathname.includes("/extension-firefox/")
    ? "extension-firefox"
    : "extension";
  let config = JSON.parse(JSON.stringify(preset.config));
  let state = JSON.parse(JSON.stringify(preset.state));
  const copy = (value) => JSON.parse(JSON.stringify(value));
  const snapshot = (extra = {}) => ({
    ok: true,
    verdict: state.lastVerdict,
    ip: state.lastIP,
    degraded: state.degraded === true,
    state: copy(state),
    config: copy(config),
    configError: false,
    ...extra,
  });
  const respond = (message) => {
    const type = message && message.type;
    if (type === "getConfig") return { ok: true, config: copy(config), configError: false };
    if (type === "getState") {
      return snapshot({
        blockedDomain: preset.blockedDomain || null,
        blockedUrl: preset.blockedUrl || null,
      });
    }
    if (type === "checkNow") {
      if (typeof preset.checkVerdict === "string") {
        state = {
          ...state,
          lastVerdict: preset.checkVerdict,
          lastIP: preset.checkIP ?? null,
          lastCheckAt: Date.now(),
          degraded: false,
        };
      }
      return snapshot();
    }
    if (type === "saveConfig") {
      if (message.config && typeof message.config === "object") config = copy(message.config);
      return snapshot();
    }
    return { ok: false, error: "unknown-message" };
  };
  const api = {
    runtime: {
      getURL: (path) => \`/\${build}/\${String(path).replace(/^\\/+/, "")}\`,
      sendMessage: async (message) => respond(message),
      openOptionsPage: async () => {},
    },
    storage: {
      local: {
        get: async () => ({ gatePendingDomain: "" }),
        set: async () => {},
        remove: async () => {},
      },
    },
    tabs: { query: async () => [{ url: preset.activeUrl || "https://linear.app/" }] },
    permissions: { request: async () => true, remove: async () => {} },
    i18n: { getUILanguage: () => preset.uiLanguage || "en" },
  };
  window.browser = api;
  // The Chrome artifact calls chrome.* directly; the Firefox artifact uses
  // browser.*. Expose the same mock under both names.
  try {
    window.chrome = api;
  } catch (error) {
    // Chrome defines window.chrome on normal pages; patch its members.
    for (const key of Object.keys(api)) {
      try {
        window.chrome[key] = api[key];
      } catch (error2) {
        // Ignore a locked namespace.
      }
    }
  }
})();
`
);

function makeMockPages() {
  for (const buildKey of Object.keys(BUILDS)) {
    const build = BUILDS[buildKey];
    for (const page of ["popup", "options", "blocked"]) {
      let html = readFileSync(join(ROOT, build.dir, "ui", `${page}.html`), "utf8");
      html = html.replace("<head>", `<head>\n  <base href="/${build.dir}/ui/">`);
      const marker = new RegExp(`<script type="module" src="${page}\\.js"></script>`);
      if (!marker.test(html)) throw new Error(`module script not found in ${page}.html`);
      const injected = [
        '  <script src="/store-assets/src/presets.js"></script>',
        '  <script>window.MOCK = window.MOCK_PRESETS[new URLSearchParams(location.search).get("preset") || "protected-en"];</script>',
        '  <script src="/store-assets/src/mock-browser.js"></script>',
        `  <script type="module" src="${page}.js"></script>`,
      ].join("\n");
      html = html.replace(marker, injected);
      writeFile(join(SRC, build.dir, `${page}.html`), html);
    }
  }
}

function chromeShot(url, width, height, scale, output) {
  const profile = mkdtempSync(join(tmpdir(), "nohalla-store-"));
  try {
    run(CHROME, [
      "--headless=new",
      `--user-data-dir=${profile}`,
      "--no-first-run",
      "--disable-gpu",
      "--hide-scrollbars",
      `--force-device-scale-factor=${scale}`,
      `--window-size=${width},${height}`,
      "--virtual-time-budget=4500",
      `--screenshot=${output}`,
      url,
    ]);
  } finally {
    rmSync(profile, { recursive: true, force: true });
  }
  if (!existsSync(output)) throw new Error(`screenshot missing: ${output}`);
}

function flatten(input, output) {
  run(MAGICK, [input, "-alpha", "remove", "-alpha", "off", "-strip", `PNG24:${output}`]);
}

function trimPopup(input, output) {
  // Sample the page background so the restored padding matches the popup
  // theme (the UI follows prefers-color-scheme).
  const background = execFileSync(MAGICK, [
    input,
    "-format",
    "%[pixel:p{0,0}]",
    "info:",
  ])
    .toString()
    .trim();
  run(MAGICK, [
    input,
    "-trim",
    "+repage",
    "-bordercolor",
    background,
    "-border",
    "32",
    "-alpha",
    "remove",
    "-alpha",
    "off",
    "-strip",
    `PNG24:${output}`,
  ]);
}

function renderMockUi() {
  const sizes = {
    popup: [360, 900],
    options: [680, 660],
    blocked: [700, 520],
  };
  for (const buildKey of Object.keys(BUILDS)) {
    const build = BUILDS[buildKey];
    for (const lang of LANGS) {
      const jobs = [
        ["popup-protected", "popup", `protected-${lang}`],
        ["popup-unknown", "popup", `unknown-${lang}`],
        ["options", "options", `options-${lang}`],
        ["blocked", "blocked", `blocked-${lang}`],
      ];
      for (const [name, page, preset] of jobs) {
        const [width, height] = sizes[page];
        const query =
          page === "blocked"
            ? `?preset=${preset}&domain=linear.app`
            : `?preset=${preset}`;
        const raw = join(RENDERS, buildKey, `${name}-${lang}@2x.png`);
        const final = join(RENDERS, buildKey, `${name}-${lang}.png`);
        ensureDir(dirname(raw));
        chromeShot(
          `${BASE}/store-assets/src/${build.dir}/${page}.html${query}`,
          width,
          height,
          2,
          raw
        );
        if (page === "popup") trimPopup(raw, final);
        else flatten(raw, final);
        console.log(`mock ${buildKey}/${name}-${lang}`);
      }
    }
  }
}

function sceneUrl(buildKey, scene) {
  return scene.urlKey === "browse" ? BUILDS[buildKey].browseUrl : scene.url;
}

function sceneHtml(buildKey, lang, scene) {
  const build = BUILDS[buildKey];
  const copy = COPY[lang][scene.id];
  const shot = `/store-assets/src/renders/${buildKey}/${scene.shot}-${lang}.png`;
  const stage =
    scene.kind === "popup"
      ? `<div class="halo"></div><div class="popup"><img src="${shot}" alt=""></div>`
      : `<div class="window${scene.id === "3-settings" ? " window--fade" : ""}"><div class="bar"><span class="dots"><i></i><i></i><i></i></span><span class="addr">${sceneUrl(
          buildKey,
          scene
        )}</span></div><img src="${shot}" alt=""></div>`;
  const gate =
    scene.theme === "dark"
      ? `<img class="gate-bg" src="/design/exports/gate-scene.png" alt="">`
      : "";
  const chips = copy.chips.map((chip) => `<span class="chip">${chip}</span>`).join("");
  return `<!doctype html>
<html lang="${lang}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>No-halla Gate — ${scene.id}</title>
<link rel="stylesheet" href="/store-assets/src/scene.css">
</head>
<body class="theme-${scene.theme}">
${gate}
<div class="grid">
  <section class="copy">
    <div class="brand"><img src="/store-assets/icons/no-halla-gate-128.png" alt=""><span>No-halla Gate</span></div>
    <p class="kicker">${copy.kicker}</p>
    <h1>${copy.title}</h1>
    <p class="lede">${copy.lede}</p>
    <div class="chips">${chips}</div>
  </section>
  <section class="stage">${stage}</section>
</div>
<div class="foot">No-halla Gate · ${build.label} · github.com/Salesao/No-halla</div>
</body>
</html>
`;
}

function renderScenes() {
  for (const buildKey of Object.keys(BUILDS)) {
    for (const lang of LANGS) {
      for (const scene of SCENES) {
        const htmlPath = join(SRC, "scenes", buildKey, lang, `${scene.id}.html`);
        writeFile(htmlPath, sceneHtml(buildKey, lang, scene));
        const raw = join(RENDERS, buildKey, `${scene.id}-${lang}-raw.png`);
        const final = join(OUT, buildKey, lang, `${scene.id}-1280x800.png`);
        ensureDir(dirname(final));
        chromeShot(
          `${BASE}/store-assets/src/scenes/${buildKey}/${lang}/${scene.id}.html`,
          1280,
          800,
          1,
          raw
        );
        flatten(raw, final);
        console.log(`scene ${buildKey}/${lang}/${scene.id}`);
      }
    }
  }
}

function bannerHtml(lang, kind) {
  const copy = COPY[lang][kind];
  if (kind === "small") {
    return `<!doctype html><html lang="${lang}"><head><meta charset="utf-8">
<link rel="stylesheet" href="/store-assets/src/banner.css"></head>
<body class="small">
  <img class="gate" src="/design/exports/gate-scene.png" alt="">
  <div class="content">
    <div class="brand"><img src="/store-assets/icons/no-halla-gate-128.png" alt=""><span>${copy.brand}</span></div>
    <h1>${copy.title}</h1>
    <p>${copy.lede}</p>
    <div class="rule"></div>
  </div>
</body></html>`;
  }
  const chips = copy.chips.map((chip) => `<span class="chip">${chip}</span>`).join("");
  return `<!doctype html><html lang="${lang}"><head><meta charset="utf-8">
<link rel="stylesheet" href="/store-assets/src/banner.css"></head>
<body class="marquee">
  <img class="gate" src="/design/exports/gate-scene.png" alt="">
  <div class="content">
    <div class="brand"><img src="/store-assets/icons/no-halla-gate-128.png" alt=""><span>NO-HALLA GATE</span></div>
    <p class="kicker">${copy.kicker}</p>
    <h1>${copy.title}</h1>
    <p class="lede">${copy.lede}</p>
    <div class="chips">${chips}</div>
  </div>
</body></html>`;
}

function renderBanners() {
  for (const lang of LANGS) {
    for (const [kind, width, height] of [
      ["small", 440, 280],
      ["marquee", 1400, 560],
    ]) {
      const htmlPath = join(SRC, "banners", lang, `${kind}.html`);
      writeFile(htmlPath, bannerHtml(lang, kind));
      const raw = join(RENDERS, "banners", `${kind}-${lang}-raw.png`);
      const final = join(OUT, "chrome", `${kind}-promo-${lang}.png`);
      ensureDir(dirname(raw));
      ensureDir(dirname(final));
      chromeShot(
        `${BASE}/store-assets/src/banners/${lang}/${kind}.html`,
        width,
        height,
        1,
        raw
      );
      flatten(raw, final);
      console.log(`banner ${lang}/${kind}`);
    }
  }
}

function writeManifest() {
  const files = [];
  // Enumerate the known output folders without a recursive helper dependency.
  const paths = [];
  for (const buildKey of Object.keys(BUILDS)) {
    for (const lang of LANGS) {
      for (const scene of SCENES) {
        paths.push([join(OUT, buildKey, lang, `${scene.id}-1280x800.png`), 1280, 800]);
      }
    }
  }
  for (const lang of LANGS) {
    paths.push([join(OUT, "chrome", `small-promo-${lang}.png`), 440, 280]);
    paths.push([join(OUT, "chrome", `marquee-promo-${lang}.png`), 1400, 560]);
  }
  paths.push([join(OUT, "icons", "no-halla-gate-128.png"), 128, 128]);
  for (const [path, width, height] of paths) {
    if (!existsSync(path)) throw new Error(`missing output: ${path}`);
    files.push({
      path: path.slice(ROOT.length + 1),
      width,
      height,
      sha256: createHash("sha256").update(readFileSync(path)).digest("hex"),
    });
  }
  writeFile(
    join(OUT, "manifest.json"),
    `${JSON.stringify({ generatedAt: new Date().toISOString(), files }, null, 2)}\n`
  );
}

function copyIcons() {
  ensureDir(join(OUT, "icons"));
  copyFileSync(join(ROOT, "extension", "icons", "icon128.png"), join(OUT, "icons", "no-halla-gate-128.png"));
}

writeFile(
  join(SRC, "scene.css"),
  `/* Listing scenes for No-halla Gate. Brand colors mirror design/tokens.json. */
:root { --accent: #b5763a; --accent-light: #d9a066; }
* { box-sizing: border-box; }
html, body { width: 100%; height: 100%; margin: 0; overflow: hidden; }
body {
  position: relative;
  padding: 44px 56px;
  font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", "Helvetica Neue", Arial, sans-serif;
  background: var(--canvas);
  color: var(--ink);
}
body::before {
  content: "";
  position: absolute;
  inset: 0;
  pointer-events: none;
  background-image:
    linear-gradient(var(--grid) 1px, transparent 1px),
    linear-gradient(90deg, var(--grid) 1px, transparent 1px);
  background-size: 48px 48px;
  opacity: 0.32;
}
body.theme-light {
  --canvas: #f5f6fa;
  --ink: #182130;
  --muted: #515f72;
  --line: #d9e0eb;
  --panel: #ffffff;
  --grid: rgba(22, 50, 59, 0.055);
  background-image: radial-gradient(1100px 560px at 86% 6%, rgba(21, 87, 173, 0.07), transparent 62%);
}
body.theme-dark {
  --canvas: #0e1f26;
  --ink: #f2f5fa;
  --muted: #a9b8c4;
  --line: #2e4a52;
  --panel: #1c333d;
  --grid: rgba(232, 224, 208, 0.045);
  background-image: radial-gradient(1100px 620px at 82% 10%, rgba(181, 118, 58, 0.16), transparent 60%);
}
.grid {
  position: relative;
  z-index: 2;
  display: grid;
  grid-template-columns: 420px minmax(0, 1fr);
  gap: 44px;
  height: 100%;
  align-items: center;
}
.copy { max-width: 420px; }
.brand {
  display: flex;
  align-items: center;
  gap: 10px;
  margin-bottom: 30px;
  font-size: 14px;
  font-weight: 600;
  letter-spacing: 0.01em;
}
.brand img { width: 28px; height: 28px; border-radius: 7px; }
.kicker {
  margin: 0;
  padding-left: 12px;
  border-left: 2px solid var(--accent);
  color: var(--muted);
  font-size: 11px;
  font-weight: 600;
  letter-spacing: 0.15em;
  text-transform: uppercase;
}
h1 {
  margin: 18px 0 18px;
  font-size: 47px;
  line-height: 1.05;
  font-weight: 650;
  letter-spacing: -0.025em;
}
.lede {
  margin: 0;
  color: var(--muted);
  font-size: 16px;
  line-height: 1.55;
}
.chips { display: flex; flex-wrap: wrap; gap: 8px; margin-top: 28px; }
.chip {
  display: inline-flex;
  align-items: center;
  min-height: 28px;
  padding: 0 11px;
  border: 1px solid var(--line);
  border-radius: 999px;
  color: var(--muted);
  font-size: 10px;
  font-weight: 600;
  letter-spacing: 0.06em;
  text-transform: uppercase;
  background: color-mix(in srgb, var(--panel) 55%, transparent);
}
.stage {
  position: relative;
  display: flex;
  align-items: center;
  justify-content: center;
  height: 100%;
  min-width: 0;
}
.halo {
  position: absolute;
  width: 520px;
  height: 520px;
  border-radius: 50%;
  background: radial-gradient(circle, rgba(181, 118, 58, 0.18), transparent 68%);
  filter: blur(2px);
}
.popup {
  position: relative;
  z-index: 2;
  overflow: hidden;
  border: 1px solid var(--line);
  border-radius: 16px;
  background: var(--panel);
  box-shadow: 0 30px 70px rgba(0, 0, 0, 0.3), 0 2px 10px rgba(0, 0, 0, 0.12);
}
.popup img { display: block; width: 380px; height: auto; }
.window {
  position: relative;
  z-index: 2;
  overflow: hidden;
  max-width: 100%;
  border: 1px solid var(--line);
  border-radius: 13px;
  background: #14252d;
  box-shadow: 0 30px 70px rgba(0, 0, 0, 0.34), 0 2px 10px rgba(0, 0, 0, 0.14);
}
.bar {
  display: flex;
  align-items: center;
  gap: 10px;
  height: 34px;
  padding: 0 12px;
  background: #14252d;
  border-bottom: 1px solid rgba(255, 255, 255, 0.08);
}
.dots i {
  display: inline-block;
  width: 7px;
  height: 7px;
  margin-right: 4px;
  border-radius: 50%;
  background: #5b6b73;
}
.addr {
  flex: 1;
  min-width: 0;
  height: 22px;
  padding: 0 8px;
  overflow: hidden;
  border-radius: 5px;
  background: rgba(255, 255, 255, 0.07);
  color: #a9b8c4;
  font-size: 10px;
  line-height: 22px;
  white-space: nowrap;
}
.window img { display: block; max-width: 100%; height: auto; }
.window--fade::after {
  content: "";
  position: absolute;
  right: 0;
  bottom: 0;
  left: 0;
  height: 64px;
  background: linear-gradient(to bottom, rgba(14, 31, 38, 0), #0e1f26 88%);
  pointer-events: none;
}
.gate-bg {
  position: absolute;
  right: -140px;
  bottom: -210px;
  width: 760px;
  opacity: 0.24;
  pointer-events: none;
  mask-image: linear-gradient(90deg, transparent 0%, #000 48%);
}
.foot {
  position: absolute;
  left: 56px;
  bottom: 18px;
  z-index: 3;
  color: var(--muted);
  font-size: 10px;
  letter-spacing: 0.08em;
  text-transform: uppercase;
}
`
);

writeFile(
  join(SRC, "banner.css"),
  `/* Chrome promotional tiles. Brand colors mirror design/tokens.json. */
* { box-sizing: border-box; }
html, body { margin: 0; overflow: hidden; }
body {
  position: relative;
  font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", "Helvetica Neue", Arial, sans-serif;
  background: #0e1f26;
  color: #f2f5fa;
}
.gate {
  position: absolute;
  right: -90px;
  bottom: -180px;
  opacity: 0.55;
  pointer-events: none;
  mask-image: linear-gradient(90deg, transparent 0%, #000 42%);
}
.content { position: relative; z-index: 2; }
.brand {
  display: flex;
  align-items: center;
  gap: 9px;
  color: #a9b8c4;
  font-size: 10px;
  font-weight: 700;
  letter-spacing: 0.14em;
}
.brand img { width: 22px; height: 22px; border-radius: 5px; }
body.small { width: 440px; height: 280px; }
body.small .content { width: 270px; padding: 26px 24px; }
body.small .gate { width: 320px; opacity: 0.5; }
body.small h1 {
  margin: 18px 0 8px;
  font-size: 27px;
  line-height: 1.03;
  font-weight: 650;
  letter-spacing: -0.025em;
}
body.small p {
  margin: 0;
  color: #a9b8c4;
  font-size: 11.5px;
  line-height: 1.4;
}
body.small .rule {
  width: 30px;
  height: 2px;
  margin-top: 15px;
  background: #b5763a;
}
body.marquee { width: 1400px; height: 560px; }
body.marquee .content { width: 790px; padding: 64px 0 0 72px; }
body.marquee .gate { width: 780px; right: -70px; bottom: -210px; opacity: 0.52; }
body.marquee .kicker {
  margin: 22px 0 0;
  padding-left: 12px;
  border-left: 2px solid #b5763a;
  color: #a9b8c4;
  font-size: 11px;
  font-weight: 600;
  letter-spacing: 0.15em;
  text-transform: uppercase;
}
body.marquee h1 {
  margin: 18px 0 16px;
  max-width: 650px;
  font-size: 58px;
  line-height: 1.02;
  font-weight: 650;
  letter-spacing: -0.03em;
}
body.marquee .lede {
  max-width: 610px;
  margin: 0;
  color: #a9b8c4;
  font-size: 19px;
  line-height: 1.5;
}
.chips { display: flex; flex-wrap: wrap; gap: 8px; margin-top: 26px; }
.chip {
  display: inline-flex;
  align-items: center;
  min-height: 29px;
  padding: 0 12px;
  border: 1px solid #2e4a52;
  border-radius: 999px;
  color: #a9b8c4;
  font-size: 10px;
  font-weight: 600;
  letter-spacing: 0.06em;
  text-transform: uppercase;
  background: rgba(28, 51, 61, 0.5);
}
`
);

copyIcons();
makeMockPages();
renderMockUi();
renderScenes();
renderBanners();
writeManifest();
console.log("store assets built");