// No-halla Gate status popup. Pulls state/config from the background event
// page, renders the status priority, domain list and master switch, and wires
// the one-shot check, domain add/remove, "add current IP" and settings
// entry points. All copy comes from the locale dictionary.

import { api } from "../src/browser.js";
import { normalizeHostname } from "../src/config.js";
import { applyLanguage, currentLanguage, localizeDocument, t } from "../src/i18n.js";

const MAX_DOMAINS = 500;
const MAX_TRUSTED = 64;

const ui = {
  pill: null,
  lore: null,
  ip: null,
  trustedCount: null,
  lastCheck: null,
  addCurrentIP: null,
  addCurrentSite: null,
  domainForm: null,
  domainInput: null,
  domainAdd: null,
  domainList: null,
  domainCount: null,
  domainEmpty: null,
  domainError: null,
  master: null,
  check: null,
  settings: null,
  message: null
};

let config = null;
let state = {
  lastVerdict: "unknown",
  lastIP: null,
  lastCheckAt: null,
  degraded: false
};
let configError = false;
let checking = false;
let saving = false;
let addingIP = false;
let addingDomain = false;
let messageTimer = null;
let domainErrorTimer = null;
let activeSite;

function cacheElements() {
  ui.pill = document.getElementById("status-pill");
  ui.lore = document.getElementById("status-lore");
  ui.ip = document.getElementById("current-ip");
  ui.trustedCount = document.getElementById("trusted-count");
  ui.lastCheck = document.getElementById("last-check");
  ui.addCurrentIP = document.getElementById("add-current-ip");
  ui.addCurrentSite = document.getElementById("add-current-site");
  ui.domainForm = document.getElementById("domain-form");
  ui.domainInput = document.getElementById("domain-input");
  ui.domainAdd = document.getElementById("domain-add");
  ui.domainList = document.getElementById("domain-list");
  ui.domainCount = document.getElementById("domain-count");
  ui.domainEmpty = document.getElementById("domain-empty");
  ui.domainError = document.getElementById("domain-error");
  ui.master = document.getElementById("master");
  ui.check = document.getElementById("check-now");
  ui.settings = document.getElementById("settings");
  ui.message = document.getElementById("message");
}

// Never rejects: transport failures are reported as {ok:false}.
async function send(message) {
  try {
    const response = await api.runtime.sendMessage(message);
    if (response && typeof response === "object") return response;
    return { ok: false, error: "transport" };
  } catch {
    return { ok: false, error: "transport" };
  }
}

async function activateLanguage(language) {
  try {
    await applyLanguage(language);
  } catch {
    // i18n never rejects; keep the popup alive if it ever does.
  }
  document.documentElement.lang = currentLanguage();
  localizeDocument();
}

function domainsOf(value) {
  return value && Array.isArray(value.domains) ? value.domains : [];
}

function trustedOf(value) {
  return value && Array.isArray(value.trustedAddresses)
    ? value.trustedAddresses
    : [];
}

function resolveStatus() {
  if (configError || state.degraded) return "degraded";
  if (!config) return "unknown";
  if (checking) return "checking";
  if (!config.enabled) return "disabled";

  if (trustedOf(config).length === 0) return "setup";

  if (state.lastVerdict === "trusted") return "protected";
  if (state.lastVerdict === "untrusted") return "untrusted";
  return "unknown";
}

function statusText(status) {
  return t(`gate.status.${status}`);
}

const ERROR_TIMEOUT_MS = 2500;

function setMessage(text, persistent = false) {
  clearTimeout(messageTimer);
  messageTimer = null;
  const visible = typeof text === "string" && text.length > 0;
  ui.message.textContent = visible ? text : "";
  ui.message.hidden = !visible;
  if (visible && !persistent) {
    messageTimer = setTimeout(() => {
      messageTimer = null;
      ui.message.textContent = "";
      ui.message.hidden = true;
    }, ERROR_TIMEOUT_MS);
  }
}

function setDomainError(text) {
  clearTimeout(domainErrorTimer);
  domainErrorTimer = null;
  const visible = typeof text === "string" && text.length > 0;
  ui.domainError.textContent = visible ? text : "";
  ui.domainError.hidden = !visible;
  if (visible) {
    domainErrorTimer = setTimeout(() => {
      domainErrorTimer = null;
      ui.domainError.textContent = "";
      ui.domainError.hidden = true;
    }, ERROR_TIMEOUT_MS);
  }
}

function updateControls() {
  const locked = Boolean(configError);
  const blockedActions = saving || locked || !config;

  ui.check.disabled = checking;
  ui.check.toggleAttribute("aria-busy", checking);
  ui.master.disabled = blockedActions;
  ui.addCurrentIP.disabled = addingIP || blockedActions;
  ui.addCurrentIP.toggleAttribute("aria-busy", addingIP);
  ui.addCurrentSite.disabled =
    addingDomain || blockedActions || activeSite === undefined;
  ui.domainInput.disabled = addingDomain || blockedActions;
  ui.domainAdd.disabled = addingDomain || blockedActions;
  for (const button of ui.domainList.querySelectorAll(".row-remove")) {
    button.disabled = addingDomain || blockedActions;
  }
}

