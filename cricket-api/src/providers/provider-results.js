/**
 * Typed provider-result sentinels.
 * ----------------------------------------------------------------------------
 * A provider (e.g. ESPN Cricinfo) implements every BaseProvider method for
 * INTERFACE parity, but not every backend can actually serve every method with
 * usable data. Instead of returning empty-but-successful data (which would make
 * provider-manager stop and hand the caller a blank response), such a method
 * RETURNS one of these sentinels.
 *
 * `provider-manager.execute()` inspects the return value with `isUsableResult`:
 * a sentinel is treated as a soft failure and the manager continues to the next
 * provider in priority order — so a thin ESPN response never masks a fuller
 * Cricbuzz one.
 *
 * These are RETURN VALUES, not thrown errors, so a method returning a sentinel
 * still counts as a successful (up) call for provider health accounting — we do
 * not want ESPN's lack of, say, a balls-map to trip its failover cooldown.
 */

/** The provider will never serve this method (feature genuinely unsupported). */
export class ProviderFeatureNotSupported {
  /**
   * @param {string} method - the BaseProvider method name
   * @param {string} [reason] - optional human-readable reason
   */
  constructor(method, reason = '') {
    this.method = method;
    this.reason = reason || `${method} is not supported by this provider`;
  }
}

/**
 * The provider tried, got a response, but it was too thin to trust (e.g. an
 * ESPN summary whose batting/bowling arrays came back empty). Distinct from
 * FeatureNotSupported so logs/tests can tell "can't" apart from "didn't this time".
 */
export class ProviderIncompleteData {
  /**
   * @param {string} method - the BaseProvider method name
   * @param {string} [reason] - optional human-readable reason
   */
  constructor(method, reason = '') {
    this.method = method;
    this.reason = reason || `${method} returned incomplete data from this provider`;
  }
}

/** @param {*} value @returns {boolean} true when value is a typed sentinel. */
export function isProviderSentinel(value) {
  return (
    value instanceof ProviderFeatureNotSupported ||
    value instanceof ProviderIncompleteData
  );
}

/**
 * True when a provider method's return value is usable data the manager may
 * return to the caller. A typed sentinel is NOT usable (fall through to the
 * next provider). `null`/`undefined` are also treated as not usable, so a
 * provider that returns nothing is skipped rather than shadowing a real result.
 * Everything else (arrays incl. empty, objects, primitives) is usable — callers
 * that need "non-empty" semantics should return an explicit sentinel instead.
 *
 * @param {*} value
 * @returns {boolean}
 */
export function isUsableResult(value) {
  if (value == null) return false;
  if (isProviderSentinel(value)) return false;
  return true;
}
