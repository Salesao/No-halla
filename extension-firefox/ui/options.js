// Options page for No-halla Gate. The page keeps a copy of the config only for
// rendering; every mutation goes through the background page message protocol.
// Host permissions are requested from inside the click handlers so Firefox
// keeps the user gesture, and any failure surfaces a localized message.

import { api } from "../src/browser.js";
import { DEFAULT_CONFIG, normalizeHostname, validateConfig } from "../src/config.js";
import { applyLanguage, localizeDocument, t } from "../src/i18n.js";

const MAX_DOMAINS = 500;
const MAX_TRUSTED = 64;
const MIN_INTERVAL_SECONDS = 1;
const SAVED_TIMEOUT_MS = 2500;

const form = document.getElementById("options-form");
const configWarning = document.getElementById("config-warning");
const statusNode = document.getElementById("status");

const domainList = document.getElementById("domain-list");
const domainInput = document.getElementById("domain-input");
const domainAdd = document.getElementById("domain-add");
const domainsError = document.getElementById("domains-error");

const trustedList = document.getElementById("trusted-list");
const trustedInput = document.getElementById("trusted-input");
const trustedAdd = document.getElementById("trusted-add");
const trustedAddCurrent = document.getElementById("trusted-add-current");
const trustedError = document.getElementById("trusted-error");

const endpointInput = document.getElementById("endpoint");
const endpointSave = document.getElementById("endpoint-save");
const endpointError = document.getElementById("endpoint-error");

const languageSelect = document.getElementById("language");
const backgroundInput = document.getElementById("background-check");
const intervalField = document.getElementById("interval-field");
const intervalInput = document.getElementById("interval-seconds");
const settingsError = document.getElementById("settings-error");

const errorNodes = {
  domains: domainsError,
  trusted: trustedError,
  endpoint: endpointError,
  settings: settingsError
};

/** @type {object} */
let config = cloneDefault();
let busy = false;
let locked = false;
let savedTimer = null;

function cloneDefault() {
  return {
    schemaVersion: DEFAULT_CONFIG.schemaVersion,
    enabled: DEFAULT_CONFIG.enabled,
    domains: [],
    trustedAddresses: [],
    endpoint: DEFAULT_CONFIG.endpoint,
    language: DEFAULT_CONFIG.language,
    backgroundCheck: DEFAULT_CONFIG.backgroundCheck,
    backgroundIntervalSeconds: DEFAULT_CONFIG.backgroundIntervalSeconds
  };
}

// Defensive copy of a config sent by the service worker; null when unusable.
function readConfig(raw) {
  if (raw === null || typeof raw !== "object" || Array.isArray(raw)) return null;
  return {
    schemaVersion: Number.isInteger(raw.schemaVersion) ? raw.schemaVersion : DEFAULT_CONFIG.schemaVersion,
    enabled: raw.enabled !== false,
    domains: Array.isArray(raw.domains) ? raw.domains.slice() : [],
    trustedAddresses: Array.isArray(raw.trustedAddresses) ? raw.trustedAddresses.slice() : [],
    endpoint: typeof raw.endpoint === "string" ? raw.endpoint : DEFAULT_CONFIG.endpoint,
    language: ["system", "en", "ru"].includes(raw.language) ? raw.language : DEFAULT_CONFIG.language,
    backgroundCheck: raw.backgroundCheck === true,
    backgroundIntervalSeconds: Number.isInteger(raw.backgroundIntervalSeconds)
      ? raw.backgroundIntervalSeconds
      : DEFAULT_CONFIG.backgroundIntervalSeconds
  };
}

async function send(message) {
  try {
    const response = await api.runtime.sendMessage(message);
    if (response !== null && typeof response === "object") return response;
    return { ok: false, error: "empty-response" };
  } catch {
    return { ok: false, error: "unavailable" };
  }
}

// Sends the candidate config and adopts the config echoed back by the worker.
async function persist(candidate) {
  const response = await send({ type: "saveConfig", config: candidate });
  if (response.ok !== true) {
    if (response.error === "config-error") {
      setLocked(true);
      configWarning.hidden = false;
      showError("settings", t("gate.error.config"));
    }
    return {
      ok: false,
      error: typeof response.error === "string" ? response.error : "generic",
      detail: typeof response.detail === "string" ? response.detail : null
    };
  }
  const next = readConfig(response.config);
  if (next === null) return { ok: false, error: "generic", detail: null };
  config = next;
  configWarning.hidden = true;
  return { ok: true, error: null, detail: null };
}

