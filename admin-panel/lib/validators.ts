import { z } from 'zod';

export const loginSchema = z.object({
  email: z.string().min(1, 'Enter your username or email'),
  password: z.string().min(8, 'Password must be at least 8 characters'),
});
export type LoginInput = z.infer<typeof loginSchema>;

const optionalJsonString = z
  .string()
  .optional()
  .nullable()
  .refine((value) => {
    if (!value || !value.trim()) return true;
    try {
      JSON.parse(value);
      return true;
    } catch {
      return false;
    }
  }, 'Must be valid JSON');

export const streamSchema = z.object({
  match_external_id: z.string().min(1, 'Match ID required'),
  match_title: z.string().optional().nullable(),
  title: z.string().optional().nullable(),
  team_a: z.string().optional().nullable(),
  team_b: z.string().optional().nullable(),
  label: z.string().optional().nullable(),
  language: z.string().optional().nullable(),
  server_name: z.string().optional().nullable(),
  server_id: z.coerce.number().int().optional().nullable(),
  quality: z.enum(['AUTO', 'FHD', 'HD', 'SD']).default('AUTO'),
  stream_type: z.enum(['hls', 'dash', 'mpd', 'iframe', 'external']).default('hls'),
  stream_url: z.string().url('Must be a valid URL'),
  backup_stream_url: z.string().url().optional().or(z.literal('')),
  status: z.enum(['unknown', 'working', 'slow', 'down']).default('unknown'),
  is_active: z.boolean().default(true),
  is_premium: z.boolean().default(false),
  requires_reward_ad: z.boolean().default(false),
  requires_login: z.boolean().default(false),
  priority: z.coerce.number().int().min(0).default(100),
  starts_at: z.string().optional().nullable(),
  ends_at: z.string().optional().nullable(),
  lifecycle_state: z.enum(['draft', 'scheduled', 'active', 'disabled', 'expired']).default('scheduled'),
  timezone: z.string().optional().nullable(),
  early_show_minutes: z.coerce.number().int().min(0).max(1440).default(0),
  auto_hide_after_end: z.boolean().default(true),
  headers_json: optionalJsonString,
  user_agent_header: z.string().optional().nullable(),
  referer_header: z.string().optional().nullable(),
  origin_header: z.string().optional().nullable(),
  drm_enabled: z.boolean().default(false),
  drm_type: z.enum(['none', 'clearkey', 'widevine', 'fairplay', 'aes128']).default('none'),
  drm_license_url: z.string().url().optional().or(z.literal('')),
  drm_headers: optionalJsonString,
  clear_key_key_id: z.string().optional().nullable(),
  clear_key_key: z.string().optional().nullable(),
  notes: z.string().optional().nullable(),
});
export type StreamInput = z.infer<typeof streamSchema>;

export const providerSchema = z.object({
  slug: z.string().min(2, 'Slug required'),
  name: z.string().min(2, 'Name required'),
  provider_type: z.string().default('custom'),
  base_url: z.string().url().optional().nullable().or(z.literal('')),
  description: z.string().optional().nullable(),
  priority: z.coerce.number().int().min(0).default(100),
  timeout_ms: z.coerce.number().int().min(1000).default(8000),
  rate_limit_per_minute: z.coerce.number().int().min(1).default(60),
  is_active: z.boolean().default(true),
});
export type ProviderInput = z.infer<typeof providerSchema>;

export const providerKeySchema = z.object({
  label: z.string().min(1, 'Label required'),
  key_value: z.string().min(4, 'Key required'),
  notes: z.string().optional().nullable(),
});
export type ProviderKeyInput = z.infer<typeof providerKeySchema>;

export const apiKeySchema = z.object({
  name: z.string().min(3, 'Name must be at least 3 characters'),
  email: z.string().email().optional().or(z.literal('')),
  tier: z.enum(['free', 'standard', 'premium', 'unlimited']).default('free'),
  rate_limit: z.coerce.number().int().min(1).default(100),
  expires_in_days: z.coerce.number().int().min(0).optional(),
});
export type ApiKeyInput = z.infer<typeof apiKeySchema>;

export const appSettingSchema = z.object({
  setting_key: z.string().min(1),
  setting_group: z.string().default('general'),
  description: z.string().optional().nullable(),
  setting_value: z.string().min(1, 'Provide JSON or a value'),
});
export type AppSettingInput = z.infer<typeof appSettingSchema>;

