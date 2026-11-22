/**
 * No-halla Gate background event page (Firefox MV3).
 *
 * Orchestrates the standalone extension: trust checks, DNR dynamic rules,
 * per-domain host permissions, the optional alarm, and the UI message
 * protocol. Firefox runs this file as a packaged background page, so module
 * imports are plain ES modules instead of a Chrome service worker.
 *
 * Fail-closed policy (spec 6.2/6.5): a cold background-page start is
 * "unknown" for rule purposes even when storage says "trusted"; rules are
 * removed only after a fresh trusted check and a verified getDynamicRules()
 * comparison. A damaged config never removes rules.
 */

import { api } from "./browser.js";
import {
  DEFAULT_CONFIG,
  loadConfig,
  loadState,
  saveConfig,
  saveState,
  validateConfig,
} from "./config.js";
import { checkTrust } from "./trust.js";
import { reconcileRules } from "./rules.js";

const THROTTLE_MS = 3000;
const BACKOFF_START_MS = 5000;
const BACKOFF_MAX_MS = 60000;
const ALARM_CHECK = "gate-check";
// Firefox does not clamp alarm periods: `periodInMinutes` is passed to the
// platform timer as-is, so the stored interval is used exactly. Alarms are not
// persisted across browser restarts, which is why every cold start resyncs it.
const FALLBACK_ALARM_MINUTES = 1;

let cachedConfig = { ...DEFAULT_CONFIG };
let cachedState = {
  lastVerdict: "unknown",
  lastIP: null,
  lastCheckAt: null,
  degraded: false,
};
let configError = false;
let lastAttemptAt = 0;
let backoffMs = 0;
let inFlight = null;
let configRevision = 0;
let lastBlockedDomain = null;
let lastBlockedUrl = null;
let requestListener = null;

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

function errorCode(error) {
  if (error && typeof error.message === "string" && error.message) {
    return error.message;
  }
  return "internal";
}

async function safeSaveState(state) {
  try {
    await saveState(state);
  } catch (error) {
    // State is UI-only; a write failure must not turn into a trusted verdict.
    console.warn("No-halla Gate: state write failed", errorCode(error));
  }
}

function stateSnapshot(extra = {}) {
  return {
    verdict: cachedState.lastVerdict,
    ip: cachedState.lastIP,
    degraded: cachedState.degraded,
    state: clone(cachedState),
    config: clone(cachedConfig),
    configError,
    ...extra,
  };
}

async function updateAction() {
  const blocked =
    !configError &&
    cachedConfig.enabled &&
    cachedState.lastVerdict !== "trusted";
  try {
    await api.action.setBadgeText({ text: blocked ? "!" : "" });
    await api.action.setBadgeBackgroundColor({ color: "#a42338" });
    await api.action.setTitle({
      title: blocked ? "No-halla Gate — blocked" : "No-halla Gate — open",
    });
  } catch (error) {
    // Badge is cosmetic.
  }
}

async function reconcile(config, verdictState, isConfigError = configError) {
  if (isConfigError) {
    return { ok: false, degraded: true };
  }
  let result = { ok: false, degraded: true };
  try {
    result = await reconcileRules(config, verdictState, { configError: false });
  } catch (error) {
    console.warn("No-halla Gate: reconcile failed", errorCode(error));
  }
  return result;
}

/**
 * Runs one trust check (unless throttled/backed off) and applies the verdict.
 * A forced check ignores the throttle and backoff (user action).
 */
