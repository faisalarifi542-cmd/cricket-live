import { z } from 'zod';

export const loginSchema = z.object({
  email: z.string().min(1, 'Enter your username or email'),
  password: z.string().min(8, 'Password must be at least 8 characters'),
});
export type LoginInput = z.infer<typeof loginSchema>;

export const streamSchema = z.object({
  match_external_id: z.string().min(1, 'Match ID required'),
  title: z.string().optional().nullable(),
  label: z.string().optional().nullable(),
  language: z.string().optional().nullable(),
  server_name: z.string().optional().nullable(),
  server_id: z.coerce.number().int().optional().nullable(),
  quality: z.enum(['AUTO', 'FHD', 'HD', 'SD']).default('AUTO'),
  stream_type: z.enum(['hls', 'dash', 'iframe', 'external']).default('hls'),
  stream_url: z.string().url('Must be a valid URL'),
  is_active: z.boolean().default(true),
  is_premium: z.boolean().default(false),
  priority: z.coerce.number().int().min(0).default(100),
  starts_at: z.string().optional().nullable(),
  ends_at: z.string().optional().nullable(),
  user_agent_header: z.string().optional().nullable(),
  referer_header: z.string().optional().nullable(),
  drm_enabled: z.boolean().default(false),
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
  banner_enabled: z.boolean().default(true),
  native_enabled: z.boolean().default(true),
  interstitial_enabled: z.boolean().default(true),
  rewarded_enabled: z.boolean().default(false),
  frequency_minutes: z.coerce.number().int().min(0).default(5),
  android_banner_id: z.string().optional().nullable(),
  android_interstitial_id: z.string().optional().nullable(),
  android_native_id: z.string().optional().nullable(),
  android_rewarded_id: z.string().optional().nullable(),
  ios_banner_id: z.string().optional().nullable(),
  ios_interstitial_id: z.string().optional().nullable(),
  ios_native_id: z.string().optional().nullable(),
  ios_rewarded_id: z.string().optional().nullable(),
});
export type AdsInput = z.infer<typeof adsSchema>;
