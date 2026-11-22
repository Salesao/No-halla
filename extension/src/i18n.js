// Localization for extension pages. Explicit language selection overrides the
// browser UI locale: dictionaries are read from the packaged _locales files,
// cached per language, and every failure degrades to the raw key so the UI
// never breaks. Placeholders use the printf-style %s/%d emitted by the locale
// generator. No chrome.i18n.getMessage dependency, no network requests.

const LOCALES = ['system', 'en', 'ru'];
const DEFAULT_LANGUAGE = 'en';
const PLACEHOLDER_RE = /%[sd]/g;

/** @type {Map<string, Record<string, {message?: string}>>} */
const messageCache = new Map();

let activeLanguage = DEFAULT_LANGUAGE;
/** @type {Record<string, {message?: string}>} */
let activeMessages = Object.create(null);
// Guards against an out-of-order resolution overwriting newer state.
let requestToken = 0;

// "system" maps to the browser UI locale (Russian when it starts with "ru"),
// any unknown language also falls back to "system".
function resolveLanguage(language) {
  const requested = LOCALES.includes(language) ? language : 'system';
  if (requested !== 'system') return requested;

  try {
    const uiLanguage = chrome.i18n.getUILanguage();
    if (typeof uiLanguage === 'string' && uiLanguage.toLowerCase().startsWith('ru')) {
      return 'ru';
    }
  } catch {
    // No chrome.i18n in this context; use the default below.
  }
  return 'en';
}

// Never rejects: an unreadable or malformed locale file yields null so the
// caller can retry instead of caching an empty dictionary forever.
async function loadMessages(language) {
  try {
    const url = chrome.runtime.getURL(`_locales/${language}/messages.json`);
    const response = await fetch(url);
    if (!response.ok) return null;

    const data = await response.json();
    if (data === null || typeof data !== 'object' || Array.isArray(data)) {
      return null;
    }
    if (Object.keys(data).length === 0) return null;
    return data;
  } catch {
    return null;
  }
}

/**
 * Resolve and activate a language.
 * @param {string} language "system", "en" or "ru"; anything else means "system".
 * @returns {Promise<"en"|"ru">} The resolved language tag.
 */
export async function applyLanguage(language) {
  const resolved = resolveLanguage(language);
  const token = ++requestToken;

  let dictionary = messageCache.get(resolved);
  if (dictionary === undefined) {
    const loaded = await loadMessages(resolved);
    if (loaded !== null) {
      messageCache.set(resolved, loaded);
      dictionary = loaded;
    }
  }
  if (dictionary === undefined) {
    dictionary = Object.create(null);
  }
  // Only the most recent call may update module state.
  if (token === requestToken) {
    activeLanguage = resolved;
    activeMessages = dictionary;
  }
  return resolved;
}

/**
 * Translate a copy key such as "gate.popup.title".
 * @param {string} key
 * @param {...unknown} args Values for sequential %s / %d placeholders.
 * @returns {string} Localized text, or the original key when unavailable.
 */
export function t(key, ...args) {
  if (typeof key !== 'string' || key.length === 0) return '';

  const name = key.replace(/\./g, '_');
  const entry = activeMessages[name];
  const template = entry && typeof entry.message === 'string' && entry.message.length > 0
    ? entry.message
    : key;

  let index = 0;
  return template.replace(PLACEHOLDER_RE, (match) => {
    if (index >= args.length) return match;
    return String(args[index++]);
  });
}

/**
 * Apply the active translations to a document subtree.
 * @param {ParentNode|null} root Defaults to the current document.
 */
export function localizeDocument(root = null) {
  if (typeof document === 'undefined' && root === null) return;
  const scope = root ?? document;

  for (const element of scope.querySelectorAll('[data-i18n]')) {
    const key = element.getAttribute('data-i18n');
    if (key) element.textContent = t(key);
  }

  const attributeBindings = [
    ['data-i18n-placeholder', 'placeholder'],
    ['data-i18n-aria-label', 'aria-label'],
    ['data-i18n-title', 'title']
  ];
  for (const [sourceAttribute, targetAttribute] of attributeBindings) {
    for (const element of scope.querySelectorAll(`[${sourceAttribute}]`)) {
      const key = element.getAttribute(sourceAttribute);
      if (key) element.setAttribute(targetAttribute, t(key));
    }
  }
}

/**
 * @returns {"en"|"ru"} Active language; "en" until applyLanguage resolves.
 */
export function currentLanguage() {
  return activeLanguage;
}