async function performCheck(force = false) {
  // Dedup only with a check that reads the same installed config. A check
  // started for an older config is awaited and then replaced by a fresh one.
  for (;;) {
    if (!inFlight) break;
    if (inFlight.revision === configRevision) {
      return inFlight.promise;
    }
    try {
      await inFlight.promise;
    } catch (error) {
      // The owner of that promise reports its own failure.
    }
  }

  const now = Date.now();
  if (!force) {
    if (now - lastAttemptAt < THROTTLE_MS) {
      return stateSnapshot({ skipped: "throttle" });
    }
    if (backoffMs > 0 && now - lastAttemptAt < backoffMs) {
      return stateSnapshot({ skipped: "backoff" });
    }
  }

  // Snapshot and revision are read together, with no await between them, so a
  // check can never pair an old config with a newer revision.
  const revisionAtStart = configRevision;
  const configSnapshot = clone(cachedConfig);
  const promise = (async () => {
    lastAttemptAt = Date.now();
    let result = { verdict: "unknown", ip: null };

    if (configError) {
      const failedState = {
        ...cachedState,
        lastVerdict: "unknown",
        degraded: true,
        lastCheckAt: Date.now(),
      };
      cachedState = failedState;
      await safeSaveState(failedState);
      await updateAction();
      return stateSnapshot();
    }

    try {
      result = await checkTrust(configSnapshot);
    } catch (error) {
      // checkTrust never throws; this is defence in depth.
      result = { verdict: "unknown", ip: null };
    }

    if (revisionAtStart !== configRevision) {
      return stateSnapshot({ skipped: "stale-config" });
    }

    const next = {
      ...cachedState,
      lastVerdict: result.verdict,
      lastIP: result.ip,
      lastCheckAt: Date.now(),
      degraded: false,
    };

    let applied = await reconcile(configSnapshot, next, false);

    // The config changed while rules were being verified: this verdict is
    // stale, so do not persist it. The newer config's check has been queued.
    if (revisionAtStart !== configRevision) {
      return stateSnapshot({ skipped: "stale-config" });
    }

    const previousBlocked = Boolean(
      configSnapshot.enabled && cachedState.lastVerdict !== "trusted"
    );

    if (applied.degraded) {
      next.degraded = true;
      // Rules unverified: never report trusted, keep the gate closed.
      next.lastVerdict = "unknown";
    }

    cachedState = next;
    if (result.verdict === "unknown") {
      backoffMs = backoffMs
        ? Math.min(backoffMs * 2, BACKOFF_MAX_MS)
        : BACKOFF_START_MS;
    } else {
      backoffMs = 0;
    }
    lastAttemptAt = Date.now();
    await safeSaveState(cachedState);

    // A page that was already open under a trusted verdict keeps its SPA
    // shell; only its subresources are blocked. Reload it once when the gate
    // closes so the redirect rule can show the blocked page.
    const nowBlocked = Boolean(
      configSnapshot.enabled &&
        !applied.degraded &&
        next.lastVerdict !== "trusted"
    );
    if (nowBlocked && !previousBlocked) {
      await reloadOpenTabs(configSnapshot.domains);
    }

    await updateAction();
    return stateSnapshot();
  })();

  inFlight = { revision: revisionAtStart, promise };
  try {
    return await promise;
  } finally {
    if (inFlight && inFlight.promise === promise) {
      inFlight = null;
    }
  }
}

async function hasOrigin(pattern) {
  try {
    return await api.permissions.contains({ origins: [pattern] });
  } catch (error) {
    return false;
  }
}

async function domainGranted(domain) {
  // Firefox may keep only the broader `*.domain` pattern when both are asked
  // for.
  const apex = `*://${domain}/*`;
  const wildcard = `*://*.${domain}/*`;
  return (await hasOrigin(wildcard)) || (await hasOrigin(apex));
}

function domainUrls(domain) {
  return [`*://${domain}/*`, `*://*.${domain}/*`];
}

function onRequest(details) {
  try {
    const url = new URL(details.url);
    if (details.type === "main_frame" || details.type === "sub_frame") {
      // The redirect target is a moz-extension page; it must never replace the
      // last http(s) site recorded for the blocked page.
      if (url.protocol !== "http:" && url.protocol !== "https:") {
        return;
      }
      lastBlockedDomain = url.hostname;
      lastBlockedUrl = url.href;
    }
  } catch (error) {
    // Ignore malformed URLs.
  }
  performCheck(false).catch((error) => {
    console.warn("No-halla Gate: request check failed", errorCode(error));
  });
}