function renderDomains() {
  const domains = domainsOf(config);
  ui.domainList.replaceChildren();
  ui.domainEmpty.hidden = !config || domains.length > 0;
  ui.domainCount.textContent = config ? String(domains.length) : "";

  for (const domain of domains) {
    const row = document.createElement("li");
    row.className = "domain-row";

    const value = document.createElement("span");
    value.className = "domain-name";
    value.textContent = domain;

    const remove = document.createElement("button");
    remove.type = "button";
    remove.className = "row-remove";
    remove.textContent = "×";
    const label = `${t("gate.options.remove")} ${domain}`;
    remove.setAttribute("aria-label", label);
    remove.title = label;
    remove.addEventListener("click", () => {
      void removeDomain(domain);
    });

    row.append(value, remove);
    ui.domainList.append(row);
  }
}

function render() {
  const status = resolveStatus();
  document.body.dataset.status = status;

  ui.pill.removeAttribute("data-i18n");
  ui.pill.textContent = statusText(status);
  const loreKey = `gate.status.${status}.lore`;
  const lore = t(loreKey);
  // "checking" has no lore string; never render the raw key.
  ui.lore.textContent = lore === loreKey ? "" : lore;

  const lastIP =
    typeof state.lastIP === "string" && state.lastIP.length > 0
      ? state.lastIP
      : null;
  ui.ip.textContent = lastIP ?? t("gate.popup.unknownIP");
  ui.trustedCount.textContent = config
    ? String(trustedOf(config).length)
    : t("gate.common.unknown");

  const checkedAt = Number(state.lastCheckAt);
  const checkedLabel =
    Number.isFinite(checkedAt) && checkedAt > 0
      ? new Date(checkedAt).toLocaleString()
      : t("gate.popup.never");
  ui.lastCheck.textContent = t("gate.popup.lastCheck", checkedLabel);

  ui.master.checked = Boolean(config && config.enabled);

  if (configError) {
    setMessage(t("gate.error.config"), true);
  } else if (addingIP || addingDomain || saving) {
    // Keep the current progress message.
  } else {
    setMessage("");
  }

  renderDomains();
  updateControls();
}

function applyPayload(payload) {
  if (payload.state && typeof payload.state === "object") {
    state = { ...state, ...payload.state };
  }
  if (payload.config && typeof payload.config === "object") {
    config = payload.config;
  }
  if (typeof payload.configError === "boolean") {
    configError = payload.configError;
  }
  render();
}

function mapSaveError(response) {
  if (!response || response.error === "transport") return t("gate.error.generic");
  if (response.error === "config-error") return t("gate.error.config");
  if (response.error === "permission-denied") return t("gate.error.permission");
  if (response.error === "invalid") {
    const detail = typeof response.detail === "string" ? response.detail : "";
    if (detail === "domains:limit") return t("gate.error.domainLimit", MAX_DOMAINS);
    if (detail === "domains:duplicate") return t("gate.error.duplicate");
    if (detail === "domains:invalid") return t("gate.error.hostname");
    if (detail === "trusted:limit") return t("gate.error.addressLimit", MAX_TRUSTED);
    if (detail === "trusted:invalid") return t("gate.error.address");
  }
  return t("gate.error.generic");
}

async function addDomain() {
  if (addingDomain || saving || configError || !config) return;
  setDomainError("");

  const domain = normalizeHostname(ui.domainInput.value);
  if (domain === null) {
    setDomainError(t("gate.error.hostname"));
    return;
  }
  void addDomainValue(domain);
}

async function currentSiteDomain() {
  try {
    const tabs = await api.tabs.query({ active: true, currentWindow: true });
    const tab = Array.isArray(tabs) ? tabs[0] : null;
    if (!tab || typeof tab.url !== "string") return null;
    const url = new URL(tab.url);
    if (url.protocol !== "http:" && url.protocol !== "https:") return null;
    // A "www." host would protect only that host; the apex covers it and its
    // subdomains through requestDomains.
    const host = url.hostname.replace(/^www\./i, "");
    return normalizeHostname(host);
  } catch {
    return null;
  }
}

async function refreshActiveSite() {
  activeSite = await currentSiteDomain();
  updateControls();
}

async function addCurrentSite() {
  if (addingDomain || saving || configError || !config) return;
  setDomainError("");
  if (activeSite === undefined) return;
  if (activeSite === null) {
    setDomainError(t("gate.error.siteUnavailable"));
    return;
  }
  void addDomainValue(activeSite);
}

