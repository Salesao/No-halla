/**
 * Dynamic declarativeNetRequest rules for the No-halla Gate extension.
 *
 * A blocked domain gets exactly two fixed-ID rules: a redirect of frames to
 * the packaged blocked page and a block of every subresource. Rule IDs derive
 * from the domain index, so reconcile is deterministic and idempotent.
 *
 * Fail-closed policy (spec 6.2): after every update the applied rule IDs are
 * read back and compared with the desired IDs. Any rejection, missing API or
 * mismatch returns degraded and never reports success. A config error leaves
 * the installed rules untouched.
 *
 * Pure module: no chrome APIs at import time, no I/O, no UI strings.
 */

const BLOCKED_PAGE = "/ui/blocked.html";

const FRAME_RESOURCE_TYPES = ["main_frame", "sub_frame"];

// Every remaining DNR resource type; frames are redirected instead of blocked.
const SUBRESOURCE_TYPES = [
  "script",
  "stylesheet",
  "image",
  "font",
  "object",
  "xmlhttprequest",
  "ping",
  "csp_report",
  "media",
  "websocket",
  "webtransport",
  "webbundle",
  "other",
];

const HOSTNAME_RE = /^[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?$/;
const MAX_HOSTNAME_LENGTH = 253;

/**
 * Canonical hostname for a rule, or null when the value cannot be used.
 * Invalid entries are skipped without shifting IDs of the remaining ones.
 * @param {unknown} value
 * @returns {string|null}
 */
function canonicalDomain(value) {
  if (typeof value !== "string") return null;

  const domain = value.trim().toLowerCase();
  if (!domain || domain.length > MAX_HOSTNAME_LENGTH) return null;
  if (!HOSTNAME_RE.test(domain)) return null;
  if (domain.includes("..")) return null;

  return domain;
}

/**
 * Usable domains in input order.
 * @param {unknown} domains
 * @returns {string[]}
 */
function validDomains(domains) {
  if (!Array.isArray(domains)) return [];

  const result = [];
  for (const domain of domains) {
    const canonical = canonicalDomain(domain);
    if (canonical !== null) result.push(canonical);
  }
  return result;
}

/**
 * Build the desired dynamic rules for a domain list.
 * @param {string[]} domains
 * @returns {object[]} DNR rules with deterministic IDs (2*i+1, 2*i+2).
 */
export function buildRules(domains) {
  const rules = [];
  const list = validDomains(domains);

  list.forEach((domain, index) => {
    rules.push({
      id: 2 * index + 1,
      priority: 1,
      action: {
        type: "redirect",
        redirect: { extensionPath: BLOCKED_PAGE },
      },
      condition: {
        requestDomains: [domain],
        resourceTypes: [...FRAME_RESOURCE_TYPES],
      },
    });

    rules.push({
      id: 2 * index + 2,
      priority: 1,
      action: { type: "block" },
      condition: {
        requestDomains: [domain],
        resourceTypes: [...SUBRESOURCE_TYPES],
      },
    });
  });

  return rules;
}

/**
 * All rule IDs belonging to the given domain list.
 * @param {string[]} domains
 * @returns {number[]} `[1, 2, ..., 2*n]`.
 */
export function allRuleIds(domains) {
  const count = validDomains(domains).length * 2;
  const ids = [];
  for (let id = 1; id <= count; id += 1) {
    ids.push(id);
  }
  return ids;
}

/**
 * Apply or remove dynamic rules so they match the current config and state.
 *
 * Blocking is active when the master switch is on and the last verdict is not
 * trusted. The rules are replaced atomically, then read
 * back and verified by exact ID set. Any failure is reported as degraded; this
 * function never throws.
 *
 * @param {object|null|undefined} config gateConfig shape.
 * @param {object|null|undefined} state gateState shape.
 * @param {{configError?: boolean}} [options]
 * @returns {Promise<{ok: boolean, degraded: boolean}>}
 */
export async function reconcileRules(config, state, options = {}) {
  try {
    // A damaged config must never change the installed rules.
    if (options && options.configError === true) {
      return { ok: false, degraded: true };
    }

    const blocked =
      Boolean(config && config.enabled) &&
      !(state && state.lastVerdict === "trusted");

    const desired = blocked ? buildRules(config && config.domains) : [];
    const desiredIds = desired.map((rule) => rule.id);

    const dnr = globalThis.chrome && globalThis.chrome.declarativeNetRequest;
    if (
      !dnr ||
      typeof dnr.getDynamicRules !== "function" ||
      typeof dnr.updateDynamicRules !== "function"
    ) {
      return { ok: false, degraded: true };
    }

    const existing = await dnr.getDynamicRules();
    if (!Array.isArray(existing)) {
      return { ok: false, degraded: true };
    }

    const removeRuleIds = existing.map((rule) => rule.id);
    const update = { removeRuleIds };
    if (desired.length > 0) update.addRules = desired;

    await dnr.updateDynamicRules(update);

    // Verification pass: the ID set must match the desired set exactly.
    const applied = await dnr.getDynamicRules();
    if (!Array.isArray(applied)) {
      return { ok: false, degraded: true };
    }

    const appliedIds = applied.map((rule) => rule.id);
    if (appliedIds.length !== desiredIds.length) {
      return { ok: false, degraded: true };
    }

    const appliedSet = new Set(appliedIds);
    if (appliedSet.size !== appliedIds.length) {
      return { ok: false, degraded: true };
    }

    const desiredSet = new Set(desiredIds);
    for (const id of desiredIds) {
      if (!appliedSet.has(id)) return { ok: false, degraded: true };
    }
    for (const id of appliedIds) {
      if (!desiredSet.has(id)) return { ok: false, degraded: true };
    }

    return { ok: true, degraded: false };
  } catch {
    return { ok: false, degraded: true };
  }
}