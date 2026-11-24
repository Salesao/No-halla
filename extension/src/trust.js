// Trust check: fetch the configured IP endpoint and classify the observed
// address against the trusted list. Port of the app's IPVerifier semantics.
// Fail-closed: every error path resolves to `unknown`; a previous verdict is
// never reused, and this module keeps no state between calls.
// No chrome APIs, no UI strings, no address logging.

import { parseIPv4, ipInTrustedList } from './cidr.js';

// An IPv4 answer is 15 characters; anything larger is not this endpoint.
const MAX_BODY_BYTES = 128;
const ATTEMPT_TIMEOUT_MS = 2000;
// One check tries up to MAX_ATTEMPTS endpoints (rotation/fallback) inside a
// bounded total budget. A single endpoint still gets one transport retry for
// the intermittent ERR_CONNECTION_CLOSED case.
const TOTAL_BUDGET_MS = 6000;
const MAX_ATTEMPTS = 4;
const RETRY_MIN_REMAINING_MS = 500;
const RETRY_JITTER_MS = 250;

// Fresh object per call: callers can never mutate a shared verdict.
function unknownVerdict() {
  return { verdict: 'unknown', ip: null };
}

async function cancelBody(response) {
  try {
    if (response && response.body && typeof response.body.cancel === 'function') {
      await response.body.cancel();
    }
  } catch {
    // The stream may already be closed; nothing else to release.
  }
}

// Read at most MAX_BODY_BYTES and abort the stream beyond that. A hostile or
// misconfigured endpoint must not be able to grow the service worker's memory.
async function readBoundedText(response) {
  const body = response.body;
  if (!body || typeof body.getReader !== 'function') {
    const text = await response.text();
    return text.length > MAX_BODY_BYTES ? null : text;
  }

  const reader = body.getReader();
  const chunks = [];
  let total = 0;
  try {
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      total += value.byteLength;
      if (total > MAX_BODY_BYTES) {
        try {
          await reader.cancel();
        } catch {
          // Already cancelled.
        }
        return null;
      }
      chunks.push(value);
    }
  } finally {
    try {
      reader.releaseLock();
    } catch {
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

// HTTPS-only endpoint: a plain-http endpoint can answer with 200 and no
// redirect, so the scheme is verified here rather than relying on `res.url`.
export function isHttpsEndpoint(value) {
  if (typeof value !== 'string') return false;
  let url;
  try {
    url = new URL(value);
  } catch {
    return false;
  }
  return url.protocol === 'https:' && url.hostname !== '';
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// A transport failure rejects as a TypeError in both browsers. Timeouts abort
// with an AbortError and are never retried.
function isTransportError(error) {
  return Boolean(error) && error.name === 'TypeError';
}

async function attempt(endpoint, trustedAddresses, timeoutMs) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const res = await fetch(endpoint, {
      method: 'GET',
      cache: 'no-store',
      credentials: 'omit',
      redirect: 'error',
      signal: controller.signal
    });

    if (!res || res.ok !== true) {
      await cancelBody(res);
      return unknownVerdict();
    }
    if (!String(res.url).startsWith('https://')) {
      await cancelBody(res);
      return unknownVerdict();
    }

    // Strict IPv4 only: IPv6, HTML/captive-portal markup and empty bodies are
    // all unparseable and therefore `unknown`.
    const text = await readBoundedText(res);
    if (text === null) return unknownVerdict();
    const body = text.trim();
    if (parseIPv4(body) === null) return unknownVerdict();

    // Empty trusted list is a setup state, not a pass: fail closed.
    if (!Array.isArray(trustedAddresses) || trustedAddresses.length === 0) {
      return { verdict: 'unknown', ip: body };
    }

    const trusted = ipInTrustedList(body, trustedAddresses);
    return { verdict: trusted ? 'trusted' : 'untrusted', ip: body };
  } finally {
    clearTimeout(timer);
  }
}

/**
 * Check the current public address against `config.trustedAddresses`, trying
 * the supplied endpoints in order until one returns a valid IPv4 (or the
 * budget runs out). A valid untrusted address is final; only failures without
 * a usable address fall through to the next endpoint.
 * @param {object} config
 * @param {string[]} [endpoints] ordered endpoints; defaults to config.endpoint.
 * @returns {Promise<{verdict: 'trusted'|'untrusted'|'unknown', ip: string|null}>}
 */
export async function checkTrust(config, endpoints = []) {
  if (typeof config !== 'object' || config === null || Array.isArray(config)) {
    return unknownVerdict();
  }

  const requested =
    Array.isArray(endpoints) && endpoints.length > 0
      ? endpoints
      : [config.endpoint];
  const list = requested.filter(isHttpsEndpoint);
  if (list.length === 0) return unknownVerdict();

  const trustedAddresses = config.trustedAddresses;
  const startedAt = Date.now();
  const deadline = startedAt + TOTAL_BUDGET_MS;
  const attempts = Math.min(list.length, MAX_ATTEMPTS);
  let transportFailure = false;

  for (let index = 0; index < attempts; index += 1) {
    const remaining = deadline - Date.now();
    if (remaining < RETRY_MIN_REMAINING_MS) break;
    try {
      const result = await attempt(
        list[index],
        trustedAddresses,
        Math.min(ATTEMPT_TIMEOUT_MS, remaining)
      );
      if (result.verdict !== 'unknown') return result;
      // A valid IPv4 with an empty trusted list is a setup state; another
      // endpoint cannot change it.
      if (result.ip !== null) return result;
    } catch (error) {
      if (isTransportError(error)) transportFailure = true;
      // A timeout or network error on one endpoint falls through to the next.
    }
  }

  // Keep the single-endpoint retry for the intermittent connection close.
  if (list.length === 1 && transportFailure) {
    const remaining = deadline - Date.now();
    if (remaining >= RETRY_MIN_REMAINING_MS) {
      await sleep(1 + Math.floor(Math.random() * RETRY_JITTER_MS));
      const retryTimeout = deadline - Date.now();
      if (retryTimeout >= RETRY_MIN_REMAINING_MS) {
        try {
          return await attempt(list[0], trustedAddresses, retryTimeout);
        } catch {
          return unknownVerdict();
        }
      }
    }
  }
  return unknownVerdict();
}