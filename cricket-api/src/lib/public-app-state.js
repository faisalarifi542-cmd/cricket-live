import { query } from './db.js';

function parseJsonMaybe(value, fallback = null) {
  if (value == null) return fallback;
  if (typeof value !== 'string') return value;
  try {
    return JSON.parse(value);
  } catch {
    return fallback;
  }
}

function normalizeBool(value, fallback = false) {
  if (value == null) return fallback;
  if (typeof value === 'boolean') return value;
  if (typeof value === 'number') return value !== 0;
  const text = String(value).trim().toLowerCase();
  if (['1', 'true', 'yes', 'on'].includes(text)) return true;
  if (['0', 'false', 'no', 'off'].includes(text)) return false;
  return fallback;
}

const PUBLIC_SETTING_KEYS = new Set([
  'appName',
  'appEnvironment',
  'appMaintenanceMode',
  'maintenanceTitle',
  'maintenanceMessage',
  'forceUpdateEnabled',
  'minimumVersion',
  'latestVersion',
  'androidUpdateUrl',
  'iosUpdateUrl',
  'enableLiveScores',
  'enableLiveStreaming',
  'enableNews',
  'enableRankings',
  'enableSchedule',
  'enableSeries',
  'enableNotifications',
  'enableAds',
  'defaultHomeTab',
  'defaultStreamQuality',
  'streamUnavailableMessage',
  'liveScoreRefreshSeconds',
  'liveMatchesRefreshSeconds',
  'liveLineRefreshSeconds',
  'scorecardRefreshSeconds',
  'commentaryRefreshSeconds',
  'oversRefreshSeconds',
  'scheduleRefreshMinutes',
  'newsRefreshMinutes',
  'homeRefreshSeconds',
  'primaryColor',
  'accentColor',
  'oneSignalAppId',
  'adsTestMode',
]);

const SENSITIVE_KEY_RE = /(secret|password|token|jwt|private|rest.*key|api.*key|database|db_|connection)/i;

function isSafePublicSettingKey(key) {
  return PUBLIC_SETTING_KEYS.has(key) && !SENSITIVE_KEY_RE.test(key);
}

function toNumber(value, fallback = null) {
  if (value == null || value === '') return fallback;
  const num = Number(value);
  return Number.isFinite(num) ? num : fallback;
}

function apiString(value, fallback = '') {
  if (value == null) return fallback;
  const text = String(value).trim();
  return text || fallback;
}

function pick(row, keys, fallback = null) {
  for (const key of keys) {
    if (row?.[key] != null && row[key] !== '') return row[key];
  }
  return fallback;
}

function normalizeStreamType(value) {
  const type = String(value || 'hls').toLowerCase();
  return type === 'mpd' ? 'dash' : type;
}

function publicHeaders(row) {
  const headers = {
    ...(row?.user_agent_header ? { 'User-Agent': row.user_agent_header } : {}),
    ...(row?.referer_header ? { Referer: row.referer_header } : {}),
    ...(row?.origin_header ? { Origin: row.origin_header } : {}),
  };
  const custom = parseJsonMaybe(row?.headers_json || row?.headers || row?.request_headers, null);
  if (custom && typeof custom === 'object' && !Array.isArray(custom)) {
    for (const [key, value] of Object.entries(custom)) {
      if (value != null && !headers[key]) headers[key] = String(value);
    }
  }
  return headers;
}

function publicDrm(row) {
  if (!normalizeBool(row?.drm_enabled, false)) {
    return { type: 'none' };
  }
  const headers = parseJsonMaybe(row?.drm_headers || row?.drmHeaders, {}) || {};
  return {
    type: String(row?.drm_type || row?.drmType || 'none').toLowerCase() || 'none',
    licenseUrl: row?.drm_license_url || row?.drmLicenseUrl || null,
    headers: headers && typeof headers === 'object' ? headers : {},
    keyId: row?.clear_key_key_id || row?.clearKeyKeyId || null,
    key: row?.clear_key_key || row?.clearKeyKey || null,
  };
}

