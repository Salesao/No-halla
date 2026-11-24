// Configuration and UI state stored in chrome.storage.local under `gateConfig`
// and `gateState`. Every error path is fail-closed: callers receive defaults
// plus an error flag and must keep their current rules.

import { parseIPv4, parseCIDR } from './cidr.js';
import { FALLBACK_LIMIT } from './endpoints.js';

const CONFIG_KEY = 'gateConfig';
const STATE_KEY = 'gateState';
const MAX_DOMAINS = 500;
const MAX_TRUSTED = 64;
export const MIN_INTERVAL_SECONDS = 30;
const VERDICTS = ['trusted', 'untrusted', 'unknown'];
const LANGUAGES = ['system', 'en', 'ru'];

export const DEFAULT_CONFIG = Object.freeze({
  schemaVersion: 1,
  enabled: true,
  domains: Object.freeze([]),
  trustedAddresses: Object.freeze([]),
  endpoint: 'https://ipinfo.io/ip',
  fallbackEndpoints: Object.freeze([]),
  language: 'system',
  backgroundCheck: false,
  backgroundIntervalSeconds: 30
});

const DEFAULT_STATE = Object.freeze({
  lastVerdict: 'unknown',
  lastIP: null,
  lastCheckAt: null,
  degraded: false
});

function cloneConfig(config) {
  return {
    schemaVersion: config.schemaVersion,
    enabled: config.enabled,
    domains: Array.isArray(config.domains) ? config.domains.slice() : [],
    trustedAddresses: Array.isArray(config.trustedAddresses) ? config.trustedAddresses.slice() : [],
    endpoint: config.endpoint,
    fallbackEndpoints: Array.isArray(config.fallbackEndpoints) ? config.fallbackEndpoints.slice() : [],
    language: config.language,
    backgroundCheck: config.backgroundCheck,
    backgroundIntervalSeconds: config.backgroundIntervalSeconds
  };
}

function cloneState(state) {
  return {
    lastVerdict: state.lastVerdict,
    lastIP: state.lastIP,
    lastCheckAt: state.lastCheckAt,
    degraded: state.degraded
  };
}

