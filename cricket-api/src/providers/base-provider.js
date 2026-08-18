/**
 * Base provider interface.
 * All data providers (Cricbuzz, Cricinfo, CricketData) must extend this.
 */
export class BaseProvider {
  constructor(name, priority = 0) {
    this.name = name;
    this.priority = priority;
    this.healthy = true;
    this.consecutiveFailures = 0;
    this.lastFailure = null;
    this.maxConsecutiveFailures = 5;
    this.cooldownMs = 60_000; // 1 minute cooldown after max failures
  }

  /** Check if provider is available */
  isAvailable() {
    if (this.healthy) return true;
    // Auto-recover after cooldown
    if (this.lastFailure && Date.now() - this.lastFailure > this.cooldownMs) {
      this.healthy = true;
      this.consecutiveFailures = 0;
      return true;
    }
    return false;
  }

  recordSuccess() {
    this.consecutiveFailures = 0;
    this.healthy = true;
  }

  recordFailure() {
    this.consecutiveFailures++;
    this.lastFailure = Date.now();
    if (this.consecutiveFailures >= this.maxConsecutiveFailures) {
      this.healthy = false;
    }
  }

  // --- Admin-facing metadata (overridden by subclasses) ---

  /** @returns {'up'|'down'|'limited'|'misconfigured'|'disabled'} */
  healthState() {
    return this.healthy ? 'up' : 'down';
  }

  /** @returns {boolean} true when provider has all required config (keys, base URL, etc.) */
  isConfigured() {
    return true; // most providers need no extra config
  }

  /** @returns {string|null} human-readable reason when !isConfigured(), null otherwise */
  configReason() {
    return null;
  }

  /**
   * Return a static map of method → support level so the admin panel can render
   * what each provider actually does without probing every method at runtime.
   * Override in each subclass.
   * @returns {{[method: string]: 'full'|'limited'|'unsupported'}}
   */
  getCapabilities() {
    return {};
  }

  // --- Methods to implement ---

  /** @returns {Promise<Array>} list of live matches */
  async getLiveMatches() {
    throw new Error(`${this.name}: getLiveMatches not implemented`);
  }

  /** @returns {Promise<Array>} list of upcoming matches */
  async getUpcomingMatches() {
    throw new Error(`${this.name}: getUpcomingMatches not implemented`);
  }

  /** @returns {Promise<Array>} list of recent matches */
  async getRecentMatches() {
    throw new Error(`${this.name}: getRecentMatches not implemented`);
  }

  /** @returns {Promise<Object>} match details */
  async getMatchInfo(matchId) {
    throw new Error(`${this.name}: getMatchInfo not implemented`);
  }

  /** @returns {Promise<Object>} match stats */
  async getMatchStats(matchId) {
    throw new Error(`${this.name}: getMatchStats not implemented`);
  }

  /** @returns {Promise<Object>} match overs data */
  async getMatchOvers(matchId) {
    throw new Error(`${this.name}: getMatchOvers not implemented`);
  }

  /** @returns {Promise<Object>} scorecard */
  async getScorecard(matchId) {
    throw new Error(`${this.name}: getScorecard not implemented`);
  }

  /** @returns {Promise<Array>} commentary entries */
  async getCommentary(matchId) {
    throw new Error(`${this.name}: getCommentary not implemented`);
  }

  /** @returns {Promise<Array>} series list */
  async getSeriesList() {
    throw new Error(`${this.name}: getSeriesList not implemented`);
  }

  /** @returns {Promise<Object>} series details */
  async getSeriesInfo(seriesId) {
    throw new Error(`${this.name}: getSeriesInfo not implemented`);
  }

  /** @returns {Promise<Array>} points table */
  async getPointsTable(seriesId) {
    throw new Error(`${this.name}: getPointsTable not implemented`);
  }

  /** @returns {Promise<Object>} player info */
  async getPlayerInfo(playerId) {
    throw new Error(`${this.name}: getPlayerInfo not implemented`);
  }

  /** @returns {Promise<Object>} team info */
  async getTeamInfo(teamId) {
    throw new Error(`${this.name}: getTeamInfo not implemented`);
  }

  /** @returns {Promise<Object>} news stories list */
  async getNewsStories(cursor) {
    throw new Error(`${this.name}: getNewsStories not implemented`);
  }

  /** @returns {Promise<Object>} series stats types/menu */
  async getSeriesStatsTypes(seriesId) {
    throw new Error(`${this.name}: getSeriesStatsTypes not implemented`);
  }

  /** @returns {Promise<Object>} series stats table for a stat type */
  async getSeriesStatsTable(seriesId, statType) {
    throw new Error(`${this.name}: getSeriesStatsTable not implemented`);
  }

  async getSeriesNews(seriesId, cursor) {
    throw new Error(`${this.name}: getSeriesNews not implemented`);
  }

  async getMatchNews(matchId, cursor) {
    throw new Error(`${this.name}: getMatchNews not implemented`);
  }

  async getFullCommentary(matchId, inningsId) {
    throw new Error(`${this.name}: getFullCommentary not implemented`);
  }

  async getHighlights(matchId, inningsId) {
    throw new Error(`${this.name}: getHighlights not implemented`);
  }

  async getBallsMap(matchId, inningsId) {
    throw new Error(`${this.name}: getBallsMap not implemented`);
  }

  async getOverByOver(matchId, inningsId) {
    throw new Error(`${this.name}: getOverByOver not implemented`);
  }

  async getUpcomingSchedule(type, timestamp) {
    throw new Error(`${this.name}: getUpcomingSchedule not implemented`);
  }

  /** @returns {Promise<Object|null>} match header (fallback for upcoming matches) */
  async getMatchHeader(matchId) {
    return null;
  }
}