export function publicStreamDto(row) {
  if (!row) return null;
  const quality = String(pick(row, ['quality'], 'AUTO') || 'AUTO').toUpperCase();
  const label = pick(row, ['label'], quality) || quality;
  const url = pick(row, ['stream_url', 'streamUrl'], '');
  return {
    id: String(row.id),
    title: pick(row, ['title'], label || quality) || label || quality,
    type: normalizeStreamType(pick(row, ['stream_type', 'streamType'], 'hls')),
    url,
    backupUrl: pick(row, ['backup_stream_url', 'backupStreamUrl'], null),
    quality,
    qualityLabel: label || quality,
    language: pick(row, ['language'], 'English'),
    serverName: pick(row, ['server_name', 'serverName'], 'Server'),
    isPremium: normalizeBool(pick(row, ['is_premium', 'isPremium'], false), false),
    requiresRewardAd: normalizeBool(pick(row, ['requires_reward_ad', 'requiresRewardAd'], false), false),
    requiresLogin: normalizeBool(pick(row, ['requires_login', 'requiresLogin'], false), false),
    priority: toNumber(row.priority, 100),
    status: pick(row, ['status'], 'unknown') || 'unknown',
    headers: publicHeaders(row),
    drm: publicDrm(row),
  };
}

export function streamLifecycleStatus(row) {
  const now = Date.now();
  const startsAt = row?.starts_at ? new Date(row.starts_at).getTime() : null;
  const endsAt = row?.ends_at ? new Date(row.ends_at).getTime() : null;
  if (normalizeBool(row?.is_active, true) === false) return 'inactive';
  if (endsAt && endsAt < now) return 'expired';
  if (startsAt && startsAt > now) return 'scheduled';
  return 'active';
}

export async function fetchActiveStreamsForMatch(matchId) {
  if (!matchId) return [];
  const rows = await query(
    `SELECT * FROM match_streams
      WHERE match_external_id = ?
        AND is_active = 1
        AND (starts_at IS NULL OR starts_at <= NOW())
        AND (ends_at IS NULL OR ends_at >= NOW())
      ORDER BY priority ASC, id ASC`,
    [matchId],
  ).catch(() => []);
  return rows.map((row) => ({
    ...row,
    lifecycle_status: streamLifecycleStatus(row),
  }));
}

export async function fetchStreamSummaryByMatchIds(matchIds = []) {
  const ids = [...new Set(matchIds.map((id) => String(id || '').trim()).filter(Boolean))];
  if (!ids.length) return new Map();
  const placeholders = ids.map(() => '?').join(', ');
  const rows = await query(
    `SELECT match_external_id, COUNT(*) AS stream_count,
            SUM(CASE WHEN is_premium = 1 THEN 1 ELSE 0 END) AS premium_count,
            MIN(priority) AS min_priority
       FROM match_streams
      WHERE match_external_id IN (${placeholders})
        AND is_active = 1
        AND (starts_at IS NULL OR starts_at <= NOW())
        AND (ends_at IS NULL OR ends_at >= NOW())
      GROUP BY match_external_id`,
    ids,
  ).catch(() => []);
  return new Map(
    rows.map((row) => [
      String(row.match_external_id),
      {
        streamCount: Number(row.stream_count || 0),
        premiumCount: Number(row.premium_count || 0),
        minPriority: Number(row.min_priority || 100),
      },
    ]),
  );
}

function matchIdFromItem(item) {
  return String(
    item?.match_id ||
      item?.matchId ||
      item?.id ||
      item?.match_external_id ||
      item?.matchExternalId ||
      '',
  ).trim();
}