function mapValidation(detail) {
  if (typeof detail !== "string") return t("gate.error.generic");
  if (detail === "interval:range") return t("gate.error.interval", MIN_INTERVAL_SECONDS);
  if (detail === "endpoint:invalid") return t("gate.error.endpoint");
  if (detail === "trusted:limit") return t("gate.error.addressLimit", MAX_TRUSTED);
  if (detail === "trusted:invalid") return t("gate.error.address");
  if (detail === "domains:limit") return t("gate.error.domainLimit", MAX_DOMAINS);
  if (detail === "domains:duplicate") return t("gate.error.duplicate");
  if (detail === "domains:invalid") return t("gate.error.hostname");
  return t("gate.error.generic");
}

function clearSaved() {
  clearTimeout(savedTimer);
  savedTimer = null;
  statusNode.textContent = "";
}

function clearMessages() {
  clearSaved();
  for (const node of Object.values(errorNodes)) node.textContent = "";
}

function showError(section, message) {
  const node = errorNodes[section];
  if (node) node.textContent = message;
}

function showSaved() {
  statusNode.textContent = t("gate.options.saved");
  clearTimeout(savedTimer);
  savedTimer = setTimeout(() => {
    savedTimer = null;
    statusNode.textContent = "";
  }, SAVED_TIMEOUT_MS);
}

function setBusy(value) {
  busy = value;
  syncDisabled();
}

function setLocked(value) {
  locked = value;
  syncDisabled();
}

function syncDisabled() {
  const disabled = busy || locked;
  for (const button of form.querySelectorAll("button")) button.disabled = disabled;
  for (const field of [
    domainInput,
    trustedInput,
    endpointInput,
    languageSelect,
    backgroundInput
  ]) {
    field.disabled = disabled;
  }
  intervalInput.disabled = disabled || backgroundInput.checked !== true;
}

function syncInterval() {
  const enabled = backgroundInput.checked === true;
  intervalField.hidden = !enabled;
  intervalInput.disabled = !enabled || busy || locked;
}

function createRemoveButton(accessibleName, onClick) {
  const button = document.createElement("button");
  button.type = "button";
  button.className = "btn-remove";
  button.textContent = t("gate.options.remove");
  button.setAttribute("aria-label", accessibleName);
  button.disabled = busy || locked;
  button.addEventListener("click", onClick);
  return button;
}

function renderDomains() {
  domainList.replaceChildren();
  if (config.domains.length === 0) {
    const empty = document.createElement("li");
    empty.className = "empty";
    empty.textContent = t("gate.options.noDomains");
    domainList.append(empty);
    return;
  }
  for (const domain of config.domains) {
    const row = document.createElement("li");
    const value = document.createElement("span");
    value.className = "value";
    value.textContent = domain;
    row.append(
      value,
      createRemoveButton(`${t("gate.options.remove")} ${domain}`, () => {
        removeDomain(domain);
      })
    );
    domainList.append(row);
  }
}

function renderTrusted() {
  trustedList.replaceChildren();
  for (const address of config.trustedAddresses) {
    const row = document.createElement("li");
    const value = document.createElement("span");
    value.className = "value";
    value.textContent = address;
    row.append(
      value,
      createRemoveButton(`${t("gate.options.remove")} ${address}`, () => {
        removeTrusted(address);
      })
    );
    trustedList.append(row);
  }
}

function syncSettings() {
  languageSelect.value = config.language;
  backgroundInput.checked = config.backgroundCheck === true;
  intervalInput.value = String(config.backgroundIntervalSeconds);
}

function render() {
  renderDomains();
  renderTrusted();
  syncSettings();
  syncInterval();
  syncDisabled();
}

async function removeDomain(domain) {
  if (busy || locked) return;
  clearMessages();
  const index = config.domains.indexOf(domain);
  setBusy(true);
  const candidate = {
    ...config,
    domains: config.domains.filter((item) => item !== domain)
  };
  const result = await persist(candidate);
  setBusy(false);
  if (result.ok) {
    renderDomains();
    const buttons = domainList.querySelectorAll(".btn-remove");
    const target = buttons[Math.min(index, buttons.length - 1)] || domainAdd;
    if (target) target.focus();
    showSaved();
    return;
  }
  showError("domains", t("gate.error.generic"));
}

async function removeTrusted(address) {
  if (busy || locked) return;
  clearMessages();
  const index = config.trustedAddresses.indexOf(address);
  setBusy(true);
  const candidate = {
    ...config,
    trustedAddresses: config.trustedAddresses.filter((item) => item !== address)
  };
  const result = await persist(candidate);
  setBusy(false);
  if (result.ok) {
    renderTrusted();
    const buttons = trustedList.querySelectorAll(".btn-remove");
    const target =
      buttons[Math.min(index, buttons.length - 1)] || trustedAddCurrent;
    if (target) target.focus();
    showSaved();
    return;
  }
  showError("trusted", t("gate.error.generic"));
}

