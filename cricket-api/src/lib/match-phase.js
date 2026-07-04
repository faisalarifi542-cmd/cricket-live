/**
 * Derives a fine-grained match `phase` from a provider's coarse `status` and
 * free-form `status_text`. This is ADDITIVE: the existing coarse `status`
 * field is never changed. The Flutter `MatchStatusDisplay` resolver prefers
 * this `phase` field and falls back to its own status-text heuristic when the
 * field is absent (older cached payloads), so emitting it here makes stoppages
 * (stumps/lunch/tea/innings break/drinks/rain) resolve correctly even when the
 * status text is generic.
 *
 * Canonical phase values:
 *   upcoming · live · stumps · lunch · tea · drinks · rain · innings_break ·
 *   completed · no_result · abandoned · cancelled
 *
 * The text-token order mirrors the Flutter `_phaseFromText` heuristic in
 * lib/utils/match_status.dart so backend and frontend agree.
 */

/**
 * Detects a live stoppage sub-phase from free-form status text.
 * Order matters: "innings break" is checked before a bare "break", "tea break"
 * before a bare "tea", etc. Returns null when no stoppage token is found.
 * @param {string} text
 * @returns {string|null}
 */
export function stoppageFromText(text) {
  const t = String(text || '').toLowerCase();
  if (!t) return null;
  if (t.includes('stumps')) return 'stumps';
  if (t.includes('innings break') || t.includes('innings_break')) {
    return 'innings_break';
  }
  if (t.includes('lunch')) return 'lunch';
  if (t.includes('tea break') || t.includes('tea interval') || t.includes(' tea')) {
    return 'tea';
  }
  if (t.includes('drinks')) return 'drinks';
  if (t.includes('rain') || t.includes('wet outfield') || t.includes('bad light')) {
    return 'rain';
  }
  return null;
}

/**
 * Derive the canonical `phase` for a match.
 * @param {string} status - Coarse provider status (live/upcoming/completed/
 *   innings_break/abandoned/no_result/…). Unknown values are tolerated.
 * @param {string} [statusText=''] - Free-form status text (the source of
 *   stoppage tokens like "Stumps, Day 1").
 * @returns {string} One of the canonical phase values above.
 */
export function derivePhase(status, statusText = '') {
  const t = String(statusText || '');
  const s = String(status || '').toLowerCase();

  // Terminal text overrides a generic 'completed' (e.g. CricketData collapses
  // abandoned/no-result into completed — the text still carries the truth).
  if (t && /abandon/i.test(t)) return 'abandoned';
  if (t && /no\s*result|no_result/i.test(t)) return 'no_result';
  if (t && /cancel/i.test(t)) return 'cancelled';

  switch (s) {
    case 'completed':
      return 'completed';
    case 'abandoned':
      return 'abandoned';
    case 'no_result':
      return 'no_result';
    case 'cancelled':
      return 'cancelled';
    case 'upcoming':
    case 'preview':
      return 'upcoming';
    case 'innings_break':
      // A coarse innings_break is a stoppage, but let a more specific text
      // token (e.g. "lunch") win.
      return stoppageFromText(t) || 'innings_break';
    case 'live':
      break;
    default:
      if (!s) return 'upcoming';
      // Unknown coarse status — treat as live and let the text refine it.
  }

  // Live — refine into a stoppage sub-phase via text, else plain live.
  return stoppageFromText(t) || 'live';
}
