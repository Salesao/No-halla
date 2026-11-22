// IPv4 parsing and CIDR matching for the trusted-address list.
// Port of NoHalla/Core/Network/CIDR.swift (IPv4 only; no IPv6).
// Pure module: no chrome APIs, no I/O. Every bitwise result is coerced with
// `>>> 0` because JS bitwise operators are signed 32-bit.

const IPV4_OCTET_RE = /^\d{1,3}$/;
const IPV4_RE = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/;
// Prefix: "0".."32" with no leading zeros ("08" is invalid).
const PREFIX_RE = /^(0|[1-9]\d?)$/;
const FULL_MASK = 0xffffffff;

/**
 * Parse a strict dotted-quad IPv4 string into an unsigned 32-bit number.
 * @param {string} str
 * @returns {number|null} 0..2^32-1, or null when invalid.
 */
export function parseIPv4(str) {
  if (typeof str !== 'string') return null;

  const trimmed = str.trim();
  if (!IPV4_RE.test(trimmed)) return null;

  const parts = trimmed.split('.');
  let value = 0;

  for (const part of parts) {
    if (!IPV4_OCTET_RE.test(part)) return null;
    // Leading zeros are rejected: "01" is ambiguous (octal in some parsers).
    if (part.length > 1 && part[0] === '0') return null;

    const octet = Number(part);
    if (octet > 255) return null;

    value = (value << 8) | octet;
  }

  return value >>> 0;
}

/**
 * Parse a bare IPv4 address (implicit /32) or "a.b.c.d/0..32".
 * @param {string} str
 * @returns {{base: number, mask: number}|null} base is the network address.
 */
export function parseCIDR(str) {
  if (typeof str !== 'string') return null;

  const trimmed = str.trim();
  if (trimmed === '') return null;

  const parts = trimmed.split('/');
  if (parts.length > 2) return null;

  const ip = parseIPv4(parts[0]);
  if (ip === null) return null;

  if (parts.length === 1) {
    return { base: ip, mask: FULL_MASK };
  }

  const prefixText = parts[1];
  if (!PREFIX_RE.test(prefixText)) return null;

  const prefix = Number(prefixText);
  if (prefix > 32) return null;

  // `/0` must be special-cased: `0xffffffff << 32` is `0xffffffff << 0` in JS.
  const mask = prefix === 0 ? 0 : (FULL_MASK << (32 - prefix)) >>> 0;

  return { base: (ip & mask) >>> 0, mask };
}

/**
 * Test whether an IPv4 address (already parsed) falls inside a CIDR block.
 * @param {number} ip unsigned 32-bit address
 * @param {{base: number, mask: number}} cidr parsed CIDR
 * @returns {boolean}
 */
export function matchCIDR(ip, cidr) {
  if (typeof ip !== 'number' || !Number.isInteger(ip) || ip < 0 || ip > FULL_MASK) {
    return false;
  }
  if (cidr === null || typeof cidr !== 'object') return false;
  if (!Number.isInteger(cidr.base) || !Number.isInteger(cidr.mask)) return false;
  if (cidr.base < 0 || cidr.base > FULL_MASK) return false;
  if (cidr.mask < 0 || cidr.mask > FULL_MASK) return false;

  const mask = cidr.mask >>> 0;
  const base = cidr.base >>> 0;
  return ((ip & mask) >>> 0) === ((base & mask) >>> 0);
}

/**
 * Test an IPv4 string against a list of IPv4/CIDR strings.
 * Invalid list entries are skipped; a non-array list yields false.
 * @param {string} ipStr
 * @param {string[]} list
 * @returns {boolean}
 */
export function ipInTrustedList(ipStr, list) {
  const ip = parseIPv4(ipStr);
  if (ip === null || !Array.isArray(list)) return false;

  for (const entry of list) {
    if (typeof entry !== 'string') continue;
    const cidr = parseCIDR(entry);
    if (cidr === null) continue;
    if (matchCIDR(ip, cidr)) return true;
  }

  return false;
}