export function applyStreamMeta(match, summary = null, { allowReplay = false } = {}) {
  const streamCount = Number(summary?.streamCount || 0);
  const premiumCount = Number(summary?.premiumCount || 0);
  const status = String(match?.status || match?.matchStatus || '').toLowerCase();
  const isRecent = ['recent', 'completed', 'finished', 'result'].includes(status);
  const hasLiveStream = streamCount > 0 && (!isRecent || allowReplay);
  return {
    ...match,
    hasLiveStream,
    watchLiveEnabled: hasLiveStream,
    streamCount,
    isPremiumStreamAvailable: premiumCount > 0,
    streamBadgeText: hasLiveStream
      ? (premiumCount > 0 ? 'Premium' : 'LIVE STREAM')
      : null,
    defaultStreamId: summary?.defaultStreamId || null,
  };
}

export function isLiveStreamingFeatureEnabled(config = {}) {
  return normalizeBool(
    config?.features?.liveStreamsEnabled ??
      config?.features?.liveStreaming ??
      config?.enableLiveStreaming,
    true,
  );
}

export async function enrichMatchListWithStreams(matches = [], { allowReplay = false } = {}) {
  const ids = matches.map((match) => matchIdFromItem(match)).filter(Boolean);
  const [summaries, config] = await Promise.all([
    fetchStreamSummaryByMatchIds(ids),
    buildPublicAppConfig().catch(() => ({ enableLiveStreaming: true })),
  ]);
  const liveStreamsEnabled = isLiveStreamingFeatureEnabled(config);
  return matches.map((match) => {
    const id = matchIdFromItem(match);
    const enriched = applyStreamMeta(match, summaries.get(id) || null, { allowReplay });
    return {
      ...enriched,
      watchLiveEnabled: liveStreamsEnabled && enriched.watchLiveEnabled,
    };
  });
}