export const homeSectionSchema = z.object({
  slug: z.string().min(1),
  title: z.string().min(1),
  section_type: z.string().min(1),
  sort_order: z.coerce.number().int().min(0).default(100),
  is_active: z.boolean().default(true),
  starts_at: z.string().optional().nullable(),
  ends_at: z.string().optional().nullable(),
  payload: z.string().optional().nullable(),
});
export type HomeSectionInput = z.infer<typeof homeSectionSchema>;

export const bannerSchema = z.object({
  placement: z.string().min(1, 'Placement required'),
  title: z.string().optional().nullable(),
  subtitle: z.string().optional().nullable(),
  image_url: z.string().url().optional().or(z.literal('')),
  cta_label: z.string().optional().nullable(),
  cta_url: z.string().url().optional().or(z.literal('')),
  sort_order: z.coerce.number().int().min(0).default(100),
  is_active: z.boolean().default(true),
  starts_at: z.string().optional().nullable(),
  ends_at: z.string().optional().nullable(),
});
export type BannerInput = z.infer<typeof bannerSchema>;

export const notificationSchema = z.object({
  title: z.string().min(1, 'Title required'),
  body: z.string().min(1, 'Body required'),
  image_url: z.string().url().optional().or(z.literal('')),
  target_type: z.string().default('all'),
  target_value: z.string().optional().nullable(),
  deep_link_type: z.string().optional().nullable(),
  deep_link_value: z.string().optional().nullable(),
  scheduled_at: z.string().optional().nullable(),
  status: z.enum(['draft', 'scheduled', 'sent']).default('draft'),
});
export type NotificationInput = z.infer<typeof notificationSchema>;

export const newsSchema = z.object({
  headline: z.string().min(1, 'Headline required'),
  body: z.string().optional().nullable(),
  context: z.string().optional().nullable(),
  story_type: z.string().default('custom'),
  image_url: z.string().url().optional().or(z.literal('')),
  source: z.string().default('CricPro'),
  is_featured: z.boolean().default(false),
  is_hidden: z.boolean().default(false),
  sort_order: z.coerce.number().int().min(0).default(100),
  published_at: z.string().optional().nullable(),
});
export type NewsInput = z.infer<typeof newsSchema>;

export const userSchema = z.object({
  name: z.string().min(1),
  email: z.string().email(),
  password: z.string().min(8).optional().or(z.literal('')),
  is_active: z.boolean().default(true),
  roles: z.array(z.string()).default([]),
});
export type UserInput = z.infer<typeof userSchema>;

export const roleSchema = z.object({
  slug: z.string().min(2),
  name: z.string().min(1),
  description: z.string().optional().nullable(),
  permissions: z.array(z.string()).default([]),
});
export type RoleInput = z.infer<typeof roleSchema>;

export const matchOverrideSchema = z.object({
  display_label: z.string().optional().nullable(),
  admin_note: z.string().optional().nullable(),
  is_hidden: z.boolean().default(false),
  is_featured: z.boolean().default(false),
});
export type MatchOverrideInput = z.infer<typeof matchOverrideSchema>;

