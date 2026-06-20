/**
 * Cricbuzz image URL helper.
 * Converts Cricbuzz imageId into a publicly accessible image URL.
 *
 * Image sizes:
 *   i1 = standard (~200px)
 *   i2 = medium (~400px)
 *   i3 = large  (~600px)
 */

const CRICBUZZ_IMAGE_BASE = 'https://static.cricbuzz.com/a/img/v1';

export function getCricbuzzImageUrl(imageId, size = 'i1') {
  if (!imageId) return null;
  return `${CRICBUZZ_IMAGE_BASE}/${size}/c${imageId}/i.jpg`;
}

export function getTeamLogoUrl(imageId) {
  return getCricbuzzImageUrl(imageId, 'i1');
}

export function getPlayerImageUrl(imageId) {
  return getCricbuzzImageUrl(imageId, 'i2');
}

export function getMatchImageUrl(imageId) {
  return getCricbuzzImageUrl(imageId, 'i2');
}