async function reloadOpenTabs(domains) {
  if (!Array.isArray(domains)) return;
  for (const domain of domains) {
    let tabs = [];
    try {
      // The url filter needs host access to the domain; skip the ones whose
      // grant is missing. Reloading a controlled SPA is what turns an
      // already-loaded page into the blocked page.
      tabs = await api.tabs.query({
        url: [`*://${domain}/*`, `*://*.${domain}/*`]
      });
    } catch (error) {
      continue;
    }
    for (const tab of tabs) {
      if (typeof tab.id !== "number" || tab.id < 0) continue;
      try {
        await api.tabs.reload(tab.id);
      } catch (error) {
        // The tab may have closed between the query and the reload.
      }
    }
  }
}

async function registerWebRequest(domains) {
  if (requestListener) {
    try {
      api.webRequest.onBeforeRequest.removeListener(requestListener);
    } catch (error) {
      // Listener already gone.
    }
    requestListener = null;
  }
  const list = Array.isArray(domains) ? domains : [];
  const urls = [];
  for (const domain of list) {
    for (const pattern of domainUrls(domain)) {
      if (await hasOrigin(pattern)) {
        urls.push(pattern);
      }
    }
  }
  if (urls.length === 0) {
    return;
  }
  try {
    requestListener = onRequest;
    // Observation only: no "blocking" entry, no request bodies. The filter is
    // limited to listed domains, never <all_urls>.
    api.webRequest.onBeforeRequest.addListener(requestListener, {
      urls: [...new Set(urls)],
    });
  } catch (error) {
    // Missing host permission for part of the filter: register nothing rather
    // than observing unrelated traffic. Checks still run on startup/popup.
    requestListener = null;
    console.warn("No-halla Gate: webRequest registration failed", errorCode(error));
  }
}

async function syncAlarm(config) {
  try {
    await api.alarms.clear(ALARM_CHECK);
    if (config.enabled && config.backgroundCheck) {
      const minutes = config.backgroundIntervalSeconds / 60;
      try {
        await api.alarms.create(ALARM_CHECK, { periodInMinutes: minutes });
      } catch (error) {
        // Keep the check alive if Firefox rejected the exact value.
        await api.alarms.create(ALARM_CHECK, {
          periodInMinutes: FALLBACK_ALARM_MINUTES,
        });
      }
    }
  } catch (error) {
    console.warn("No-halla Gate: alarm sync failed", errorCode(error));
  }
}

async function syncPermissions(domains) {
  const keep = new Set();
  for (const domain of domains) {
    for (const pattern of domainUrls(domain)) {
      keep.add(pattern);
    }
  }
  try {
    const all = await api.permissions.getAll();
    const remove = (all.origins || []).filter(
      (origin) => origin.startsWith("*://") && !keep.has(origin)
    );
    if (remove.length > 0) {
      await api.permissions.remove({ origins: remove });
    }
  } catch (error) {
    // Removal failure leaves a broader grant than needed; rules still match.
    console.warn("No-halla Gate: permission sync failed", errorCode(error));
  }
}

function endpointOrigin(endpoint) {
  try {
    const parsed = new URL(endpoint);
    if (parsed.protocol !== "https:") {
      return null;
    }
    // Match patterns do not carry ports: a host pattern covers every port.
    return `${parsed.protocol}//${parsed.hostname}/*`;
  } catch (error) {
    return null;
  }
}

async function endpointGranted(endpoint) {
  const origin = endpointOrigin(endpoint);
  if (origin === null) {
    return false;
  }
  return hasOrigin(origin);
}

async function missingDomains(domains) {
  const missing = [];
  for (const domain of domains) {
    if (!(await domainGranted(domain))) {
      missing.push(domain);
    }
  }
  return missing;
}

let saveQueue = Promise.resolve();

