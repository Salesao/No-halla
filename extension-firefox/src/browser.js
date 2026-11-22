// Firefox namespace wrapper. Every extension context uses `browser.*`
// promise-based APIs; the `chrome` fallback only keeps the modules loadable in
// a Chrome-like host during development. This artifact targets Firefox, so no
// callback-style calls are used anywhere.

export const api = globalThis.browser ?? globalThis.chrome;

/**
 * True when the page runs with the Firefox `browser` namespace.
 * @returns {boolean}
 */
export function isFirefox() {
  return typeof globalThis.browser !== "undefined";
}