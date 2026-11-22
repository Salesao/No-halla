// Blocked page logic. Reads the verdict from the service worker, renders the
// localized copy and offers re-check / settings. Every
// chrome.runtime call is wrapped: the page must never throw, even when the
// worker is asleep or the message port dies.

import { applyLanguage, currentLanguage, localizeDocument, t } from "../src/i18n.js";

const STATUS_LIST = [
  "protected",
  "untrusted",
  "unknown",
  "degraded",
  "disabled",
  "setup"
];

const MAX_DOMAIN_LENGTH = 253;

const FALLBACK_CONFIG = {
  enabled: true,
  trustedAddresses: [],
  language: "system"
};

const FALLBACK_STATE = {
  lastVerdict: "unknown",
  lastIP: null,
  lastCheckAt: null,
  degraded: false
};

const refs = {
  card: document.getElementById("blocked-card"),
  heading: document.getElementById("blocked-heading"),
  reason: document.getElementById("blocked-reason"),
  message: document.getElementById("blocked-message"),
  currentIP: document.getElementById("blocked-current-ip"),
  lastCheck: document.getElementById("blocked-last-check"),
  checkButton: document.getElementById("blocked-check"),
  settingsButton: document.getElementById("blocked-settings")
};

const view = {
  config: FALLBACK_CONFIG,
  state: FALLBACK_STATE,
  configError: false,
  domain: null,
  status: "unknown",
  busy: false,
  trustedNow: false,
  returnUrl: null,
  message: ""
};

// --- data helpers ---------------------------------------------------------

function cleanDomain(value) {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  if (trimmed.length === 0 || trimmed.length > MAX_DOMAIN_LENGTH) return null;
  return trimmed;
}

function readDomainParam() {
  try {
    return cleanDomain(new URLSearchParams(location.search).get("domain"));
  } catch {
    return null;
  }
}

// Runs inside frames too: document.referrer is all we touch, never a parent frame.
function readReferrerHost() {
  try {
    if (!document.referrer) return null;
    const url = new URL(document.referrer);
    if (url.protocol !== "http:" && url.protocol !== "https:") return null;
    return cleanDomain(url.hostname);
  } catch {
    return null;
  }
}

function readReturnUrl(response) {
  const raw = response && typeof response.blockedUrl === "string"
    ? response.blockedUrl
    : null;
  if (raw === null) return null;
  try {
    const url = new URL(raw);
    if (url.protocol !== "http:" && url.protocol !== "https:") return null;
    return url.href;
  } catch {
    return null;
  }
}

function readBlockedDomain(response) {
  if (!response) return null;
  return cleanDomain(response.blockedDomain);
}

function formatTime(timestamp) {
  if (typeof timestamp !== "number" || !Number.isFinite(timestamp)) {
    return t("gate.popup.never");
  }
  try {
    return new Intl.DateTimeFormat(currentLanguage(), {
      dateStyle: "short",
      timeStyle: "short"
    }).format(new Date(timestamp));
  } catch {
    return new Date(timestamp).toLocaleString();
  }
}

// --- messaging ------------------------------------------------------------

async function send(message) {
  try {
    const response = await chrome.runtime.sendMessage(message);
    if (!response || response.ok !== true) return null;
    return response;
  } catch {
    return null;
  }
}

function applyResponse(response) {
  if (!response || typeof response !== "object") return false;

  if (response.state && typeof response.state === "object") {
    view.state = { ...FALLBACK_STATE, ...response.state };
  } else {
    view.state = {
      ...view.state,
      lastVerdict: typeof response.verdict === "string" ? response.verdict : view.state.lastVerdict,
      lastIP: response.ip === undefined ? view.state.lastIP : response.ip,
      degraded: typeof response.degraded === "boolean" ? response.degraded : view.state.degraded
    };
  }
  if (response.config && typeof response.config === "object") {
    view.config = response.config;
  }
  if (typeof response.configError === "boolean") {
    view.configError = response.configError;
  }
  return true;
}

