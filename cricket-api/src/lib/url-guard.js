/**
 * Guard for admin-supplied provider `base_url` values (SEC-3).
 *
 * The admin "test provider" probe does `axios.get(base_url + path)`
 * (admin/routes/providers.routes.js:348), so whatever an admin stores becomes a
 * server-side request. Without a guard that is an SSRF primitive: it can be
 * aimed at `http://127.0.0.1:6379`, a private 10.x service, or the cloud
 * metadata endpoint `http://169.254.169.254/latest/meta-data/`.
 *
 * Honest severity: this is BLIND and requires the `providers.write` permission —
 * the probe returns only status code, latency and the x-cache header, never the
 * response body (providers.routes.js:398-408). So it is defence-in-depth against
 * an insider / stolen admin token / CSRF-style misuse, not a critical hole. It is
 * still worth closing because a status-code oracle plus timing is enough to port
 * scan an internal network, and because `axios` follows redirects by default —
 * a permitted public host can 302 to 169.254.169.254 (see assertSafeRedirect).
 *
 * Deliberately NOT doing DNS resolution + IP pinning here: that is the only way
 * to fully stop DNS rebinding, but it needs a custom agent per request and would
 * change the provider HTTP stack. The private-range checks below cover the
 * literal-IP and localhost cases that make this reachable in practice.
 */

const ALLOWED_PROTOCOLS = new Set(['http:', 'https:']);

// Hostnames that always mean "this machine".
const BLOCKED_HOSTNAMES = new Set([
  'localhost',
  'localhost.localdomain',
  'ip6-localhost',
  'ip6-loopback',
  '[::]',
  '[::1]',
  'metadata',
  'metadata.google.internal',
  'metadata.goog',
]);

function isPrivateIpv4(host) {
  const m = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/.exec(host);
  if (!m) return false;
  const [a, b, c, d] = m.slice(1).map(Number);
  if ([a, b, c, d].some((n) => n > 255)) return true; // malformed -> refuse
  if (a === 0) return true; // 0.0.0.0/8 "this network"
  if (a === 10) return true; // private
  if (a === 127) return true; // loopback
  if (a === 169 && b === 254) return true; // link-local incl. cloud metadata
  if (a === 172 && b >= 16 && b <= 31) return true; // private
  if (a === 192 && b === 168) return true; // private
  if (a === 100 && b >= 64 && b <= 127) return true; // CGNAT
  if (a === 192 && b === 0 && c === 0) return true; // IETF protocol assignments
  if (a === 198 && (b === 18 || b === 19)) return true; // benchmarking
  if (a >= 224) return true; // multicast + reserved + broadcast
  return false;
}

function isPrivateIpv6(host) {
  // URL parsing keeps IPv6 literals in brackets.
  const inner = host.replace(/^\[|\]$/g, '').toLowerCase();
  if (!inner.includes(':')) return false;
  if (inner === '::' || inner === '::1') return true; // unspecified / loopback
  if (inner.startsWith('fe80')) return true; // link-local
  if (/^f[cd]/.test(inner)) return true; // unique local fc00::/7
  // IPv4-mapped / -embedded (::ffff:127.0.0.1, ::ffff:a9fe:a9fe)
  const v4 = /(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})$/.exec(inner);
  if (v4 && isPrivateIpv4(v4[1])) return true;
  if (inner.startsWith('::ffff:') || inner.startsWith('64:ff9b:')) return true;
  return false;
}

/**
 * Validates a provider base URL.
 * @returns {{ ok: true, url: URL } | { ok: false, error: string }}
 */
export function validateProviderBaseUrl(rawValue) {
  const raw = typeof rawValue === 'string' ? rawValue.trim() : '';
  if (!raw) return { ok: false, error: 'base_url is empty' };

  let url;
  try {
    url = new URL(raw);
  } catch {
    return { ok: false, error: 'base_url must be an absolute http(s) URL' };
  }

  if (!ALLOWED_PROTOCOLS.has(url.protocol)) {
    // Blocks file:, gopher:, ftp:, data:, and the unix-socket forms.
    return { ok: false, error: `base_url protocol "${url.protocol}" is not allowed (use http or https)` };
  }

  if (url.username || url.password) {
    // user:pass@host is a classic parser-confusion trick.
    return { ok: false, error: 'base_url must not contain embedded credentials' };
  }

  const host = url.hostname.toLowerCase();
  if (!host) return { ok: false, error: 'base_url has no host' };

  if (BLOCKED_HOSTNAMES.has(host) || host.endsWith('.localhost')) {
    return { ok: false, error: `base_url host "${url.hostname}" points at this machine` };
  }
  if (isPrivateIpv4(host) || isPrivateIpv6(host)) {
    return { ok: false, error: `base_url host "${url.hostname}" is a private, loopback, or link-local address` };
  }
  // Decimal/octal/hex encodings of an IPv4 address (e.g. http://2130706433 = 127.0.0.1).
  if (/^(0x[0-9a-f]+|\d+)$/i.test(host)) {
    return { ok: false, error: `base_url host "${url.hostname}" is a numeric IP encoding` };
  }

  return { ok: true, url };
}

/**
 * Re-checks a URL an HTTP redirect wants to follow. axios defaults to
 * maxRedirects: 5, so a permitted public host could otherwise bounce the probe
 * to the metadata endpoint.
 * @returns {boolean} true when the hop is safe to follow.
 */
export function isSafeRedirectTarget(location) {
  return validateProviderBaseUrl(location).ok;
}
