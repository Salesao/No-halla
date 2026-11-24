// Visible-tab heartbeat for the optional background check.
//
// Registered dynamically (scripting.registerContentScripts) only for listed
// domains that have a host grant and only while the background check is on.
// While the page is visible it asks the service worker to run the same trust
// check as the 30 s alarm, every TICK_MS. It sends no data of its own and does
// not open or close the gate; the endpoint check remains authoritative.
//
// The script stops itself when the tab is hidden, when the stored config no
// longer lists the page (or turns the background check off), or when the
// extension context is invalidated (update/reload).

(() => {
  const TICK_MS = 2000;
  const LOADED_FLAG = "__nohallaTickLoaded";
  if (globalThis[LOADED_FLAG]) return;
  globalThis[LOADED_FLAG] = true;

  const api = globalThis.browser ?? globalThis.chrome;
  const isFirefox = typeof globalThis.browser !== "undefined";
  let timer = null;

  function stop() {
    if (timer !== null) {
      clearInterval(timer);
      timer = null;
    }
  }

  function send(message) {
    try {
      if (isFirefox) {
        const pending = api.runtime.sendMessage(message);
        if (pending && typeof pending.catch === "function") {
          pending.catch(() => {});
        }
      } else {
        api.runtime.sendMessage(message, () => {
          // A sleeping service worker is woken by the message; a transient
          // failure is retried on the next tick.
          void api.runtime.lastError;
        });
      }
    } catch (error) {
      // The extension context was invalidated; no further ticks can help.
      stop();
    }
  }

  function readConfig() {
    return new Promise((resolve) => {
      try {
        if (isFirefox) {
          api.storage.local.get("gateConfig").then(
            (stored) => resolve(stored && stored.gateConfig),
            () => resolve(null)
          );
        } else {
          api.storage.local.get("gateConfig", (stored) => {
            void api.runtime.lastError;
            resolve(stored && stored.gateConfig);
          });
        }
      } catch (error) {
        resolve(null);
      }
    });
  }

  async function relevant() {
    const config = await readConfig();
    if (!config || config.schemaVersion !== 1) return false;
    if (config.enabled !== true || config.backgroundCheck !== true) return false;
    if (!Array.isArray(config.domains)) return false;
    const host = location.hostname.toLowerCase();
    return config.domains.some(
      (domain) => host === domain || host.endsWith(`.${domain}`)
    );
  }

  async function tick() {
    try {
      if (document.visibilityState !== "visible") return;
      if (!(await relevant())) {
        stop();
        return;
      }
      send({ type: "tabTick" });
    } catch (error) {
      stop();
    }
  }

  function start() {
    if (timer === null) timer = setInterval(tick, TICK_MS);
  }

  function sync() {
    if (document.visibilityState === "visible") {
      tick();
      start();
    } else {
      stop();
    }
  }

  document.addEventListener("visibilitychange", sync);
  window.addEventListener("pageshow", sync);
  window.addEventListener("pagehide", stop);
  sync();
})();