// Serialize saves so a stale permission keep-set cannot remove a domain the
// next save just granted.
function handleSaveConfig(nextConfig) {
  const run = saveQueue.then(() => applySaveConfig(nextConfig));
  saveQueue = run.then(
    () => undefined,
    () => undefined
  );
  return run;
}

async function applySaveConfig(nextConfig) {
  // A damaged stored config must never be overwritten by a page that only
  // rendered defaults. Recovery is a successful reload after the storage is
  // repaired, not "save empty settings".
  if (configError) {
    return { ok: false, error: "config-error" };
  }
  const validation = validateConfig(nextConfig);
  if (validation) {
    return { ok: false, error: "invalid", detail: validation };
  }
  const deniedDomains = await missingDomains(nextConfig.domains);
  if (deniedDomains.length > 0) {
    return { ok: false, error: "permission-denied", deniedDomains };
  }
  if (!(await endpointGranted(nextConfig.endpoint))) {
    return { ok: false, error: "permission-denied", deniedEndpoint: nextConfig.endpoint };
  }

  try {
    await saveConfig(nextConfig);
  } catch (error) {
    return { ok: false, error: "invalid", detail: errorCode(error) };
  }

  const previousDomains = new Set(cachedConfig.domains);
  const previousEndpointOrigin = endpointOrigin(cachedConfig.endpoint);
  cachedConfig = clone(nextConfig);
  configError = false;
  configRevision += 1;
  await syncPermissions(cachedConfig.domains);
  const nextEndpointOrigin = endpointOrigin(cachedConfig.endpoint);
  if (
    previousEndpointOrigin !== null &&
    nextEndpointOrigin !== null &&
    previousEndpointOrigin !== nextEndpointOrigin
  ) {
    try {
      await api.permissions.remove({ origins: [previousEndpointOrigin] });
    } catch (error) {
      // The old endpoint may be a required manifest grant; nothing to remove.
    }
  }
  await registerWebRequest(cachedConfig.domains);
  await syncAlarm(cachedConfig);

  const result = await performCheck(true);
  const addedDomains = nextConfig.domains.filter(
    (domain) => !previousDomains.has(domain)
  );
  if (
    addedDomains.length > 0 &&
    result.degraded !== true &&
    result.state &&
    result.state.lastVerdict !== "trusted"
  ) {
    await reloadOpenTabs(addedDomains);
  }
  return { ok: true, ...result };
}

async function handlePendingDomain() {
  if (configError) return;
  let pending = null;
  try {
    const stored = await api.storage.local.get("gatePendingDomain");
    pending = stored.gatePendingDomain;
  } catch (error) {
    return;
  }
  if (typeof pending !== "string" || pending.length === 0) return;
  if (!(await domainGranted(pending))) return;
  if (cachedConfig.domains.includes(pending)) {
    try {
      await api.storage.local.remove("gatePendingDomain");
    } catch (error) {
      // Best effort.
    }
    return;
  }
  const candidate = {
    ...cachedConfig,
    domains: [...cachedConfig.domains, pending]
  };
  if (validateConfig(candidate) !== null) {
    try {
      await api.storage.local.remove("gatePendingDomain");
    } catch (error) {
      // Best effort.
    }
    return;
  }
  await handleSaveConfig(candidate);
  try {
    await api.storage.local.remove("gatePendingDomain");
  } catch (error) {
    // Best effort.
  }
}

async function revalidateConfig() {
  // A damaged stored config is never overwritten. If it was repaired outside
  // the extension, the next UI request picks it up instead of staying locked
  // until a browser restart.
  if (!configError) {
    return;
  }
  try {
    const loaded = await loadConfig();
    if (loaded.error !== null) {
      return;
    }
    cachedConfig = loaded.config;
    configError = false;
    configRevision += 1;
    await syncAlarm(cachedConfig);
    await registerWebRequest(cachedConfig.domains);
    const applied = await reconcile(cachedConfig, cachedState, false);
    cachedState = { ...cachedState, degraded: applied.degraded === true };
    await safeSaveState(cachedState);
    await updateAction();
  } catch (error) {
    // Still damaged: keep the previous fail-closed state.
  }
}