export async function buildPublicAppConfig() {
  const [settingsRows, adRows] = await Promise.all([
    query(`SELECT setting_key, setting_value FROM app_settings WHERE is_public = 1 OR is_public IS NULL`).catch(() => []),
    query(`SELECT setting_key, setting_value FROM ad_settings WHERE is_public = 1 OR is_public IS NULL`).catch(() => []),
  ]);

  const legacy = {
    appName: 'CricPro',
    appEnvironment: process.env.NODE_ENV || 'production',
    appMaintenanceMode: false,
    maintenanceTitle: 'Maintenance in progress',
    maintenanceMessage: 'CricPro is being tuned. Please check back soon.',
    forceUpdateEnabled: false,
    enableLiveScores: true,
    enableLiveStreaming: true,
    enableNews: true,
    enableRankings: true,
    enableSchedule: true,
    enableSeries: true,
    enableNotifications: true,
    enableAds: false,
    defaultHomeTab: 'live',
    defaultStreamQuality: 'AUTO',
    streamUnavailableMessage: 'Live stream will be available closer to match time.',
    liveScoreRefreshSeconds: 5,
    liveMatchesRefreshSeconds: 10,
    liveLineRefreshSeconds: 5,
    scorecardRefreshSeconds: 30,
    commentaryRefreshSeconds: 30,
    oversRefreshSeconds: 20,
    scheduleRefreshMinutes: 5,
    newsRefreshMinutes: 5,
    homeRefreshSeconds: 30,
    primaryColor: '#06b6d4',
    accentColor: '#3b82f6',
  };

  const settings = { ...legacy };
  for (const row of settingsRows) {
    const key = row.setting_key;
    if (!isSafePublicSettingKey(key)) continue;
    const value = parseJsonMaybe(row.setting_value, row.setting_value);
    settings[key] = value;
  }

  const adsValue = parseJsonMaybe(
    adRows.find((row) => row.setting_key === 'ads_config')?.setting_value,
    {},
  );

  const ads = {
    enabled: normalizeBool(settings.enableAds ?? adsValue?.show_ads, false),
    testMode: normalizeBool(adsValue?.test_mode ?? settings.adsTestMode, false),
    admobEnabled: normalizeBool(adsValue?.admob_enabled ?? adsValue?.show_ads, true),
    unityEnabled: normalizeBool(adsValue?.unity_enabled, false),
    metaEnabled: normalizeBool(adsValue?.meta_enabled, false),
    rewardedEnabled: normalizeBool(adsValue?.rewarded_enabled, false),
    bannerEnabled: normalizeBool(adsValue?.banner_enabled ?? true, true),
    nativeEnabled: normalizeBool(adsValue?.native_enabled ?? true, true),
    interstitialEnabled: normalizeBool(adsValue?.interstitial_enabled ?? true, true),
    frequencyMinutes: toNumber(adsValue?.frequency_minutes, 5),
    android: {
      bannerId: adsValue?.android_banner_id || null,
      nativeId: adsValue?.android_native_id || null,
      interstitialId: adsValue?.android_interstitial_id || null,
      rewardedId: adsValue?.android_rewarded_id || null,
    },
    ios: {
      bannerId: adsValue?.ios_banner_id || null,
      nativeId: adsValue?.ios_native_id || null,
      interstitialId: adsValue?.ios_interstitial_id || null,
      rewardedId: adsValue?.ios_rewarded_id || null,
    },
    placementConfig: parseJsonMaybe(adsValue?.placement_config, null) || {},
    frequencyConfig: parseJsonMaybe(adsValue?.frequency_config, null) || {},
  };
  ads.units = {
    android: ads.android,
    ios: ads.ios,
  };
  ads.placements = {
    home: {
      bannerEnabled: normalizeBool(adsValue?.home_banner_enabled, true),
      nativeEnabled: normalizeBool(adsValue?.home_native_enabled, true),
      nativeEvery: toNumber(adsValue?.home_native_every, 5),
    },
    matches: {
      bannerEnabled: normalizeBool(adsValue?.matches_banner_enabled, true),
      nativeEnabled: normalizeBool(adsValue?.matches_native_enabled, true),
      nativeEvery: toNumber(adsValue?.matches_native_every, 5),
    },
    matchDetails: {
      bannerEnabled: normalizeBool(adsValue?.match_details_banner_enabled, true),
      nativeEnabled: normalizeBool(adsValue?.match_details_native_enabled, true),
    },
    news: {
      bannerEnabled: normalizeBool(adsValue?.news_banner_enabled, true),
      nativeEnabled: normalizeBool(adsValue?.news_native_enabled, true),
      nativeEvery: toNumber(adsValue?.news_native_every, 4),
    },
    series: {
      bannerEnabled: normalizeBool(adsValue?.series_banner_enabled, true),
      nativeEnabled: normalizeBool(adsValue?.series_native_enabled, true),
      nativeEvery: toNumber(adsValue?.series_native_every, 6),
    },
    more: {
      bannerEnabled: normalizeBool(adsValue?.more_banner_enabled, true),
      nativeEnabled: false,
    },
    livePlayer: {
      bannerEnabled: normalizeBool(adsValue?.live_player_banner_enabled, false),
      nativeEnabled: false,
    },
    ...ads.placementConfig,
  };
  ads.frequency = {
    interstitialFrequencyCap: toNumber(adsValue?.interstitial_frequency_cap, 1),
    minimumSecondsBetweenInterstitials: toNumber(
      adsValue?.minimum_seconds_between_interstitials,
      toNumber(adsValue?.frequency_minutes, 5) * 60,
    ),
    ...ads.frequencyConfig,
  };
  ads.rewardedRequiredForPremiumStreams = normalizeBool(
    adsValue?.rewarded_required_for_premium_streams,
    false,
  );

  const features = {
    liveScores: normalizeBool(settings.enableLiveScores, true),
    liveStreaming: normalizeBool(settings.enableLiveStreaming, true),
    liveStreamsEnabled: normalizeBool(settings.enableLiveStreaming, true),
    news: normalizeBool(settings.enableNews, true),
    rankings: normalizeBool(settings.enableRankings, true),
    schedule: normalizeBool(settings.enableSchedule, true),
    series: normalizeBool(settings.enableSeries, true),
    notifications: normalizeBool(settings.enableNotifications, true),
    notificationsEnabled: normalizeBool(settings.enableNotifications, true),
    ads: normalizeBool(settings.enableAds, false),
    adsEnabled: normalizeBool(settings.enableAds, false),
    premiumStreams: normalizeBool(settings.enableLiveStreaming, true),
    premiumStreamsEnabled: normalizeBool(settings.enableLiveStreaming, true),
    newsEnabled: normalizeBool(settings.enableNews, true),
    seriesEnabled: normalizeBool(settings.enableSeries, true),
  };

  const notifications = {
    enabled: normalizeBool(settings.enableNotifications, true),
    oneSignalAppId: process.env.ONESIGNAL_APP_ID || settings.oneSignalAppId || null,
    permissionPromptMode: apiString(settings.notificationPermissionPromptMode, 'later'),
    defaultChannel: 'general',
    clickActions: {
      match: 'cricpro://match/:id',
      liveStream: 'cricpro://match/:id/live',
      news: 'cricpro://news/:id',
      series: 'cricpro://series/:id',
    },
  };

  const player = {
    defaultStreamQuality: apiString(settings.defaultStreamQuality, 'AUTO'),
    defaultUnavailableMessage: apiString(
      settings.streamUnavailableMessage,
      'Live stream is not available yet.',
    ),
    streamUnavailableMessage: apiString(
      settings.streamUnavailableMessage,
      'Live stream will be available closer to match time.',
    ),
    allowLandscape: normalizeBool(settings.playerAllowLandscape, true),
    showQualitySelector: normalizeBool(settings.playerShowQualitySelector, true),
    liveScoreRefreshSeconds: toNumber(settings.liveScoreRefreshSeconds, 5),
    liveLineRefreshSeconds: toNumber(settings.liveLineRefreshSeconds, 5),
    scorecardRefreshSeconds: toNumber(settings.scorecardRefreshSeconds, 30),
    commentaryRefreshSeconds: toNumber(settings.commentaryRefreshSeconds, 30),
    oversRefreshSeconds: toNumber(settings.oversRefreshSeconds, 20),
  };

  const app = {
    appName: apiString(settings.appName, 'CricPro'),
    environment: apiString(settings.appEnvironment, process.env.NODE_ENV || 'production'),
    maintenanceMode: normalizeBool(settings.appMaintenanceMode, false),
    maintenanceTitle: apiString(settings.maintenanceTitle, 'Maintenance in progress'),
    maintenanceMessage: apiString(
      settings.maintenanceMessage,
      'CricPro is being tuned. Please check back soon.',
    ),
    forceUpdateEnabled: normalizeBool(settings.forceUpdateEnabled, false),
    minimumVersion: apiString(settings.minimumVersion, null),
    latestVersion: apiString(settings.latestVersion, null),
    androidUpdateUrl: apiString(settings.androidUpdateUrl, null),
    iosUpdateUrl: apiString(settings.iosUpdateUrl, null),
    defaultHomeTab: apiString(settings.defaultHomeTab, 'live'),
    primaryColor: apiString(settings.primaryColor, '#06b6d4'),
    accentColor: apiString(settings.accentColor, '#3b82f6'),
  };

  return {
    ...settings,
    ...app,
    maintenanceMode: app.maintenanceMode,
    forceUpdateEnabled: app.forceUpdateEnabled,
    defaultHomeTab: app.defaultHomeTab,
    defaultStreamQuality: player.defaultStreamQuality,
    streamUnavailableMessage: player.streamUnavailableMessage,
    enableLiveScores: features.liveScores,
    enableLiveStreaming: features.liveStreaming,
    enableNews: features.news,
    enableRankings: features.rankings,
    enableSchedule: features.schedule,
    enableSeries: features.series,
    enableNotifications: features.notifications,
    enableAds: features.ads,
    ads,
    notifications,
    features,
    player,
    app,
    legacy,
  };
}
