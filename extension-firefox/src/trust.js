// Trust check: fetch the configured IP endpoint and classify the observed
// address against the trusted list. Port of the app's IPVerifier semantics.
// Fail-closed: every error path resolves to `unknown`; a previous verdict is
// never reused, and this module keeps no state between calls.
// No browser APIs, no UI strings, no address logging.

import { parseIPv4, ipInTrustedList } from './cidr.js';

// An IPv4 answer is 15 characters; anything larger is not this endpoint.
const MAX_BODY_BYTES = 128;

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
function isHttpsEndpoint(value) {
  if (typeof value !== 'string') return false;
  let url;
  try {
    url = new URL(value);
  } catch {
    return false;
  }
  return url.protocol === 'https:' && url.hostname !== '';
}

/**
 * Check the current public address against `config.trustedAddresses`.
 * @param {object} config extension config (`endpoint`, `trustedAddresses`).
 * @returns {Promise<{verdict: 'trusted'|'untrusted'|'unknown', ip: string|null}>}
 */
export async function checkTrust(config) {
  let controller = null;
  let timer = null;

  try {
    if (typeof config !== 'object' || config === null || Array.isArray(config)) {
      return unknownVerdict();
    }

    const endpoint = config.endpoint;
    if (!isHttpsEndpoint(endpoint)) return unknownVerdict();

    controller = new AbortController();
    timer = setTimeout(() => controller.abort(), 2500);

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
    if (!Array.isArray(config.trustedAddresses) || config.trustedAddresses.length === 0) {
      return { verdict: 'unknown', ip: body };
    }

    const trusted = ipInTrustedList(body, config.trustedAddresses);
    return { verdict: trusted ? 'trusted' : 'untrusted', ip: body };
  } catch {
    // AbortError/timeout, network failure, redirect rejection, malformed body.
    return unknownVerdict();
  } finally {
    clearTimeout(timer);
  }
}