export const adsSchema = z.object({
  show_ads: z.boolean().default(true),
  test_mode: z.boolean().default(false),
  consent_required: z.boolean().default(false),
  primary_network: z.enum(['admob', 'unity', 'meta']).default('admob'),
  fallback_order: z.array(z.enum(['admob', 'unity', 'meta'])).default(['admob', 'unity', 'meta']),
  banner_enabled: z.boolean().default(true),
  native_enabled: z.boolean().default(true),
  interstitial_enabled: z.boolean().default(true),
  rewarded_enabled: z.boolean().default(false),
  admob_enabled: z.boolean().default(true),
  unity_enabled: z.boolean().default(false),
  meta_enabled: z.boolean().default(false),
  rewarded_required_for_premium_streams: z.boolean().default(false),
  frequency_minutes: z.coerce.number().int().min(0).default(5),
  interstitial_frequency_cap: z.coerce.number().int().min(0).default(1),
  minimum_seconds_between_interstitials: z.coerce.number().int().min(0).default(300),
  minimum_seconds_between_full_screen_ads: z.coerce.number().int().min(0).default(90),
  home_banner_enabled: z.boolean().default(true),
  home_native_enabled: z.boolean().default(false),
  matches_banner_enabled: z.boolean().default(true),
  matches_native_enabled: z.boolean().default(false),
  schedule_banner_enabled: z.boolean().default(true),
  match_details_banner_enabled: z.boolean().default(true),
  match_details_native_enabled: z.boolean().default(false),
  match_details_interstitial_enabled: z.boolean().default(true),
  news_banner_enabled: z.boolean().default(true),
  news_native_enabled: z.boolean().default(false),
  news_interstitial_enabled: z.boolean().default(true),
  series_banner_enabled: z.boolean().default(true),
  series_native_enabled: z.boolean().default(false),
  series_interstitial_enabled: z.boolean().default(true),
  more_banner_enabled: z.boolean().default(true),
  live_player_banner_enabled: z.boolean().default(false),
  after_player_interstitial_enabled: z.boolean().default(false),
  premium_stream_rewarded_enabled: z.boolean().default(true),
  premium_stream_rewarded_interstitial_enabled: z.boolean().default(true),
  // Live stream pre-roll (Watch Live → ad → stream)
  pre_roll_enabled: z.boolean().default(true),
  live_stream_pre_roll_ad_type: z
    .enum(['none', 'interstitial', 'rewarded_interstitial', 'rewarded_video'])
    .default('rewarded_video'),
  pre_roll_free_streams: z.boolean().default(false),
  pre_roll_premium_streams: z.boolean().default(true),
  pre_roll_allow_fallback: z.boolean().default(false),
  // Pre-roll caps & timing
  pre_roll_session_cap_enabled: z.boolean().default(true),
  pre_roll_max_per_session: z.coerce.number().int().min(0).default(3),
  pre_roll_max_per_match: z.coerce.number().int().min(0).default(1),
  pre_roll_min_seconds_between_ads: z.coerce.number().int().min(0).default(180),
  pre_roll_timeout_seconds: z.coerce.number().int().min(3).max(30).default(8),
  // App Open ads
  app_open_enabled: z.boolean().default(false),
  app_open_cold_start: z.boolean().default(true),
  app_open_resume: z.boolean().default(true),
  minimum_seconds_between_app_open_ads: z.coerce.number().int().min(0).default(120),
  // Strict app-open cooldown (AdMob best practice). Default 240 min = 4 hours.
  app_open_min_interval_minutes: z.coerce.number().int().min(0).default(240),
  // Minimum real background time before app-open may show on resume (guards
  // notification-shade / screen-unlock quick resumes). Default 30s.
  app_open_min_background_seconds: z.coerce.number().int().min(0).default(30),
  max_app_open_ads_per_session: z.coerce.number().int().min(0).default(4),
  // AdMob
  admob_android_app_id: z.string().optional().nullable(),
  admob_ios_app_id: z.string().optional().nullable(),
  android_banner_id: z.string().optional().nullable(),
  android_interstitial_id: z.string().optional().nullable(),
  android_native_id: z.string().optional().nullable(),
  android_rewarded_id: z.string().optional().nullable(),
  android_rewarded_interstitial_id: z.string().optional().nullable(),
  android_app_open_id: z.string().optional().nullable(),
  ios_banner_id: z.string().optional().nullable(),
  ios_interstitial_id: z.string().optional().nullable(),
  ios_native_id: z.string().optional().nullable(),
  ios_rewarded_id: z.string().optional().nullable(),
  ios_rewarded_interstitial_id: z.string().optional().nullable(),
  ios_app_open_id: z.string().optional().nullable(),
  // Unity Ads
  unity_test_mode: z.boolean().default(false),
  unity_android_game_id: z.string().optional().nullable(),
  unity_ios_game_id: z.string().optional().nullable(),
  unity_android_banner_id: z.string().optional().nullable(),
  unity_android_interstitial_id: z.string().optional().nullable(),
  unity_android_rewarded_id: z.string().optional().nullable(),
  unity_ios_banner_id: z.string().optional().nullable(),
  unity_ios_interstitial_id: z.string().optional().nullable(),
  unity_ios_rewarded_id: z.string().optional().nullable(),
  // Meta / Facebook Audience Network
  meta_test_mode: z.boolean().default(false),
  meta_android_app_id: z.string().optional().nullable(),
  meta_ios_app_id: z.string().optional().nullable(),
  meta_android_banner_id: z.string().optional().nullable(),
  meta_android_native_id: z.string().optional().nullable(),
  meta_android_interstitial_id: z.string().optional().nullable(),
  meta_android_rewarded_id: z.string().optional().nullable(),
  meta_ios_banner_id: z.string().optional().nullable(),
  meta_ios_native_id: z.string().optional().nullable(),
  meta_ios_interstitial_id: z.string().optional().nullable(),
  meta_ios_rewarded_id: z.string().optional().nullable(),
});
export type AdsInput = z.infer<typeof adsSchema>;
