// Tab-context trust probe.
//
// The service worker's `fetch` does not always use the same network path as
// the tab it guards (observed on Vivaldi: the tab used the VPN route while the
// service worker reached the endpoint over the direct ISP route). This module
// runs the check inside an already-open listed tab using one selected endpoint.
// A failure returns its endpoint/status/header details for a cooldown; a
// missing tab or CORS refusal returns `null`, so the caller can fall back to
// the extension-context check; a probe can never open the gate on its own.
//
// Chrome MV3 content scripts are CORS-constrained even with host permissions.
// Known presets without Access-Control-Allow-Origin are skipped here; a custom
// URL is tried once; a CORS/fetch failure is returned for cooldown/fallback.

import { parseIPv4, ipInTrustedList } from './cidr.js';
import { isHttpsEndpoint } from './trust.js';
import { endpointSupportsCors } from './endpoints.js';

const PROBE_TIMEOUT_MS = 6000;
const PROBE_DEADLINE_MS = 7000;
const MAX_PROBE_ENDPOINTS = 1;
const MAX_BODY_BYTES = 128;

// Serialized into the tab by executeScript: it must not reference module
// scope, imports, or any extension API. It uses one endpoint and returns
// { endpoint, text } on success, { endpoint, failure } with status/header
// details on failure, or null when the deadline expires.
async function readEndpointsInTab(endpoints, timeoutMs, maxBytes) {
  const deadline = Date.now() + timeoutMs;
  const attemptMs = 2000;
  const ipv4 =
    /^(?:(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)\.){3}(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)$/;

  function retryAfterMs(value) {
    if (typeof value !== 'string' || value.trim() === '') return null;
    const seconds = Number(value);
    if (Number.isFinite(seconds) && seconds >= 0) {
      return Math.min(seconds * 1000, 86400000);
    }
    const date = Date.parse(value);
    if (Number.isFinite(date)) {
      return Math.min(Math.max(0, date - Date.now()), 86400000);
    }
    return null;
  }

  function failure(kind, res) {
    const headers = res && res.headers;
    const get = headers && typeof headers.get === 'function'
      ? (name) => headers.get(name)
      : () => null;
    return {
      kind,
      status: res && Number.isFinite(res.status) ? res.status : 0,
      retryAfterMs: retryAfterMs(get('Retry-After')),
      cfRay: typeof get('CF-Ray') === 'string' ? get('CF-Ray') : null
    };
  }

  async function readBody(res) {
    const body = res.body;
    if (!body || typeof body.getReader !== 'function') {
      const text = await res.text();
      return text.length > maxBytes ? null : text;
    }
    const reader = body.getReader();
    const chunks = [];
    let total = 0;
    try {
      for (;;) {
        const { done, value } = await reader.read();
        if (done) break;
        total += value.byteLength;
        if (total > maxBytes) {
          try {
            await reader.cancel();
          } catch (error) {
            // Stream already closed.
          }
          return null;
        }
        chunks.push(value);
      }
    } finally {
      try {
        reader.releaseLock();
      } catch (error) {
        // Stream already released.
      }
    }
    const merged = new Uint8Array(total);
    let offset = 0;
    for (const chunk of chunks) {
      merged.set(chunk, offset);
      offset += chunk.byteLength;
    }
    return new TextDecoder().decode(merged);
  }

  for (const endpoint of endpoints) {
    const remaining = deadline - Date.now();
    if (remaining < 400) break;
    const controller = new AbortController();
    const timer = setTimeout(
      () => controller.abort(),
      Math.min(attemptMs, remaining)
    );
    try {
      const res = await fetch(endpoint, {
        method: 'GET',
        cache: 'no-store',
        credentials: 'omit',
        redirect: 'error',
        referrerPolicy: 'no-referrer',
        signal: controller.signal
      });
      if (!res || res.ok !== true) {
        try {
          if (res && res.body && typeof res.body.cancel === 'function') {
            await res.body.cancel();
          }
        } catch (error) {
          // Body already closed.
        }
        return { endpoint, failure: failure('http', res) };
      }
      if (!String(res.url).startsWith('https://')) {
        return { endpoint, failure: failure('scheme', res) };
      }
      const text = await readBody(res);
      if (text === null) {
        return { endpoint, failure: failure('body', res) };
      }
      const body = text.trim();
      if (!ipv4.test(body)) {
        return { endpoint, failure: failure('body', res) };
      }
      return { endpoint, text: body };
    } catch (error) {
      return {
        endpoint,
        failure: failure(
          error && error.name === 'AbortError' ? 'timeout' : 'network',
          null
        )
      };
    } finally {
      clearTimeout(timer);
    }
  }
  return null;
}