async function addDomainValue(domain) {
  if (!config) return;
  if (config.domains.includes(domain)) {
    setDomainError(t("gate.error.duplicate"));
    return;
  }
  if (config.domains.length >= MAX_DOMAINS) {
    setDomainError(t("gate.error.domainLimit", MAX_DOMAINS));
    return;
  }

  addingDomain = true;
  updateControls();

  // The permission request must be issued in the click task, before any
  // await, or Firefox drops the user gesture and never shows the prompt.
  // The pending key lets the background page finish the add if the popup
  // closes while the prompt is visible.
  void api.storage.local.set({ gatePendingDomain: domain }).catch(() => {});
  let granted = false;
  try {
    granted = await api.permissions.request({
      origins: [`*://${domain}/*`, `*://*.${domain}/*`]
    });
  } catch {
    granted = false;
  }
  if (!granted) {
    try {
      await api.storage.local.remove("gatePendingDomain");
    } catch {
      // Pending key is best effort.
    }
    addingDomain = false;
    updateControls();
    setDomainError(t("gate.error.permission"));
    return;
  }

  const response = await send({
    type: "saveConfig",
    config: { ...config, domains: [...config.domains, domain] }
  });
  addingDomain = false;
  try {
    await api.storage.local.remove("gatePendingDomain");
  } catch {
    // Pending key is best effort.
  }

  if (response.ok) {
    ui.domainInput.value = "";
    applyPayload(response);
    ui.domainInput.focus();
    return;
  }
  setDomainError(mapSaveError(response));
  updateControls();
}

async function removeDomain(domain) {
  if (saving || configError || !config) return;
  saving = true;
  updateControls();

  const response = await send({
    type: "saveConfig",
    config: {
      ...config,
      domains: config.domains.filter((item) => item !== domain)
    }
  });
  saving = false;

  if (response.ok) {
    applyPayload(response);
    return;
  }
  setMessage(mapSaveError(response));
  updateControls();
}

async function addCurrentIP() {
  if (addingIP || saving || configError || !config) return;
  setMessage("");
  addingIP = true;
  updateControls();

  // Always ask the endpoint now; a stale cached address would be useless.
  const checkResponse = await send({ type: "checkNow" });
  const ip =
    checkResponse.ok === true &&
    typeof checkResponse.ip === "string" &&
    checkResponse.ip !== ""
      ? checkResponse.ip
      : null;

  if (ip === null) {
    addingIP = false;
    setMessage(t("gate.error.checkFailed"));
    updateControls();
    return;
  }
  if (config.trustedAddresses.includes(ip)) {
    addingIP = false;
    setMessage(t("gate.error.duplicate"));
    updateControls();
    return;
  }
  if (config.trustedAddresses.length >= MAX_TRUSTED) {
    addingIP = false;
    setMessage(t("gate.error.addressLimit", MAX_TRUSTED));
    updateControls();
    return;
  }

  const response = await send({
    type: "saveConfig",
    config: {
      ...config,
      trustedAddresses: [...config.trustedAddresses, ip]
    }
  });
  addingIP = false;

  if (response.ok) {
    applyPayload(response);
    return;
  }
  setMessage(mapSaveError(response));
  updateControls();
}

async function runCheck() {
  if (checking) return;
  checking = true;
  render();

  const response = await send({ type: "checkNow" });
  checking = false;

  if (response.ok) {
    applyPayload(response);
    return;
  }

  render();
  setMessage(
    response.error === "transport" ? t("gate.error.generic") : t("gate.error.checkFailed")
  );
}

async function onMasterChange() {
  if (!config) return;
  if (saving) {
    ui.master.checked = Boolean(config.enabled);
    return;
  }

  const desired = ui.master.checked;
  const previous = Boolean(config.enabled);
  saving = true;
  updateControls();

  const response = await send({
    type: "saveConfig",
    config: { ...config, enabled: desired }
  });
  saving = false;

  if (response.ok && response.config) {
    applyPayload(response);
    return;
  }

  ui.master.checked = previous;
  updateControls();
  setMessage(mapSaveError(response));
}

function openSettings() {
  try {
    const result = api.runtime.openOptionsPage();
    if (result && typeof result.catch === "function") {
      result.catch(() => setMessage(t("gate.error.generic")));
    }
  } catch {
    setMessage(t("gate.error.generic"));
  }
}

function bindEvents() {
  ui.master.addEventListener("change", () => {
    void onMasterChange();
  });
  ui.check.addEventListener("click", () => {
    void runCheck();
  });
  ui.addCurrentIP.addEventListener("click", () => {
    void addCurrentIP();
  });
  ui.domainForm.addEventListener("submit", (event) => {
    event.preventDefault();
    void addDomain();
  });
  ui.addCurrentSite.addEventListener("click", () => {
    void addCurrentSite();
  });
  ui.domainInput.addEventListener("input", () => {
    setDomainError("");
  });
  ui.settings.addEventListener("click", openSettings);
}

async function init() {
  cacheElements();
  bindEvents();
  void refreshActiveSite();
  // No config yet: keep the controls inert until the first payload lands.
  ui.master.disabled = true;
  ui.addCurrentIP.disabled = true;
  ui.domainInput.disabled = true;
  ui.domainAdd.disabled = true;

  const initial = await send({ type: "getState" });
  if (initial.ok && initial.config && typeof initial.config === "object") {
    await activateLanguage(initial.config.language);
    applyPayload(initial);
  } else {
    await activateLanguage("system");
    applyPayload({});
    setMessage(t("gate.error.generic"));
  }

  // Required popup-open one-shot check; the popup already rendered above.
  void runCheck();
}

document.addEventListener("DOMContentLoaded", () => {
  void init();
});