async function addDomain() {
  if (busy || locked) return;
  clearMessages();

  const domain = normalizeHostname(domainInput.value);
  if (domain === null) {
    showError("domains", t("gate.error.hostname"));
    return;
  }
  if (config.domains.includes(domain)) {
    showError("domains", t("gate.error.duplicate"));
    return;
  }
  if (config.domains.length >= MAX_DOMAINS) {
    showError("domains", t("gate.error.domainLimit", MAX_DOMAINS));
    return;
  }

  const origins = [`*://${domain}/*`, `*://*.${domain}/*`];
  // Requested synchronously from the click handler, before any await, so the
  // Firefox prompt keeps the user gesture.
  setBusy(true);
  let granted = false;
  try {
    granted = await api.permissions.request({ origins });
  } catch {
    granted = false;
  }
  if (granted !== true) {
    setBusy(false);
    showError("domains", t("gate.error.permission"));
    return;
  }

  const candidate = { ...config, domains: [...config.domains, domain] };
  const result = await persist(candidate);
  if (result.ok) {
    domainInput.value = "";
    setBusy(false);
    renderDomains();
    showSaved();
    return;
  }

  try {
    await api.permissions.remove({ origins });
  } catch {
    // Best effort: the domain was never saved, so leave no extra grant behind.
  }
  setBusy(false);
  showError(
    "domains",
    result.error === "permission-denied" ? t("gate.error.permission") : t("gate.error.generic")
  );
}

async function addTrusted() {
  if (busy || locked) return;
  clearMessages();

  const address = trustedInput.value.trim();
  if (address === "") {
    showError("trusted", t("gate.error.address"));
    return;
  }
  if (config.trustedAddresses.includes(address)) {
    showError("trusted", t("gate.error.duplicate"));
    return;
  }

  const candidate = {
    ...config,
    trustedAddresses: [...config.trustedAddresses, address]
  };
  const detail = validateConfig(candidate);
  if (detail !== null) {
    showError("trusted", mapTrustedDetail(detail));
    return;
  }

  setBusy(true);
  const result = await persist(candidate);
  setBusy(false);
  if (result.ok) {
    trustedInput.value = "";
    renderTrusted();
    showSaved();
    return;
  }
  showError("trusted", t("gate.error.generic"));
}

function mapTrustedDetail(detail) {
  if (typeof detail === "string" && detail.startsWith("trusted:limit")) {
    return t("gate.error.addressLimit", MAX_TRUSTED);
  }
  return t("gate.error.address");
}

async function addCurrentIP() {
  if (busy || locked) return;
  clearMessages();
  setBusy(true);

  // Always ask the endpoint now: the cached lastIP can be stale after a
  // network change, and trusting it would block the current address.
  const checkResponse = await send({ type: "checkNow" });
  const ip =
    checkResponse.ok === true &&
    typeof checkResponse.ip === "string" &&
    checkResponse.ip !== ""
      ? checkResponse.ip
      : null;

  if (ip === null || ip === "") {
    setBusy(false);
    showError("trusted", t("gate.error.checkFailed"));
    return;
  }
  if (config.trustedAddresses.includes(ip)) {
    setBusy(false);
    showError("trusted", t("gate.error.duplicate"));
    return;
  }

  const candidate = {
    ...config,
    trustedAddresses: [...config.trustedAddresses, ip]
  };
  const detail = validateConfig(candidate);
  if (detail !== null) {
    setBusy(false);
    showError("trusted", mapTrustedDetail(detail));
    return;
  }

  const result = await persist(candidate);
  setBusy(false);
  if (result.ok) {
    renderTrusted();
    showSaved();
    return;
  }
  showError("trusted", t("gate.error.generic"));
}

async function saveEndpoint() {
  if (busy || locked) return;
  clearMessages();

  const value = endpointInput.value.trim();
  let url = null;
  try {
    url = new URL(value);
  } catch {
    url = null;
  }
  if (url === null || url.protocol !== "https:") {
    showError("endpoint", t("gate.error.endpoint"));
    return;
  }

  const candidate = { ...config, endpoint: value };
  if (validateConfig(candidate) !== null) {
    showError("endpoint", t("gate.error.endpoint"));
    return;
  }

  const originPattern = `${url.protocol}//${url.hostname}/*`;
  const previousOrigin = (() => {
    try {
      const current = new URL(config.endpoint);
      return `${current.protocol}//${current.hostname}/*`;
    } catch {
      return null;
    }
  })();
  // Requested directly in the handler, before the first await.
  setBusy(true);
  let granted = false;
  try {
    granted = await api.permissions.request({ origins: [originPattern] });
  } catch {
    granted = false;
  }
  if (granted !== true) {
    setBusy(false);
    showError("endpoint", t("gate.error.endpoint"));
    return;
  }

  const result = await persist(candidate);
  setBusy(false);
  if (result.ok) {
    syncEndpoint();
    showSaved();
    return;
  }
  if (originPattern !== previousOrigin) {
    // Remove the grant only when the live config still points at the old
    // endpoint. Another tab may already have saved this endpoint.
    const live = await send({ type: "getConfig" });
    let liveOrigin = null;
    if (live.ok === true && live.config && typeof live.config.endpoint === "string") {
      try {
        const liveURL = new URL(live.config.endpoint);
        liveOrigin = `${liveURL.protocol}//${liveURL.hostname}/*`;
      } catch {
        liveOrigin = null;
      }
    }
    if (liveOrigin === previousOrigin) {
      try {
        await api.permissions.remove({ origins: [originPattern] });
      } catch {
        // Best effort: the grant is unused if the endpoint was not saved.
      }
    }
  }
  showError(
    "endpoint",
    result.error === "permission-denied" ? t("gate.error.endpoint") : t("gate.error.generic")
  );
}