// Canonical hostname or null. Strips a scheme, path/query/fragment and a
// numeric port, then validates every label.
export function normalizeHostname(input) {
  if (typeof input !== 'string') return null;

  let host = input.trim().toLowerCase();
  host = host.replace(/^[a-z][a-z0-9+.-]*:\/\//, '');
  const cut = host.search(/[/?#]/);
  if (cut !== -1) host = host.slice(0, cut);
  host = host.replace(/\.$/, '');
  host = host.replace(/:\d+$/, '');

  if (host.length === 0 || host.length > 253) return null;
  if (!/^[a-z0-9.-]+$/.test(host)) return null;
  if (host.includes('*') || host.includes(':') || host.includes('/')) return null;

  const labels = host.split('.');
  if (labels.length < 2) return null;
  for (const label of labels) {
    if (label.length < 1 || label.length > 63) return null;
    if (!/^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$/.test(label)) return null;
  }
  return host;
}

function isValidEndpoint(value) {
  if (typeof value !== 'string' || value.trim() === '') return false;
  let url;
  try {
    url = new URL(value);
  } catch {
    return false;
  }
  return url.protocol === 'https:' && url.username === '' && url.password === '' && url.hostname !== '';
}

export function validateConfig(config) {
  if (typeof config !== 'object' || config === null || Array.isArray(config)) return 'schema:invalid';
  if (config.schemaVersion !== 1) return 'schema:invalid';

  if (typeof config.enabled !== 'boolean') return 'schema:invalid';
  if (!Array.isArray(config.domains)) return 'domains:invalid';
  if (config.domains.length > MAX_DOMAINS) return 'domains:limit';

  const seen = new Set();
  for (const domain of config.domains) {
    if (typeof domain !== 'string') return 'domains:invalid';
    if (normalizeHostname(domain) !== domain) return 'domains:invalid';
    if (seen.has(domain)) return 'domains:duplicate';
    seen.add(domain);
  }

  if (!Array.isArray(config.trustedAddresses)) return 'trusted:invalid';
  if (config.trustedAddresses.length > MAX_TRUSTED) return 'trusted:limit';
  for (const address of config.trustedAddresses) {
    if (typeof address !== 'string') return 'trusted:invalid';
    if (parseIPv4(address) === null && parseCIDR(address) === null) return 'trusted:invalid';
  }

  if (!isValidEndpoint(config.endpoint)) return 'endpoint:invalid';

  const fallbackEndpoints = config.fallbackEndpoints === undefined ? [] : config.fallbackEndpoints;
  if (!Array.isArray(fallbackEndpoints)) return 'fallback:invalid';
  if (fallbackEndpoints.length > FALLBACK_LIMIT) return 'fallback:limit';
  const endpointSet = new Set([config.endpoint]);
  for (const url of fallbackEndpoints) {
    if (!isValidEndpoint(url)) return 'fallback:invalid';
    if (endpointSet.has(url)) return 'fallback:duplicate';
    endpointSet.add(url);
  }

  if (!LANGUAGES.includes(config.language)) return 'language:invalid';
  if (typeof config.backgroundCheck !== 'boolean') return 'schema:invalid';
  if (
    !Number.isInteger(config.backgroundIntervalSeconds) ||
    config.backgroundIntervalSeconds < MIN_INTERVAL_SECONDS
  ) {
    return 'interval:range';
  }

  return null;
}

// Old builds allowed a 1 s floor. Clamp that field on load so an upgrade never
// turns a valid stored config into config-error and freezes the rules.
export function normalizeStoredConfig(raw) {
  if (raw === null || typeof raw !== 'object' || Array.isArray(raw)) return raw;
  if (raw.schemaVersion !== 1) return raw;
  let normalized = raw;
  const interval = normalized.backgroundIntervalSeconds;
  if (Number.isInteger(interval) && interval >= 1 && interval < MIN_INTERVAL_SECONDS) {
    normalized = { ...normalized, backgroundIntervalSeconds: MIN_INTERVAL_SECONDS };
  }
  // Added after 1.0.0: an old config has no fallback list, which means none.
  if (normalized.fallbackEndpoints === undefined) {
    normalized = { ...normalized, fallbackEndpoints: [] };
  }
  return normalized;
}

export async function loadConfig() {
  try {
    const storage = globalThis.chrome && globalThis.chrome.storage && globalThis.chrome.storage.local;
    if (!storage || typeof storage.get !== 'function') {
      return { config: cloneConfig(DEFAULT_CONFIG), error: 'config-error' };
    }
    const result = await storage.get(CONFIG_KEY);
    const raw = result && typeof result === 'object' ? result[CONFIG_KEY] : undefined;
    if (raw === undefined) {
      return { config: cloneConfig(DEFAULT_CONFIG), error: null };
    }
    const normalized = normalizeStoredConfig(raw);
    if (validateConfig(normalized) !== null) {
      return { config: cloneConfig(DEFAULT_CONFIG), error: 'config-error' };
    }
    return { config: cloneConfig(normalized), error: null };
  } catch {
    return { config: cloneConfig(DEFAULT_CONFIG), error: 'config-error' };
  }
}

export async function saveConfig(config) {
  const error = validateConfig(config);
  if (error !== null) throw new Error(error);

  const storage = globalThis.chrome && globalThis.chrome.storage && globalThis.chrome.storage.local;
  if (!storage || typeof storage.set !== 'function') {
    throw new Error('storage:unavailable');
  }
  await storage.set({ [CONFIG_KEY]: cloneConfig(config) });
}

function coerceState(raw) {
  const state = raw && typeof raw === 'object' && !Array.isArray(raw) ? raw : {};
  const verdict = VERDICTS.includes(state.lastVerdict) ? state.lastVerdict : 'unknown';
  const lastIP = typeof state.lastIP === 'string' && state.lastIP !== '' ? state.lastIP : null;
  const lastCheckAt = Number.isFinite(state.lastCheckAt) && state.lastCheckAt >= 0 ? state.lastCheckAt : null;
  return {
    lastVerdict: verdict,
    lastIP,
    lastCheckAt,
    degraded: Boolean(state.degraded)
  };
}

export async function loadState() {
  try {
    const storage = globalThis.chrome && globalThis.chrome.storage && globalThis.chrome.storage.local;
    if (!storage || typeof storage.get !== 'function') {
      return cloneState(DEFAULT_STATE);
    }
    const result = await storage.get(STATE_KEY);
    const raw = result && typeof result === 'object' ? result[STATE_KEY] : undefined;
    return coerceState(raw);
  } catch {
    return cloneState(DEFAULT_STATE);
  }
}

export async function saveState(state) {
  const storage = globalThis.chrome && globalThis.chrome.storage && globalThis.chrome.storage.local;
  if (!storage || typeof storage.set !== 'function') {
    throw new Error('storage:unavailable');
  }
  await storage.set({ [STATE_KEY]: coerceState(state) });
}