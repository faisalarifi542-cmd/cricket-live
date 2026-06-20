/**
 * Provider fetch-by-ID helpers for the Admin Panel auto-fill tools.
 * ----------------------------------------------------------------------------
 * The Admin Panel lets operators type a provider ID (Cricbuzz player/team/match
 * id) and "Fetch" the record so the form auto-fills. These helpers run the
 * provider request through the shared `providerManager` so they automatically
 * follow the DB-configured priority + failover (admin → next enabled provider),
 * then shape the result into the flat field set the admin forms expect.
 *
 * They never throw for "not found" — callers get a normalized object or `null`
 * plus the originating provider name. A thrown error means every provider
 * failed (network/auth), which the route surfaces as a clear message.
 */
import providerManager from '../providers/provider-manager.js';
import { getPlayerImageUrl, getTeamLogoUrl, getMatchImageUrl } from './image-helper.js';

function str(value) {
  if (value == null) return '';
  const text = String(value).trim();
  return text && text !== '-' && text.toLowerCase() !== 'tbd' ? text : '';
}

/** Resolve a usable image URL: explicit url first, else build from an imageId. */
function imageFrom(url, imageId, kind) {
  const direct = str(url);
  if (direct) return direct;
  const id = str(imageId);
  if (!id) return '';
  if (kind === 'team') return getTeamLogoUrl(id) || '';
  if (kind === 'match') return getMatchImageUrl(id) || '';
  return getPlayerImageUrl(id) || '';
}

/**
 * Fetch a player by provider id and shape it for the admin player form.
 * @returns {Promise<{ provider: string, data: object } | null>}
 */
export async function fetchPlayerByProviderId(playerId) {
  const id = str(playerId);
  if (!id) return null;
  const { data, provider } = await providerManager.execute('getPlayerInfo', id);
  if (!data) return null;
  return {
    provider,
    data: {
      provider_player_id: str(data.player_id) || id,
      external_id: str(data.player_id) || id,
      player_external_id: str(data.player_id) || id,
      name: str(data.name) || str(data.full_name),
      full_name: str(data.full_name) || str(data.name),
      display_name: str(data.name) || str(data.full_name),
      short_name: str(data.short_name),
      country: str(data.country) || str(data.nationality),
      role: str(data.role),
      batting_style: str(data.batting_style),
      bowling_style: str(data.bowling_style),
      dob: data.dob || null,
      birth_place: str(data.birth_place),
      profile_url: str(data.profile_url),
      provider_image_url: imageFrom(data.image_url, data.image_id, 'player'),
      image_id: str(data.image_id),
    },
  };
}

/**
 * Fetch a team by provider id and shape it for the admin team form.
 * @returns {Promise<{ provider: string, data: object } | null>}
 */
export async function fetchTeamByProviderId(teamId) {
  const id = str(teamId);
  if (!id) return null;
  const { data, provider } = await providerManager.execute('getTeamInfo', id);
  if (!data) return null;
  return {
    provider,
    data: {
      provider_team_id: str(data.team_id) || id,
      external_id: str(data.team_id) || id,
      name: str(data.name) || str(data.short_name),
      short_name: str(data.short_name),
      country: str(data.country),
      team_type: str(data.team_type) || 'international',
      provider_logo_url: imageFrom(data.logo_url, data.image_id, 'team'),
      players: Array.isArray(data.players)
        ? data.players.map((p) => ({
            player_id: str(p.player_id || p.id),
            name: str(p.name),
            role: str(p.role),
          }))
        : [],
    },
  };
}

/**
 * Fetch a match by provider id and shape it for the admin match form/preview.
 * @returns {Promise<{ provider: string, data: object } | null>}
 */
export async function fetchMatchByProviderId(matchId) {
  const id = str(matchId);
  if (!id) return null;
  let result;
  try {
    result = await providerManager.execute('getMatchInfoDetailed', id);
  } catch {
    result = await providerManager.execute('getMatchInfo', id);
  }
  const data = result?.data;
  const provider = result?.provider || null;
  if (!data) return null;

  const t1 = data.team1 || data.teamA || {};
  const t2 = data.team2 || data.teamB || {};
  const teamDto = (t) => ({
    team_id: str(t.id || t.team_id || t.teamId),
    name: str(t.name || t.teamName),
    short_name: str(t.short_name || t.shortName || t.teamSName),
    logo_url: imageFrom(t.logo_url || t.imageUrl, t.image_id || t.imageId, 'team'),
  });

  return {
    provider,
    data: {
      provider_match_id: str(data.match_id || data.matchId || data.id) || id,
      match_id: str(data.match_id || data.matchId || data.id) || id,
      title: str(data.match_desc || data.matchDesc || data.title || data.name),
      series_id: str(data.series_id || data.seriesId),
      series_name: str(data.series_name || data.seriesName),
      team1: teamDto(t1),
      team2: teamDto(t2),
      venue: str(data.venue?.name || data.venue || data.ground),
      start_time: data.start_time || data.startTime || data.startDate || null,
      match_format: str(data.match_format || data.format || data.matchFormat),
      match_type: str(data.match_type || data.matchType || data.category),
      status: str(data.status || data.state || data.matchStatus),
      status_text: str(data.status_text || data.statusText),
      toss: str(data.toss?.text || data.tossResults || data.toss),
      raw: data,
    },
  };
}