async function saveSettings() {
  if (busy || locked) return;
  clearMessages();

  const backgroundCheck = backgroundInput.checked === true;
  let interval = config.backgroundIntervalSeconds;
  if (backgroundCheck) {
    if (intervalInput.value.trim() === "") {
      showError("settings", t("gate.error.interval", MIN_INTERVAL_SECONDS));
      return;
    }
    interval = Number(intervalInput.value);
    if (!Number.isInteger(interval) || interval < MIN_INTERVAL_SECONDS) {
      showError("settings", t("gate.error.interval", MIN_INTERVAL_SECONDS));
      return;
    }
  } else {
    const parsed = Number(intervalInput.value);
    if (Number.isInteger(parsed) && parsed >= MIN_INTERVAL_SECONDS) interval = parsed;
  }

  const candidate = {
    ...config,
    language: languageSelect.value,
    backgroundCheck,
    backgroundIntervalSeconds: interval
  };
  const detail = validateConfig(candidate);
  if (detail !== null) {
    showError("settings", mapValidation(detail));
    return;
  }

  const previousLanguage = config.language;
  setBusy(true);
  const result = await persist(candidate);
  setBusy(false);

  if (!result.ok) {
    if (result.error === "permission-denied") {
      showError("settings", t("gate.error.permission"));
    } else if (result.error === "invalid" && result.detail !== null) {
      showError("settings", mapValidation(result.detail));
    } else {
      showError("settings", t("gate.error.generic"));
    }
    return;
  }

  if (config.language !== previousLanguage) {
    document.documentElement.lang = await applyLanguage(config.language);
    localizeDocument();
  }
  render();
  showSaved();
}

function syncEndpoint() {
  endpointInput.value = config.endpoint;
}

async function initialize() {
  try {
    const response = await send({ type: "getConfig" });
    let language = DEFAULT_CONFIG.language;
    let configError = false;

    if (response.ok === true) {
      const loaded = readConfig(response.config);
      if (loaded !== null) {
        config = loaded;
        language = loaded.language;
      } else {
        configError = true;
      }
      if (response.configError === true) configError = true;
    } else {
      configError = true;
    }

    document.documentElement.lang = await applyLanguage(language);
    localizeDocument();

    if (configError) {
      // Never render editable defaults over a damaged stored config: a Save
      // would overwrite the real domain list and drop its permissions.
      setLocked(true);
      configWarning.hidden = false;
      showError("settings", t("gate.error.config"));
    } else {
      setLocked(false);
      configWarning.hidden = true;
    }

    syncEndpoint();
    render();
  } catch {
    setLocked(true);
    configWarning.hidden = false;
    showError("settings", t("gate.error.config"));
  } finally {
    setBusy(false);
  }
}

form.addEventListener("input", () => {
  clearMessages();
});

form.addEventListener("change", () => {
  clearMessages();
  syncInterval();
});

form.addEventListener("submit", (event) => {
  event.preventDefault();
  saveSettings();
});

domainAdd.addEventListener("click", () => {
  addDomain();
});

trustedAdd.addEventListener("click", () => {
  addTrusted();
});

trustedAddCurrent.addEventListener("click", () => {
  addCurrentIP();
});

endpointSave.addEventListener("click", () => {
  saveEndpoint();
});

domainInput.addEventListener("keydown", (event) => {
  if (event.key !== "Enter") return;
  event.preventDefault();
  addDomain();
});

trustedInput.addEventListener("keydown", (event) => {
  if (event.key !== "Enter") return;
  event.preventDefault();
  addTrusted();
});

endpointInput.addEventListener("keydown", (event) => {
  if (event.key !== "Enter") return;
  event.preventDefault();
  saveEndpoint();
});

// Buttons stay disabled until the config is rendered, and again during saves.
setBusy(true);
initialize();