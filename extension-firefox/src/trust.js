// Trust check: fetch the configured IP endpoint and classify the observed
// address against the trusted list. Port of the app's IPVerifier semantics.
// Fail-closed: every error path resolves to `unknown`; a previous verdict is
// never reused, and this module keeps no state between calls.
// No browser APIs, no UI strings, no address logging.

import { parseIPv4, ipInTrustedList } from './cidr.js';

// An IPv4 answer is 15 characters; anything larger is not this endpoint.
const MAX_BODY_BYTES = 128;
const ATTEMPT_TIMEOUT_MS = 2000;
// Each check uses one endpoint. The total budget still bounds the request and
// the one transport retry kept for the intermittent ERR_CONNECTION_CLOSED case.
const TOTAL_BUDGET_MS = 6000;
const MAX_ATTEMPTS = 1;
const RETRY_MIN_REMAINING_MS = 500;
const RETRY_JITTER_MS = 250;

// Fresh object per call: callers can never mutate a shared verdict.
function unknownVerdict() {
  return { verdict: 'unknown', ip: null, failed: [] };
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

// Endpoint failures carry status/header details for per-endpoint cooldowns.
// Timeouts and transport errors are classified; only a network error is retried.
function headerValue(res, name) {
  return res && res.headers && typeof res.headers.get === 'function'
    ? res.headers.get(name)
    : null;
}

function parseRetryAfter(value) {
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

function makeFailure(endpoint, kind, details = {}) {
  const status = Number.isFinite(details.status) ? details.status : 0;
  const retryAfterMs = Number.isFinite(details.retryAfterMs)
    ? details.retryAfterMs
    : null;
  const cfRay = typeof details.cfRay === 'string' ? details.cfRay : null;
  console.warn(
    'No-halla Gate: endpoint failed',
    endpoint,
    kind,
    status,
    retryAfterMs,
    cfRay
  );
  return { endpoint, kind, status, retryAfterMs, cfRay };
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
      return {
        failure: makeFailure(endpoint, 'http', {
          status: res && Number.isFinite(res.status) ? res.status : 0,
          retryAfterMs: parseRetryAfter(headerValue(res, 'Retry-After')),
          cfRay: headerValue(res, 'CF-Ray')
        })
      };
    }
    if (!String(res.url).startsWith('https://')) {
      await cancelBody(res);
      return {
        failure: makeFailure(endpoint, 'scheme', {
          status: res.status,
          cfRay: headerValue(res, 'CF-Ray')
        })
      };
    }

    // Strict IPv4 only: IPv6, HTML/captive-portal markup and empty bodies are
    // all unparseable and therefore `unknown`.
    const text = await readBoundedText(res);
    if (text === null) {
      return {
        failure: makeFailure(endpoint, 'body', {
          status: res.status,
          cfRay: headerValue(res, 'CF-Ray')
        })
      };
    }
    const body = text.trim();
    if (parseIPv4(body) === null) {
      return {
        failure: makeFailure(endpoint, 'body', {
          status: res.status,
          cfRay: headerValue(res, 'CF-Ray')
        })
      };
    }

    // Empty trusted list is a setup state, not a pass: fail closed.
    if (!Array.isArray(trustedAddresses) || trustedAddresses.length === 0) {
      return { verdict: 'unknown', ip: body };
    }

    const trusted = ipInTrustedList(body, trustedAddresses);
    return { verdict: trusted ? 'trusted' : 'untrusted', ip: body };
  } catch (error) {
    return {
      failure: makeFailure(
        endpoint,
        error && error.name === 'AbortError' ? 'timeout' : 'network'
      )
    };
  } finally {
    clearTimeout(timer);
  }
}

/**
 * Check the current public address against `config.trustedAddresses`, using the
 * supplied endpoint. The caller selects one available endpoint per check; this
 * function keeps the one transport retry and returns failure details so the
 * caller can cool down that endpoint.
 * @param {object} config
 * @param {string[]} [endpoints] endpoint list; the first HTTPS endpoint is used.
 * @returns {Promise<{verdict: 'trusted'|'untrusted'|'unknown', ip: string|null, failed: Array<{endpoint: string, kind: string, status: number, retryAfterMs: number|null, cfRay: string|null}>}>}
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
  const failed = [];
  let transportFailure = false;

  for (let index = 0; index < attempts; index += 1) {
    const remaining = deadline - Date.now();
    if (remaining < RETRY_MIN_REMAINING_MS) break;
    const outcome = await attempt(
      list[index],
      trustedAddresses,
      Math.min(ATTEMPT_TIMEOUT_MS, remaining)
    );
    if (outcome.failure) {
      failed.push(outcome.failure);
      if (outcome.failure.kind === 'network') transportFailure = true;
      continue;
    }
    if (outcome.verdict !== 'unknown') {
      return { verdict: outcome.verdict, ip: outcome.ip, failed };
    }
    // A valid IPv4 with an empty trusted list is a setup state; another
    // endpoint cannot change it.
    if (outcome.ip !== null) {
      return { verdict: outcome.verdict, ip: outcome.ip, failed };
    }
  }

  // Keep the single-endpoint retry for the intermittent connection close.
  if (list.length === 1 && transportFailure) {
    const remaining = deadline - Date.now();
    if (remaining >= RETRY_MIN_REMAINING_MS) {
      await sleep(1 + Math.floor(Math.random() * RETRY_JITTER_MS));
      const retryTimeout = deadline - Date.now();
      if (retryTimeout >= RETRY_MIN_REMAINING_MS) {
        const retry = await attempt(list[0], trustedAddresses, retryTimeout);
        if (!retry.failure) {
          return { verdict: retry.verdict, ip: retry.ip, failed };
        }
        failed.push(retry.failure);
      }
    }
  }
  return { verdict: 'unknown', ip: null, failed };
}