async function ensureLanguage(language) {
  try {
    await applyLanguage(language);
  } catch {
    try {
      await applyLanguage("system");
    } catch {
      // Keep the default dictionary; keys degrade to raw copy keys.
    }
  }
}

// --- status ---------------------------------------------------------------

function computeStatus() {
  const config = view.config;
  const state = view.state;

  if (view.configError || state.degraded) return "degraded";
  if (config.enabled === false) return "disabled";

  const trusted = Array.isArray(config.trustedAddresses) ? config.trustedAddresses : [];
  if (trusted.length === 0) return "setup";

  if (state.lastVerdict === "trusted") return "protected";
  if (state.lastVerdict === "untrusted") return "untrusted";
  return "unknown";
}

function reasonText(status) {
  switch (status) {
    case "degraded":
      return t("gate.blocked.degraded");
    case "disabled":
      return t("gate.blocked.disabled");
    case "setup":
      return t("gate.blocked.reason.setup");
    case "untrusted":
      return t("gate.blocked.reason.untrusted");
    case "protected":
      return t("gate.status.protected_lore");
    default:
      return t("gate.blocked.reason.unknown");
  }
}

// --- rendering ------------------------------------------------------------

function render() {
  const base = computeStatus();
  const status = view.trustedNow && base !== "degraded" && base !== "disabled"
    ? "protected"
    : base;
  view.status = status;

  refs.heading.textContent = view.domain
    ? t("gate.blocked.heading", view.domain)
    : t("gate.blocked.headingGeneric");

  refs.reason.textContent = reasonText(status);
  for (const name of STATUS_LIST) {
    refs.reason.classList.toggle(`status-${name}`, name === status);
  }

  const ip = typeof view.state.lastIP === "string" && view.state.lastIP.length > 0
    ? view.state.lastIP
    : t("gate.common.unknown");
  refs.currentIP.textContent = t("gate.blocked.currentIP", ip);
  refs.lastCheck.textContent = t("gate.blocked.lastCheck", formatTime(view.state.lastCheckAt));

  refs.checkButton.disabled = view.busy;
  refs.settingsButton.disabled = view.busy;

  refs.message.textContent = view.message;
  refs.card.setAttribute("aria-busy", view.busy ? "true" : "false");
  document.documentElement.lang = currentLanguage();
}

// --- actions --------------------------------------------------------------

async function onCheck() {
  if (view.busy) return;
  view.busy = true;
  view.message = t("gate.status.checking");
  render();

  const response = await send({ type: "checkNow" });
  view.busy = false;

  if (!response) {
    view.message = t("gate.error.generic");
    render();
    return;
  }

  applyResponse(response);
  view.trustedNow = response.verdict === "trusted" && response.degraded !== true;
  if (view.trustedNow && view.returnUrl !== null) {
    view.message = t("gate.blocked.unblocked");
    render();
    location.replace(view.returnUrl);
    return;
  }
  view.message = view.trustedNow ? t("gate.blocked.unblocked") : "";
  render();
}

async function onSettings() {
  try {
    await chrome.runtime.openOptionsPage();
  } catch {
    view.message = t("gate.error.generic");
    render();
  }
}

// --- boot -----------------------------------------------------------------

async function boot() {
  const response = await send({ type: "getState" });
  const hasState = applyResponse(response);

  const language = view.config && typeof view.config.language === "string"
    ? view.config.language
    : "system";
  await ensureLanguage(language);

  if (!hasState) {
    view.configError = true;
    view.state = { ...view.state, degraded: true };
  }

  view.domain = readDomainParam() ?? readReferrerHost() ?? readBlockedDomain(response);
  view.returnUrl =
    readReturnUrl(response) ??
    (view.domain ? `https://${view.domain}/` : null);
  if (!hasState) view.message = t("gate.error.generic");

  localizeDocument();
  render();
}

refs.checkButton.addEventListener("click", () => {
  void onCheck();
});
refs.settingsButton.addEventListener("click", () => {
  void onSettings();
});

boot().catch(() => {
  view.configError = true;
  view.state = { ...view.state, degraded: true };
  view.message = t("gate.error.generic");
  localizeDocument();
  render();
});