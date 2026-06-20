import { query } from './db.js';

// Category key -> the OneSignal tag the app writes for it (see the Flutter
// NotificationService.syncCategoryTags: tags are `notif_<key>` = '1' | '0').
// A category send is delivered only to devices whose tag is not '0', so a user
// who toggled the category off is never targeted.
const CATEGORY_TAGS = new Set([
  'live_scores',
  'match_start',
  'toss',
  'wickets',
  'innings_result',
  'live_stream',
  'favorite_team',
  'news',
  'announcements',
]);

function categoryFilter(categoryKey) {
  const tag = `notif_${categoryKey}`;
  // relation '!=' value '0' matches devices tagged '1' AND devices that never
  // set the tag (defaults are on), while excluding anyone who set it to '0'.
  return {
    filters: [{ field: 'tag', key: tag, relation: '!=', value: '0' }],
  };
}

// Favourite targeting: the app tags each followed country/team code as
// `fav_<CODE>` = '1'. A favourite send ANDs the category opt-in with at least
// one matching favourite tag (OneSignal OR-joins via {operator:'OR'}).
function favoriteFilter(categoryKey, codesCsv) {
  const codes = String(codesCsv || '')
    .split(',')
    .map((c) => c.trim().toUpperCase())
    .filter(Boolean);
  const filters = [{ field: 'tag', key: `notif_${categoryKey}`, relation: '!=', value: '0' }];
  if (codes.length) {
    filters.push({ operator: 'AND' });
    codes.forEach((code, i) => {
      if (i > 0) filters.push({ operator: 'OR' });
      filters.push({ field: 'tag', key: `fav_${code}`, relation: '=', value: '1' });
    });
  }
  return { filters };
}

function targetFilter(targetType, targetValue) {
  if (targetType === 'android') return { included_segments: ['Android Users'] };
  if (targetType === 'ios') return { included_segments: ['iOS Users'] };
  if (targetType === 'subscription' && targetValue) {
    return { include_subscription_ids: [targetValue] };
  }
  // Category-aware send: target_value is the category key (e.g. 'live_stream').
  if (targetType === 'category' && targetValue && CATEGORY_TAGS.has(targetValue)) {
    return categoryFilter(targetValue);
  }
  // Favourite send: target_value is "<categoryKey>:<CODE,CODE,...>". The
  // category gates the opt-in; the codes restrict to followed teams/countries.
  if (targetType === 'favorite' && targetValue) {
    const [categoryKey, codesCsv] = String(targetValue).split(':');
    const key = CATEGORY_TAGS.has(categoryKey) ? categoryKey : 'favorite_team';
    return favoriteFilter(key, codesCsv);
  }
  return { included_segments: ['All'] };
}

export function buildNotificationPayload(notification = {}) {
  const targetType = notification.target_type || notification.targetType || 'all';
  const targetValue = notification.target_value || notification.targetValue || null;
  const deepLinkType = notification.deep_link_type || notification.deepLinkType || notification.type || null;
  const deepLinkValue = notification.deep_link_value || notification.deepLinkValue || notification.matchId || notification.newsId || notification.seriesId || null;
  const data = {
    ...(notification.payload && typeof notification.payload === 'object' ? notification.payload : {}),
    ...(deepLinkType ? { type: deepLinkType } : {}),
    ...(deepLinkType === 'match' && deepLinkValue ? { matchId: String(deepLinkValue) } : {}),
    ...(deepLinkType === 'live_stream' && deepLinkValue ? { matchId: String(deepLinkValue) } : {}),
    ...(deepLinkType === 'news' && deepLinkValue ? { newsId: String(deepLinkValue) } : {}),
    ...(deepLinkType === 'series' && deepLinkValue ? { seriesId: String(deepLinkValue) } : {}),
    ...(notification.deepLink ? { deepLink: notification.deepLink } : {}),
  };
  return {
    app_id: process.env.ONESIGNAL_APP_ID,
    ...targetFilter(targetType, targetValue),
    headings: { en: notification.title },
    contents: { en: notification.body },
    ...(notification.image_url ? { big_picture: notification.image_url, ios_attachments: { image: notification.image_url } } : {}),
    data,
  };
}

export async function sendOneSignalNotification(notification = {}) {
  if (!process.env.ONESIGNAL_APP_ID) throw new Error('ONESIGNAL_APP_ID is not configured');
  if (!process.env.ONESIGNAL_REST_API_KEY) throw new Error('ONESIGNAL_REST_API_KEY is not configured');
  if (!notification.title || !notification.body) throw new Error('title and body required');
  const payload = buildNotificationPayload(notification);
  const response = await fetch('https://onesignal.com/api/v1/notifications', {
    method: 'POST',
    headers: {
      Authorization: `Basic ${process.env.ONESIGNAL_REST_API_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(payload),
  });
  const text = await response.text();
  let json = {};
  try { json = text ? JSON.parse(text) : {}; } catch { json = { raw: text }; }
  if (!response.ok) {
    const err = new Error(json?.errors?.[0] || json?.error || `OneSignal returned ${response.status}`);
    err.providerResponse = json;
    throw err;
  }
  return { payload, response: json };
}

export async function recordNotificationHistory({
  notificationId = null,
  notification,
  payload = null,
  providerResponse = null,
  status = 'sent',
  errorMessage = null,
}) {
  await query(
    `INSERT INTO notification_history
      (notification_id, provider, target_type, target_value, title, body, payload, provider_response, status, sent_count, failed_count, error_message)
     VALUES (?, 'onesignal', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    [
      notificationId,
      notification.target_type || notification.targetType || 'all',
      notification.target_value || notification.targetValue || null,
      notification.title,
      notification.body,
      payload ? JSON.stringify(payload) : null,
      providerResponse ? JSON.stringify(providerResponse) : null,
      status,
      status === 'sent' ? 1 : 0,
      status === 'sent' ? 0 : 1,
      errorMessage,
    ],
  ).catch(() => null);
}