function withDeadline(promise, ms) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('probe-timeout')), ms);
    promise.then(
      (value) => {
        clearTimeout(timer);
        resolve(value);
      },
      (error) => {
        clearTimeout(timer);
        reject(error);
      }
    );
  });
}

async function queryTab(query) {
  let tabs = [];
  try {
    tabs = await chrome.tabs.query(query);
  } catch (error) {
    return null;
  }
  if (!Array.isArray(tabs)) return null;
  for (const tab of tabs) {
    if (typeof tab.id !== 'number' || tab.id < 0) continue;
    if (tab.discarded) continue;
    return tab;
  }
  return null;
}

// Prefer the active listed tab of the focused window; any other open listed
// tab shares the same profile network path.
async function pickTab(domains) {
  const urls = [];
  for (const domain of domains) {
    urls.push(`*://${domain}/*`, `*://*.${domain}/*`);
  }
  const active = await queryTab({
    url: urls,
    active: true,
    lastFocusedWindow: true
  });
  if (active !== null) return active;
  return queryTab({ url: urls });
}

async function injectProbe(tabId, endpoints) {
  try {
    const call = chrome.scripting.executeScript({
      target: { tabId },
      world: 'ISOLATED',
      func: readEndpointsInTab,
      args: [endpoints, PROBE_TIMEOUT_MS, MAX_BODY_BYTES]
    });
    const results = await withDeadline(call, PROBE_DEADLINE_MS);
    if (!Array.isArray(results) || results.length === 0) return null;
    const first = results[0];
    if (!first || first.error) return null;
    return first.result;
  } catch (error) {
    return null;
  }
}

/**
 * Run the endpoint check from an open listed tab.
 * @param {object} config extension config (`endpoint`, `trustedAddresses`).
 * @param {string[]} domains listed domains that have a host grant.
 * @param {string[]} [endpoints] the one endpoint selected for this check.
 * @returns {Promise<{verdict: 'trusted'|'untrusted'|'unknown', ip: string, endpoint?: string, failure?: object}|null>}
 *   `null` means no usable tab result; the caller must run the fallback check.
 *   A failure carries endpoint, status, Retry-After and CF-Ray for cooldown.
 */
export async function checkTrustInTab(config, domains, endpoints = []) {
  if (typeof config !== 'object' || config === null) return null;
  if (!isHttpsEndpoint(config.endpoint)) return null;
  if (!Array.isArray(domains) || domains.length === 0) return null;

  const requested =
    Array.isArray(endpoints) && endpoints.length > 0
      ? endpoints
      : [config.endpoint];
  // Custom URLs have no preset entry: try one; CORS refusal returns null.
  const list = requested
    .filter((url) => endpointSupportsCors(url) !== false)
    .slice(0, MAX_PROBE_ENDPOINTS);
  if (list.length === 0) return null;

  const tab = await pickTab(domains);
  if (tab === null) return null;

  const result = await injectProbe(tab.id, list);
  if (!result || typeof result !== 'object') return null;
  if (result.failure) {
    return {
      verdict: 'unknown',
      ip: null,
      endpoint: result.endpoint,
      failure: result.failure
    };
  }
  if (typeof result.text !== 'string') return null;
  const body = result.text.trim();
  // The tab result is usable only when it is strict IPv4, exactly like the
  // service-worker check. Anything else falls back instead of deciding.
  if (parseIPv4(body) === null) return null;

  if (
    !Array.isArray(config.trustedAddresses) ||
    config.trustedAddresses.length === 0
  ) {
    return { verdict: 'unknown', ip: body };
  }
  return {
    verdict: ipInTrustedList(body, config.trustedAddresses)
      ? 'trusted'
      : 'untrusted',
    ip: body
  };
}