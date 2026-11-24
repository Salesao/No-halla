// Known HTTPS IP-check endpoints. `cors` records whether the endpoint sends
// Access-Control-Allow-Origin, which the in-tab check needs in MV3 content
// scripts. A custom URL has no preset entry and is tried from the tab; if it
// does not allow CORS the next endpoint is used.
//
// HTTP-only endpoints (for example ip-api.com) are deliberately absent: a
// plaintext response could be rewritten by anyone on the path and turn an
// untrusted address into a trusted one.
export const ENDPOINT_PRESETS = Object.freeze([
  { url: 'https://ipinfo.io/ip', cors: true },
  { url: 'https://ipv4.icanhazip.com', cors: true },
  { url: 'https://icanhazip.com', cors: true },
  { url: 'https://ifconfig.co/ip', cors: false },
  { url: 'https://ifconfig.io/ip', cors: false },
  { url: 'https://v4.ident.me', cors: true },
  { url: 'https://ident.me', cors: true },
  { url: 'https://ifconfig.ca/ip', cors: false },
  { url: 'https://ip.gs', cors: false },
  { url: 'https://ip.tyk.nu', cors: false },
  { url: 'https://curlmyip.net', cors: false },
  { url: 'https://wgetip.com', cors: false },
  { url: 'https://myip.wtf/text', cors: true },
  { url: 'https://wtfismyip.com/text', cors: true },
  { url: 'https://ipv4.wtfismyip.com/text', cors: true },
  { url: 'https://myexternalip.com/raw', cors: true },
  { url: 'https://ipecho.net/plain', cors: true },
  { url: 'https://www.trackip.net/ip', cors: false },
  { url: 'https://ipv4.nsupdate.info/myip', cors: false },
  { url: 'https://whatismyip.akamai.com', cors: false }
]);

export const FALLBACK_LIMIT = 8;

export function endpointPreset(url) {
  return ENDPOINT_PRESETS.find((preset) => preset.url === url) || null;
}

// true/false for a known preset, null for a custom URL.
export function endpointSupportsCors(url) {
  const preset = endpointPreset(url);
  return preset === null ? null : preset.cors === true;
}