async function handleMessage(message) {
  if (configError) {
    await revalidateConfig();
  }
  const type = message && message.type;
  switch (type) {
    case "getConfig":
      return { ok: true, config: clone(cachedConfig), configError };
    case "getState":
      return {
        ok: true,
        ...stateSnapshot(),
        blockedDomain: lastBlockedDomain,
        blockedUrl: lastBlockedUrl,
      };
    case "checkNow": {
      const result = await performCheck(true);
      return { ok: true, ...result };
    }
    case "saveConfig":
      return handleSaveConfig(message.config);
    default:
      return { ok: false, error: "unknown-message" };
  }
}

async function init() {
  try {
    const loaded = await loadConfig();
    cachedConfig = loaded.config;
    configError = loaded.error !== null;
    cachedState = await loadState();

    // Cold start: the persisted verdict is UI-only. Rules stay (or are applied)
    // until a fresh check proves trust.
    const coldState = {
      ...cachedState,
      lastVerdict: "unknown",
      degraded: false,
    };
    const applied = await reconcile(cachedConfig, coldState, configError);
    if (applied.degraded) {
      coldState.degraded = true;
    }
    cachedState = coldState;
    if (configError && cachedState.degraded !== true) {
      cachedState = { ...cachedState, degraded: true };
    }
    await safeSaveState(cachedState);
    await updateAction();
  } catch (error) {
    // Never remove rules when initialization fails.
    configError = true;
    cachedState = { ...cachedState, lastVerdict: "unknown", degraded: true };
    console.warn("No-halla Gate: init failed", errorCode(error));
  }

  await syncAlarm(cachedConfig);
  await registerWebRequest(cachedConfig.domains);
  await updateAction();

  // One-shot check on every cold start (spec 6.3): it may lift the gate only
  // after a fresh trusted verdict and verified rule removal.
  performCheck(false).catch((error) => {
    console.warn("No-halla Gate: startup check failed", errorCode(error));
  });
}

const ready = init();

// A popup permission prompt may close the popup before it can save the
// domain. The grant still arrives here; finish the add.
if (api.permissions && api.permissions.onAdded) {
  api.permissions.onAdded.addListener(() => {
    ready
      .then(handlePendingDomain)
      .catch((error) => {
        console.warn("No-halla Gate: pending domain failed", errorCode(error));
      });
  });
}

// Firefox resolves the Promise returned by a listener into the response.
api.runtime.onMessage.addListener((message, sender) => {
  return ready
    .then(() => handleMessage(message))
    .catch((error) => ({ ok: false, error: errorCode(error) }));
});

api.runtime.onStartup.addListener(() => {
  ready
    .then(async () => {
      await syncAlarm(cachedConfig);
      await registerWebRequest(cachedConfig.domains);
      await performCheck(true);
    })
    .catch((error) => {
      console.warn("No-halla Gate: startup event failed", errorCode(error));
    });
});

api.runtime.onInstalled.addListener(() => {
  ready
    .then(async () => {
      await syncAlarm(cachedConfig);
      await registerWebRequest(cachedConfig.domains);
      await performCheck(true);
    })
    .catch((error) => {
      console.warn("No-halla Gate: install event failed", errorCode(error));
    });
});

api.alarms.onAlarm.addListener((alarm) => {
  ready
    .then(async () => {
      if (alarm.name === ALARM_CHECK) {
        if (!cachedConfig.enabled || !cachedConfig.backgroundCheck) {
          await api.alarms.clear(ALARM_CHECK);
          return;
        }
        await performCheck(false);
        return;
      }
    })
    .catch((error) => {
      console.warn("No-halla Gate: alarm failed", errorCode(error));
    });
});