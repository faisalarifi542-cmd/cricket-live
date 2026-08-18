export type ProviderCapabilities = Record<string, 'full' | 'limited' | 'unsupported'>;

export type Provider = {
  id: number;
  slug: string;
  name: string;
  base_url?: string;
  provider_type?: string;
  description?: string;
  is_active: boolean;
  priority: number;
  role?: string;
  timeout_ms?: number;
  rate_limit_per_minute?: number;
  health_status?: string;
  health_message?: string;
  last_error?: string;
  last_success_at?: string;
  last_failure_at?: string;
  metadata?: { role?: string } | null;
  capabilities?: ProviderCapabilities;
  is_configured?: boolean;
  config_reason?: string | null;
  live_health_state?: string;
};
