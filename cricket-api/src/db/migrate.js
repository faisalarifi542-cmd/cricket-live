import crypto from 'node:crypto';
import { getPool } from '../lib/db.js';
import config from '../config/index.js';
import logger from '../lib/logger.js';

// Default public app API key. Shared with the Flutter client via the
// APP_PUBLIC_API_KEY env (same fallback string baked into the app config so the
// app keeps working out of the box). Override in production from the Admin Panel
// by issuing a fresh client and regenerating this one.
const DEFAULT_APP_API_KEY = process.env.APP_PUBLIC_API_KEY || 'csk_live_cricpro_app_8f3a2b1c9d';

const TABLES = [
  // ====================================================
  // TEAMS
  // ====================================================
  `CREATE TABLE IF NOT EXISTS teams (
    id            INT AUTO_INCREMENT PRIMARY KEY,
    external_id   VARCHAR(50) UNIQUE,
    name          VARCHAR(200) NOT NULL,
    short_name    VARCHAR(20),
    slug          VARCHAR(220),
    logo_url      TEXT,
    cricbuzz_logo_url TEXT,
    country       VARCHAR(100),
    team_type     VARCHAR(20) DEFAULT 'international',
    is_active     TINYINT(1) DEFAULT 1,
    metadata      JSON,
    created_at    DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at    DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_teams_external (external_id),
    INDEX idx_teams_name (name)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,

  // ====================================================
  // PLAYERS
  // ====================================================
  `CREATE TABLE IF NOT EXISTS players (
    id            INT AUTO_INCREMENT PRIMARY KEY,
    external_id   VARCHAR(50) UNIQUE,
    name          VARCHAR(200) NOT NULL,
    full_name     VARCHAR(300),
    dob           DATE,
    nationality   VARCHAR(100),
    role          VARCHAR(50),
    batting_style VARCHAR(50),
    bowling_style VARCHAR(100),
    image_url     TEXT,
    team_id       INT,
    stats         JSON,
    metadata      JSON,
    created_at    DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at    DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_players_external (external_id),
    INDEX idx_players_team (team_id),
    INDEX idx_players_name (name),
    FOREIGN KEY (team_id) REFERENCES teams(id) ON DELETE SET NULL
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,

  // ====================================================
  // SERIES
  // ====================================================
  `CREATE TABLE IF NOT EXISTS series (
    id            INT AUTO_INCREMENT PRIMARY KEY,
    external_id   VARCHAR(50) UNIQUE,
    name          VARCHAR(300) NOT NULL,
    short_name    VARCHAR(100),
    season        VARCHAR(20),
    start_date    DATE,
    end_date      DATE,
    series_type   VARCHAR(30),
    format        VARCHAR(20),
    country       VARCHAR(100),
    metadata      JSON,
    created_at    DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at    DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_series_external (external_id),
    INDEX idx_series_dates (start_date, end_date)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,

  // ====================================================
  // MATCHES
  // ====================================================
  `CREATE TABLE IF NOT EXISTS matches (
    id              INT AUTO_INCREMENT PRIMARY KEY,
    external_id     VARCHAR(50) UNIQUE,
    series_id       INT,
    match_format    VARCHAR(20) NOT NULL,
    match_type      VARCHAR(30),
    status          VARCHAR(30) NOT NULL DEFAULT 'upcoming',
    status_text     TEXT,
    team1_id        INT,
    team2_id        INT,
    venue           VARCHAR(300),
    city            VARCHAR(100),
    country         VARCHAR(100),
    start_time      DATETIME,
    end_time        DATETIME,
    toss_winner_id  INT,
    toss_decision   VARCHAR(10),
    winner_id       INT,
    result_text     TEXT,
    man_of_match_id INT,
    current_innings INT DEFAULT 0,
    day_number      INT,
    session         VARCHAR(20),
    live_score      JSON,
    metadata        JSON,
    provider        VARCHAR(30) DEFAULT 'cricbuzz',
    last_polled_at  DATETIME,
    created_at      DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at      DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_matches_external (external_id),
    INDEX idx_matches_status (status),
    INDEX idx_matches_series (series_id),
    INDEX idx_matches_start (start_time),
    INDEX idx_matches_teams (team1_id, team2_id),
    FOREIGN KEY (series_id) REFERENCES series(id) ON DELETE SET NULL,
    FOREIGN KEY (team1_id) REFERENCES teams(id) ON DELETE SET NULL,
    FOREIGN KEY (team2_id) REFERENCES teams(id) ON DELETE SET NULL,
    FOREIGN KEY (toss_winner_id) REFERENCES teams(id) ON DELETE SET NULL,
    FOREIGN KEY (winner_id) REFERENCES teams(id) ON DELETE SET NULL,
    FOREIGN KEY (man_of_match_id) REFERENCES players(id) ON DELETE SET NULL
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,

  // ====================================================
  // INNINGS
  // ====================================================
  `CREATE TABLE IF NOT EXISTS innings (
    id              INT AUTO_INCREMENT PRIMARY KEY,
    match_id        INT NOT NULL,
    innings_number  INT NOT NULL,
    batting_team_id INT,
    bowling_team_id INT,
    total_runs      INT DEFAULT 0,
    total_wickets   INT DEFAULT 0,
    total_overs     DECIMAL(5,1) DEFAULT 0,
    target          INT,
    run_rate        DECIMAL(5,2),
    required_rate   DECIMAL(5,2),
    is_completed    TINYINT(1) DEFAULT 0,
    extras          JSON,
    fow             JSON,
    metadata        JSON,
    created_at      DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at      DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_innings (match_id, innings_number),
    INDEX idx_innings_match (match_id),
    FOREIGN KEY (match_id) REFERENCES matches(id) ON DELETE CASCADE,
    FOREIGN KEY (batting_team_id) REFERENCES teams(id) ON DELETE SET NULL,
    FOREIGN KEY (bowling_team_id) REFERENCES teams(id) ON DELETE SET NULL
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,

  // ====================================================
  // BATTING SCORECARDS
  // ====================================================
  `CREATE TABLE IF NOT EXISTS batting_scores (
    id              INT AUTO_INCREMENT PRIMARY KEY,
    innings_id      INT NOT NULL,
    player_id       INT,
    player_name     VARCHAR(200),
    batting_pos     INT,
    runs            INT DEFAULT 0,
    balls           INT DEFAULT 0,
    fours           INT DEFAULT 0,
    sixes           INT DEFAULT 0,
    strike_rate     DECIMAL(6,2),
    dismissal_type  VARCHAR(50),
    dismissal_text  TEXT,
    bowler_id       INT,
    fielder_id      INT,
    is_batting      TINYINT(1) DEFAULT 0,
    is_striker      TINYINT(1) DEFAULT 0,
    minutes         INT,
    metadata        JSON,
    created_at      DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_batting_innings (innings_id),
    INDEX idx_batting_player (player_id),
    FOREIGN KEY (innings_id) REFERENCES innings(id) ON DELETE CASCADE,
    FOREIGN KEY (player_id) REFERENCES players(id) ON DELETE SET NULL,
    FOREIGN KEY (bowler_id) REFERENCES players(id) ON DELETE SET NULL,
    FOREIGN KEY (fielder_id) REFERENCES players(id) ON DELETE SET NULL
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,

  // ====================================================
  // BOWLING SCORECARDS
  // ====================================================
  `CREATE TABLE IF NOT EXISTS bowling_scores (
    id              INT AUTO_INCREMENT PRIMARY KEY,
    innings_id      INT NOT NULL,
    player_id       INT,
    player_name     VARCHAR(200),
    overs           DECIMAL(5,1) DEFAULT 0,
    maidens         INT DEFAULT 0,
    runs_conceded   INT DEFAULT 0,
    wickets         INT DEFAULT 0,
    economy         DECIMAL(5,2),
    dots            INT DEFAULT 0,
    fours_conceded  INT DEFAULT 0,
    sixes_conceded  INT DEFAULT 0,
    wides           INT DEFAULT 0,
    no_balls        INT DEFAULT 0,
    is_bowling      TINYINT(1) DEFAULT 0,
    metadata        JSON,
    created_at      DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_bowling_innings (innings_id),
    INDEX idx_bowling_player (player_id),
    FOREIGN KEY (innings_id) REFERENCES innings(id) ON DELETE CASCADE,
    FOREIGN KEY (player_id) REFERENCES players(id) ON DELETE SET NULL
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,

  // ====================================================
  // COMMENTARY
  // ====================================================
  `CREATE TABLE IF NOT EXISTS commentary (
    id              INT AUTO_INCREMENT PRIMARY KEY,
    match_id        INT NOT NULL,
    innings_number  INT,
    over_number     DECIMAL(5,1),
    ball_number     INT,
    event_type      VARCHAR(30),
    commentary_text TEXT NOT NULL,
    runs            INT DEFAULT 0,
    is_wicket       TINYINT(1) DEFAULT 0,
    is_boundary     TINYINT(1) DEFAULT 0,
    batsman_name    VARCHAR(200),
    bowler_name     VARCHAR(200),
    timestamp       BIGINT,
    metadata        JSON,
    created_at      DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_commentary_match (match_id),
    INDEX idx_commentary_match_innings (match_id, innings_number),
    INDEX idx_commentary_timestamp (match_id, timestamp),
    FOREIGN KEY (match_id) REFERENCES matches(id) ON DELETE CASCADE
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,

  // ====================================================
  // POINTS TABLES
  // ====================================================
  `CREATE TABLE IF NOT EXISTS points_table (
    id              INT AUTO_INCREMENT PRIMARY KEY,
    series_id       INT NOT NULL,
    team_id         INT,
    team_name       VARCHAR(200),
    matches_played  INT DEFAULT 0,
    wins            INT DEFAULT 0,
    losses          INT DEFAULT 0,
    ties            INT DEFAULT 0,
    no_results      INT DEFAULT 0,
    points          INT DEFAULT 0,
    nrr             DECIMAL(6,3) DEFAULT 0,
    position        INT,
    group_name      VARCHAR(50),
    is_qualified    TINYINT(1) DEFAULT 0,
    metadata        JSON,
    created_at      DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at      DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_points (series_id, team_id),
    INDEX idx_points_series (series_id),
    FOREIGN KEY (series_id) REFERENCES series(id) ON DELETE CASCADE,
    FOREIGN KEY (team_id) REFERENCES teams(id) ON DELETE SET NULL
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,

  // ====================================================
  // API KEYS
  // ====================================================
  `CREATE TABLE IF NOT EXISTS api_keys (
    id              INT AUTO_INCREMENT PRIMARY KEY,
    key_hash        VARCHAR(128) UNIQUE NOT NULL,
    name            VARCHAR(200) NOT NULL,
    email           VARCHAR(300),
    tier            VARCHAR(20) DEFAULT 'free',
    rate_limit      INT DEFAULT 100,
    is_active       TINYINT(1) DEFAULT 1,
    last_used_at    DATETIME,
    expires_at      DATETIME,
    metadata        JSON,
    created_at      DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_api_keys_hash (key_hash)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,

  // ====================================================
  // USERS (admin panel)
  // ====================================================
  `CREATE TABLE IF NOT EXISTS users (
    id              INT AUTO_INCREMENT PRIMARY KEY,
    username        VARCHAR(100) UNIQUE NOT NULL,
    email           VARCHAR(300) UNIQUE NOT NULL,
    password_hash   VARCHAR(200) NOT NULL,
    role            VARCHAR(20) DEFAULT 'user',
    is_active       TINYINT(1) DEFAULT 1,
    created_at      DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at      DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,

  `CREATE TABLE IF NOT EXISTS admin_users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    email VARCHAR(300) UNIQUE NOT NULL,
    name VARCHAR(200) NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    is_active TINYINT(1) DEFAULT 1,
    last_login_at DATETIME,
    last_login_ip VARCHAR(64),
    failed_login_attempts INT DEFAULT 0,
    locked_until DATETIME,
    password_changed_at DATETIME,
    refresh_token_hash VARCHAR(128),
    refresh_token_expires_at DATETIME,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,

  `CREATE TABLE IF NOT EXISTS admin_roles (
    id INT AUTO_INCREMENT PRIMARY KEY,
    slug VARCHAR(80) UNIQUE NOT NULL,
    name VARCHAR(120) NOT NULL,
    description TEXT,
    is_system TINYINT(1) DEFAULT 0,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,

  `CREATE TABLE IF NOT EXISTS admin_permissions (
    id INT AUTO_INCREMENT PRIMARY KEY,
    slug VARCHAR(120) UNIQUE NOT NULL,
    name VARCHAR(120) NOT NULL,
    description TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,

  `CREATE TABLE IF NOT EXISTS admin_user_roles (
    user_id INT NOT NULL,
    role_id INT NOT NULL,
    PRIMARY KEY (user_id, role_id),
    FOREIGN KEY (role_id) REFERENCES admin_roles(id) ON DELETE CASCADE
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,

  `CREATE TABLE IF NOT EXISTS admin_role_permissions (
    role_id INT NOT NULL,
    permission_id INT NOT NULL,
    PRIMARY KEY (role_id, permission_id),
    FOREIGN KEY (role_id) REFERENCES admin_roles(id) ON DELETE CASCADE,
    FOREIGN KEY (permission_id) REFERENCES admin_permissions(id) ON DELETE CASCADE
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,

  `CREATE TABLE IF NOT EXISTS admin_audit_logs (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    admin_user_id INT,
    admin_email VARCHAR(300),
    action VARCHAR(120) NOT NULL,
    entity_type VARCHAR(120) NOT NULL,
    entity_id VARCHAR(120),
    old_value JSON,
    new_value JSON,
    ip_address VARCHAR(64),
    user_agent VARCHAR(400),
    status VARCHAR(30) DEFAULT 'ok',
    error_message TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_audit_user (admin_user_id),
    INDEX idx_audit_action (action),
    INDEX idx_audit_entity (entity_type, entity_id),
    INDEX idx_audit_created (created_at)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,

  `CREATE TABLE IF NOT EXISTS stream_sources (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(200) NOT NULL,
    source_type VARCHAR(50) DEFAULT 'custom',
    is_active TINYINT(1) DEFAULT 1,
    metadata JSON,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,

  `CREATE TABLE IF NOT EXISTS stream_servers (
    id INT AUTO_INCREMENT PRIMARY KEY,
    source_id INT,
    name VARCHAR(200) NOT NULL,
    region VARCHAR(80),
    priority INT DEFAULT 100,
    is_active TINYINT(1) DEFAULT 1,
    metadata JSON,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (source_id) REFERENCES stream_sources(id) ON DELETE SET NULL
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,

  `CREATE TABLE IF NOT EXISTS match_streams (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    match_external_id VARCHAR(80) NOT NULL,
    match_title VARCHAR(250),
    title VARCHAR(250),
    team_a VARCHAR(180),
    team_b VARCHAR(180),
    quality ENUM('AUTO','FHD','HD','SD') DEFAULT 'AUTO',
    label VARCHAR(80),
    language VARCHAR(80) DEFAULT 'English',
    server_id INT,
    server_name VARCHAR(160),
    stream_type ENUM('hls','dash','mpd','iframe','external') DEFAULT 'hls',
    stream_url TEXT NOT NULL,
    backup_stream_url TEXT,
    is_active TINYINT(1) DEFAULT 1,
    is_premium TINYINT(1) DEFAULT 0,
    requires_reward_ad TINYINT(1) DEFAULT 0,
    requires_login TINYINT(1) DEFAULT 0,
    priority INT DEFAULT 100,
    status ENUM('working','slow','down','unknown') DEFAULT 'unknown',
    starts_at DATETIME,
    ends_at DATETIME,
    geo_blocked_countries JSON,
    headers_json JSON,
    user_agent_header VARCHAR(400),
    referer_header VARCHAR(400),
    origin_header VARCHAR(400),
    drm_enabled TINYINT(1) DEFAULT 0,
    drm_type VARCHAR(40) DEFAULT 'none',
    drm_license_url TEXT,
    drm_headers JSON,
    clear_key_key_id VARCHAR(220),
    clear_key_key TEXT,
    notes TEXT,
    last_status_at DATETIME,
    created_by INT,
    updated_by INT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_stream_match (match_external_id),
    INDEX idx_stream_active (is_active, priority),
    FOREIGN KEY (server_id) REFERENCES stream_servers(id) ON DELETE SET NULL
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,

  `CREATE TABLE IF NOT EXISTS stream_health_checks (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    stream_id BIGINT NOT NULL,
    status VARCHAR(30) NOT NULL,
    http_status INT,
    latency_ms INT,
    error_message TEXT,
    checked_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_stream_health (stream_id, checked_at),
    FOREIGN KEY (stream_id) REFERENCES match_streams(id) ON DELETE CASCADE
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,

  `CREATE TABLE IF NOT EXISTS api_providers (
    id INT AUTO_INCREMENT PRIMARY KEY,
    slug VARCHAR(100) UNIQUE NOT NULL,
    name VARCHAR(200) NOT NULL,
    provider_type VARCHAR(50) DEFAULT 'custom',
    base_url TEXT,
    description TEXT,
    priority INT DEFAULT 100,
    timeout_ms INT DEFAULT 8000,
    rate_limit_per_minute INT DEFAULT 60,
    is_active TINYINT(1) DEFAULT 1,
    health_status VARCHAR(30) DEFAULT 'unknown',
    last_success_at DATETIME,
    last_failure_at DATETIME,
    metadata JSON,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,

  `CREATE TABLE IF NOT EXISTS provider_api_keys (
    id INT AUTO_INCREMENT PRIMARY KEY,
    provider_id INT NOT NULL,
    label VARCHAR(160) NOT NULL,
    key_value TEXT NOT NULL,
    is_active TINYINT(1) DEFAULT 1,
    rotated_at DATETIME,
    last_used_at DATETIME,
    notes TEXT,
    created_by INT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (provider_id) REFERENCES api_providers(id) ON DELETE CASCADE
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,

  `CREATE TABLE IF NOT EXISTS provider_settings (
    id INT AUTO_INCREMENT PRIMARY KEY,
    provider_id INT NOT NULL,
    setting_key VARCHAR(120) NOT NULL,
    setting_value JSON,
    is_secret TINYINT(1) DEFAULT 0,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_provider_setting (provider_id, setting_key),
    FOREIGN KEY (provider_id) REFERENCES api_providers(id) ON DELETE CASCADE
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,

  // Maps a provider's match id to the extra ids that provider needs to fetch a
  // single match. ESPN Cricinfo, for example, requires BOTH matchId AND seriesId
  // for its summary/playbyplay endpoints, but the app only carries one id. This
  // table persists the matchId -> seriesId link (learned from ESPN's scoreboard
  // feed) so a match-detail request that arrives before the first scoreboard poll
  // (e.g. right after a restart) can still resolve its seriesId. Keyed by
  // provider_type so other providers can reuse it.
  `CREATE TABLE IF NOT EXISTS provider_match_mappings (
    id INT AUTO_INCREMENT PRIMARY KEY,
    provider_type VARCHAR(50) NOT NULL,
    match_id VARCHAR(64) NOT NULL,
    series_id VARCHAR(64),
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_provider_match (provider_type, match_id)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,

  `CREATE TABLE IF NOT EXISTS app_settings (
    id INT AUTO_INCREMENT PRIMARY KEY,
    setting_key VARCHAR(140) UNIQUE NOT NULL,
    setting_value JSON,
    setting_group VARCHAR(80) DEFAULT 'general',
    type VARCHAR(40) DEFAULT 'json',
    \`group\` VARCHAR(80) DEFAULT 'general',
    description TEXT,
    is_public TINYINT(1) DEFAULT 1,
    updated_by INT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,

  `CREATE TABLE IF NOT EXISTS homepage_sections (
    id INT AUTO_INCREMENT PRIMARY KEY,
    slug VARCHAR(120) UNIQUE NOT NULL,
    title VARCHAR(200) NOT NULL,
    section_type VARCHAR(80) NOT NULL,
    payload JSON,
    sort_order INT DEFAULT 100,
    is_active TINYINT(1) DEFAULT 1,
    starts_at DATETIME,
    ends_at DATETIME,
    updated_by INT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,

  `CREATE TABLE IF NOT EXISTS featured_matches (
    id INT AUTO_INCREMENT PRIMARY KEY,
    match_external_id VARCHAR(80) NOT NULL,
    sort_order INT DEFAULT 100,
    is_active TINYINT(1) DEFAULT 1,
    note TEXT,
    starts_at DATETIME,
    ends_at DATETIME,
    created_by INT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,

  `CREATE TABLE IF NOT EXISTS featured_series (
    id INT AUTO_INCREMENT PRIMARY KEY,
    series_external_id VARCHAR(80) NOT NULL,
    sort_order INT DEFAULT 100,
    is_active TINYINT(1) DEFAULT 1,
    note TEXT,
    created_by INT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,

  `CREATE TABLE IF NOT EXISTS featured_news (
    id INT AUTO_INCREMENT PRIMARY KEY,
    news_id VARCHAR(120) NOT NULL,
    sort_order INT DEFAULT 100,
    is_active TINYINT(1) DEFAULT 1,
    note TEXT,
    created_by INT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,

  `CREATE TABLE IF NOT EXISTS app_banners (
    id INT AUTO_INCREMENT PRIMARY KEY,
    placement VARCHAR(80) NOT NULL,
    title VARCHAR(200),
    subtitle TEXT,
    image_url TEXT,
    cta_label VARCHAR(80),
    cta_url TEXT,
    sort_order INT DEFAULT 100,
    is_active TINYINT(1) DEFAULT 1,
    starts_at DATETIME,
    ends_at DATETIME,
    created_by INT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,

  // App Assets — admin-managed decorative images served to the Flutter app at
  // runtime. Lets large backgrounds/overlays be swapped without an app update
  // and (later) removed from the bundle to shrink the APK. The app always ships
  // a local fallback, so a missing/inactive row degrades gracefully.
  `CREATE TABLE IF NOT EXISTS app_assets (
    id INT AUTO_INCREMENT PRIMARY KEY,
    asset_key VARCHAR(100) NOT NULL,
    theme VARCHAR(10) NOT NULL DEFAULT 'both',
    url TEXT,
    version VARCHAR(40),
    is_active TINYINT(1) DEFAULT 1,
    updated_by INT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uniq_asset_key_theme (asset_key, theme),
    INDEX idx_app_assets_active (is_active)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,

  `CREATE TABLE IF NOT EXISTS push_notifications (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    title VARCHAR(200) NOT NULL,
    body TEXT NOT NULL,
    image_url TEXT,
    target_type VARCHAR(80) DEFAULT 'all',
    target_value VARCHAR(200),
    deep_link_type VARCHAR(80),
    deep_link_value VARCHAR(200),
    scheduled_at DATETIME,
    sent_at DATETIME,
    status VARCHAR(40) DEFAULT 'draft',
    created_by INT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,

  `CREATE TABLE IF NOT EXISTS notification_campaigns (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    notification_id BIGINT,
    provider VARCHAR(80) DEFAULT 'fcm',
    status VARCHAR(40) DEFAULT 'pending',
    sent_count INT DEFAULT 0,
    failed_count INT DEFAULT 0,
    metadata JSON,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (notification_id) REFERENCES push_notifications(id) ON DELETE SET NULL
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,

  `CREATE TABLE IF NOT EXISTS app_devices (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    subscription_id VARCHAR(220) UNIQUE NOT NULL,
    push_token TEXT,
    platform VARCHAR(40) DEFAULT 'unknown',
    app_version VARCHAR(60),
    build_number VARCHAR(60),
    language VARCHAR(40),
    permission_status VARCHAR(40) DEFAULT 'unknown',
    metadata JSON,
    last_seen_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_app_devices_platform (platform),
    INDEX idx_app_devices_seen (last_seen_at)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,

  `CREATE TABLE IF NOT EXISTS notification_history (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    notification_id BIGINT,
    provider VARCHAR(80) DEFAULT 'onesignal',
    target_type VARCHAR(80) DEFAULT 'all',
    target_value VARCHAR(220),
    title VARCHAR(220),
    body TEXT,
    payload JSON,
    provider_response JSON,
    status VARCHAR(40) DEFAULT 'pending',
    sent_count INT DEFAULT 0,
    failed_count INT DEFAULT 0,
    error_message TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_notification_history_created (created_at),
    INDEX idx_notification_history_status (status)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,

  `CREATE TABLE IF NOT EXISTS ad_settings (
    id INT AUTO_INCREMENT PRIMARY KEY,
    setting_key VARCHAR(120) UNIQUE NOT NULL,
    setting_value JSON,
    is_public TINYINT(1) DEFAULT 1,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,

  `CREATE TABLE IF NOT EXISTS ad_placements (
    id INT AUTO_INCREMENT PRIMARY KEY,
    placement_key VARCHAR(120) UNIQUE NOT NULL,
    platform VARCHAR(40) DEFAULT 'all',
    ad_unit_id VARCHAR(300),
    enabled TINYINT(1) DEFAULT 1,
    frequency_cap INT DEFAULT 0,
    metadata JSON,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,

  `CREATE TABLE IF NOT EXISTS cache_events (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    event_type VARCHAR(80) NOT NULL,
    cache_key VARCHAR(300),
    details JSON,
    triggered_by INT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_cache_events_created (created_at)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,

  `CREATE TABLE IF NOT EXISTS system_logs (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    level VARCHAR(30) DEFAULT 'info',
    message TEXT NOT NULL,
    endpoint VARCHAR(200),
    provider VARCHAR(100),
    match_id VARCHAR(80),
    metadata JSON,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_system_logs_level (level),
    INDEX idx_system_logs_created (created_at)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,

  `CREATE TABLE IF NOT EXISTS match_overrides (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    match_external_id VARCHAR(80) UNIQUE NOT NULL,
    display_label VARCHAR(200),
    admin_note TEXT,
    is_hidden TINYINT(1) DEFAULT 0,
    is_featured TINYINT(1) DEFAULT 0,
    created_by INT,
    updated_by INT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_match_overrides_flags (is_hidden, is_featured)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,

  `CREATE TABLE IF NOT EXISTS custom_news (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    headline VARCHAR(300) NOT NULL,
    body LONGTEXT,
    context VARCHAR(120),
    story_type VARCHAR(80) DEFAULT 'custom',
    image_url TEXT,
    source VARCHAR(120) DEFAULT 'CricPro',
    is_featured TINYINT(1) DEFAULT 0,
    is_hidden TINYINT(1) DEFAULT 0,
    sort_order INT DEFAULT 100,
    published_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    created_by INT,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,

  `CREATE TABLE IF NOT EXISTS manual_matches (
    id INT AUTO_INCREMENT PRIMARY KEY,
    match_external_id VARCHAR(50) UNIQUE NOT NULL,
    title VARCHAR(300),
    team1_name VARCHAR(200),
    team2_name VARCHAR(200),
    team1_short VARCHAR(20),
    team2_short VARCHAR(20),
    team1_logo_url TEXT,
    team2_logo_url TEXT,
    status VARCHAR(30) DEFAULT 'live',
    match_state VARCHAR(30) DEFAULT 'live',
    venue VARCHAR(300),
    start_time DATETIME,
    is_live TINYINT(1) DEFAULT 1,
    is_test TINYINT(1) DEFAULT 1,
    is_enabled TINYINT(1) DEFAULT 1,
    sort_order INT DEFAULT 1,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_manual_enabled (is_enabled, status),
    INDEX idx_manual_external (match_external_id)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,

  // ====================================================
  // API SECURITY — API CLIENTS (apps / websites / servers)
  // Raw API keys are NEVER stored; only a SHA-256 hash + short prefix.
  // ====================================================
  `CREATE TABLE IF NOT EXISTS api_clients (
    id                    INT AUTO_INCREMENT PRIMARY KEY,
    name                  VARCHAR(200) NOT NULL,
    client_type           VARCHAR(20) DEFAULT 'app',
    api_key_hash          VARCHAR(128) UNIQUE NOT NULL,
    api_key_prefix        VARCHAR(24) NOT NULL,
    secret_hash           VARCHAR(128),
    allowed_origins       JSON,
    allowed_domains       JSON,
    allowed_package_names JSON,
    allowed_bundle_ids    JSON,
    scopes                JSON,
    rate_limit_per_minute INT DEFAULT 120,
    rate_limit_per_hour   INT DEFAULT 5000,
    rate_limit_per_day    INT DEFAULT 100000,
    status                VARCHAR(20) DEFAULT 'active',
    expires_at            DATETIME,
    last_used_at          DATETIME,
    created_by            INT,
    notes                 TEXT,
    created_at            DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at            DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_api_clients_hash (api_key_hash),
    INDEX idx_api_clients_status (status),
    INDEX idx_api_clients_type (client_type)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,

  // ====================================================
  // API SECURITY — ALLOWED ORIGINS / DOMAINS (drives CORS)
  // ====================================================
  `CREATE TABLE IF NOT EXISTS api_allowed_origins (
    id                      INT AUTO_INCREMENT PRIMARY KEY,
    origin                  VARCHAR(255),
    domain                  VARCHAR(255),
    status                  VARCHAR(20) DEFAULT 'active',
    allowed_endpoint_groups JSON,
    rate_limit_per_minute   INT DEFAULT 120,
    notes                   TEXT,
    created_at              DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at              DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_allowed_origin (origin),
    INDEX idx_allowed_domain (domain),
    INDEX idx_allowed_status (status)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,

  // ====================================================
  // API SECURITY — ENDPOINT ACCESS RULES (per endpoint group)
  // ====================================================
  `CREATE TABLE IF NOT EXISTS api_endpoint_rules (
    id                    INT AUTO_INCREMENT PRIMARY KEY,
    group_name            VARCHAR(80) UNIQUE NOT NULL,
    path_pattern          VARCHAR(255),
    methods               JSON,
    enabled               TINYINT(1) DEFAULT 1,
    auth_required         VARCHAR(20) DEFAULT 'api_key',
    allowed_client_types  JSON,
    rate_limit_per_minute INT DEFAULT 120,
    rate_limit_per_hour   INT DEFAULT 5000,
    cache_ttl_seconds     INT DEFAULT 0,
    logging_enabled       TINYINT(1) DEFAULT 1,
    notes                 TEXT,
    created_at            DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at            DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_endpoint_group (group_name)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,

  // ====================================================
  // API SECURITY — BLOCKLIST
  // ====================================================
  `CREATE TABLE IF NOT EXISTS api_blocklist (
    id          INT AUTO_INCREMENT PRIMARY KEY,
    type        VARCHAR(20) NOT NULL,
    value       VARCHAR(255) NOT NULL,
    reason      TEXT,
    enabled     TINYINT(1) DEFAULT 1,
    expires_at  DATETIME,
    created_by  INT,
    created_at  DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at  DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_blocklist_type (type, enabled),
    INDEX idx_blocklist_value (value)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,

  // ====================================================
  // API SECURITY — REQUEST LOGS (trimmed by retention setting)
  // ====================================================
  `CREATE TABLE IF NOT EXISTS api_request_logs (
    id              BIGINT AUTO_INCREMENT PRIMARY KEY,
    method          VARCHAR(10),
    path            VARCHAR(400),
    endpoint_group  VARCHAR(80),
    status_code     INT,
    ip              VARCHAR(64),
    origin          VARCHAR(255),
    referer         VARCHAR(400),
    user_agent      VARCHAR(400),
    api_client_id   INT,
    api_key_prefix  VARCHAR(24),
    allowed         TINYINT(1) DEFAULT 1,
    blocked_reason  VARCHAR(80),
    response_time_ms INT,
    created_at      DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_req_logs_created (created_at),
    INDEX idx_req_logs_allowed (allowed),
    INDEX idx_req_logs_client (api_client_id),
    INDEX idx_req_logs_group (endpoint_group),
    INDEX idx_req_logs_ip (ip),
    INDEX idx_req_logs_status (status_code)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,

  // ====================================================
  // ANALYTICS — privacy-safe app usage events (no PII)
  // device_id / session_id are random anonymous IDs generated client-side.
  // payload is a small JSON bag of non-identifying dimensions (screen name,
  // match id, quality code, etc.). NEVER store name/email/phone/IMEI/GPS.
  // ====================================================
  `CREATE TABLE IF NOT EXISTS analytics_events (
    id            BIGINT AUTO_INCREMENT PRIMARY KEY,
    event_name    VARCHAR(60) NOT NULL,
    device_id     VARCHAR(64),
    session_id    VARCHAR(64),
    payload       JSON,
    created_at    DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_analytics_event_created (event_name, created_at),
    INDEX idx_analytics_device_created (device_id, created_at),
    INDEX idx_analytics_session_created (session_id, created_at),
    INDEX idx_analytics_created (created_at)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,

  // Deduplicated devices = approximate installs / first opens. Upserted on each
  // app_open so first_seen is the install proxy and last_seen drives DAU/MAU.
  `CREATE TABLE IF NOT EXISTS analytics_devices (
    device_id     VARCHAR(64) PRIMARY KEY,
    first_seen    DATETIME DEFAULT CURRENT_TIMESTAMP,
    last_seen     DATETIME DEFAULT CURRENT_TIMESTAMP,
    app_version   VARCHAR(20),
    platform      VARCHAR(10),
    os_version    VARCHAR(30),
    country       VARCHAR(5),
    INDEX idx_analytics_devices_last (last_seen),
    INDEX idx_analytics_devices_first (first_seen),
    INDEX idx_analytics_devices_platform (platform),
    INDEX idx_analytics_devices_version (app_version)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,

  // One row per app usage session. session_id is the PK so repeated heartbeats
  // for the same session UPDATE last_seen instead of inserting duplicates — this
  // is what keeps "Sessions" honest when a user opens/resumes the app many times
  // inside the 30-minute session window. started_at drives "Sessions today".
  `CREATE TABLE IF NOT EXISTS analytics_sessions (
    session_id    VARCHAR(64) PRIMARY KEY,
    device_id     VARCHAR(64),
    started_at    DATETIME DEFAULT CURRENT_TIMESTAMP,
    last_seen     DATETIME DEFAULT CURRENT_TIMESTAMP,
    app_version   VARCHAR(20),
    platform      VARCHAR(10),
    INDEX idx_analytics_sessions_started (started_at),
    INDEX idx_analytics_sessions_device (device_id, started_at)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,
];

async function migrate() {
  const pool = getPool();
  try {
    logger.info('Running database migration...');
    logger.info(`Connecting to MySQL: ${config.db.user}@${config.db.host}:${config.db.port}/${config.db.database}`);

    for (const sql of TABLES) {
      await pool.execute(sql);
    }

    await applyCompatibilityMigrations(pool);
    await seedApiSecurityDefaults(pool);

    logger.info(`Database migration completed successfully (${TABLES.length} tables)`);
  } catch (err) {
    logger.error(`Migration failed: ${err.message || err.toString()}`);
    logger.error(`Error detail: ${JSON.stringify({ code: err.code, errno: err.errno, sqlState: err.sqlState, sqlMessage: err.sqlMessage })}`);
    throw err;
  } finally {
    await pool.end();
  }
}

async function columnExists(pool, tableName, columnName) {
  const [rows] = await pool.execute(
    `SELECT 1
       FROM INFORMATION_SCHEMA.COLUMNS
      WHERE TABLE_SCHEMA = DATABASE()
        AND TABLE_NAME = ?
        AND COLUMN_NAME = ?
      LIMIT 1`,
    [tableName, columnName],
  );
  return rows.length > 0;
}

async function addColumnIfMissing(pool, tableName, columnName, definition) {
  if (await columnExists(pool, tableName, columnName)) return;
  await pool.execute(`ALTER TABLE \`${tableName}\` ADD COLUMN ${definition}`);
  logger.info(`Added missing column ${tableName}.${columnName}`);
}

async function indexExists(pool, tableName, indexName) {
  const [rows] = await pool.execute(
    `SELECT 1
       FROM INFORMATION_SCHEMA.STATISTICS
      WHERE TABLE_SCHEMA = DATABASE()
        AND TABLE_NAME = ?
        AND INDEX_NAME = ?
      LIMIT 1`,
    [tableName, indexName],
  );
  return rows.length > 0;
}

// Adds an index via the given ALTER statement only if neither the index nor
// (for safety) the underlying table is missing. Swallows duplicate-key races so
// concurrent boots don't crash migration. The full ALTER is passed in so unique
// vs plain indexes are explicit at the call site.
async function addIndexIfMissing(pool, tableName, indexName, alterSql) {
  try {
    if (await indexExists(pool, tableName, indexName)) return;
    await pool.execute(alterSql);
    logger.info(`Added missing index ${tableName}.${indexName}`);
  } catch (err) {
    // Duplicate index or a benign race on parallel boot — log and continue.
    logger.debug(`addIndexIfMissing(${tableName}.${indexName}) skipped: ${err.message}`);
  }
}

async function applyCompatibilityMigrations(pool) {
  // ad_settings historically shipped without created_at, but the admin GET
  // route orders by created_at. Add it on existing databases so the ads
  // config can be read back (root cause of "Ads ON saves as OFF").
  await addColumnIfMissing(pool, 'ad_settings', 'created_at', 'created_at DATETIME DEFAULT CURRENT_TIMESTAMP');
  await addColumnIfMissing(pool, 'ad_settings', 'is_public', 'is_public TINYINT(1) DEFAULT 1');
  await addColumnIfMissing(pool, 'ad_settings', 'updated_at', 'updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP');

  await addColumnIfMissing(pool, 'app_settings', 'is_public', 'is_public TINYINT(1) DEFAULT 1');
  await addColumnIfMissing(pool, 'app_settings', 'type', "type VARCHAR(40) DEFAULT 'json'");
  await addColumnIfMissing(pool, 'app_settings', 'group', "`group` VARCHAR(80) DEFAULT 'general'");
  await addColumnIfMissing(pool, 'app_settings', 'description', 'description TEXT');
  await addColumnIfMissing(pool, 'app_settings', 'updated_by', 'updated_by INT NULL');
  await addColumnIfMissing(pool, 'app_settings', 'created_at', 'created_at DATETIME DEFAULT CURRENT_TIMESTAMP');
  await addColumnIfMissing(pool, 'app_settings', 'updated_at', 'updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP');

  await addColumnIfMissing(pool, 'admin_users', 'failed_login_attempts', 'failed_login_attempts INT DEFAULT 0');
  await addColumnIfMissing(pool, 'admin_users', 'locked_until', 'locked_until DATETIME NULL');
  await addColumnIfMissing(pool, 'admin_users', 'last_login_at', 'last_login_at DATETIME NULL');
  await addColumnIfMissing(pool, 'admin_users', 'is_active', 'is_active TINYINT(1) DEFAULT 1');

  await addColumnIfMissing(pool, 'teams', 'slug', 'slug VARCHAR(220) NULL');
  await addColumnIfMissing(pool, 'teams', 'cricbuzz_logo_url', 'cricbuzz_logo_url TEXT NULL');
  await addColumnIfMissing(pool, 'teams', 'is_active', 'is_active TINYINT(1) DEFAULT 1');
  await addColumnIfMissing(pool, 'teams', 'team_type', "team_type VARCHAR(20) DEFAULT 'international'");
  await addColumnIfMissing(pool, 'teams', 'metadata', 'metadata JSON NULL');

  // Player image management (admin-first, mirrors the teams logo split).
  //   admin_image_url    — operator-uploaded photo (highest priority)
  //   provider_image_url — Cricbuzz/provider photo (kept in sync separately
  //                        from the legacy `image_url` so admins can clear an
  //                        override without losing the provider source)
  //   image_mode         — per-player override of the global resolution mode
  //   is_image_active    — toggles the per-player override on/off
  //   is_active          — soft-delete flag (parity with teams)
  await addColumnIfMissing(pool, 'players', 'player_external_id', 'player_external_id VARCHAR(60) NULL');
  await addColumnIfMissing(pool, 'players', 'country', 'country VARCHAR(120) NULL');
  await addColumnIfMissing(pool, 'players', 'admin_image_url', 'admin_image_url TEXT NULL');
  await addColumnIfMissing(pool, 'players', 'provider_image_url', 'provider_image_url TEXT NULL');
  await addColumnIfMissing(pool, 'players', 'image_mode', 'image_mode VARCHAR(20) NULL');
  await addColumnIfMissing(pool, 'players', 'image_updated_at', 'image_updated_at DATETIME NULL');
  await addColumnIfMissing(pool, 'players', 'is_image_active', 'is_image_active TINYINT(1) DEFAULT 1');
  await addColumnIfMissing(pool, 'players', 'is_active', 'is_active TINYINT(1) DEFAULT 1');
  // Cricbuzz sync bookkeeping: when this player was last refreshed from the provider.
  await addColumnIfMissing(pool, 'players', 'last_synced_at', 'last_synced_at DATETIME NULL');
  await addColumnIfMissing(pool, 'players', 'short_name', 'short_name VARCHAR(120) NULL');

  await addColumnIfMissing(pool, 'match_streams', 'match_title', 'match_title VARCHAR(250) NULL');
  await addColumnIfMissing(pool, 'match_streams', 'team_a', 'team_a VARCHAR(180) NULL');
  await addColumnIfMissing(pool, 'match_streams', 'team_b', 'team_b VARCHAR(180) NULL');
  await addColumnIfMissing(pool, 'match_streams', 'backup_stream_url', 'backup_stream_url TEXT NULL');
  await addColumnIfMissing(pool, 'match_streams', 'requires_reward_ad', 'requires_reward_ad TINYINT(1) DEFAULT 0');
  await addColumnIfMissing(pool, 'match_streams', 'requires_login', 'requires_login TINYINT(1) DEFAULT 0');
  await addColumnIfMissing(pool, 'match_streams', 'headers_json', 'headers_json JSON NULL');
  await addColumnIfMissing(pool, 'match_streams', 'origin_header', 'origin_header VARCHAR(400) NULL');
  await addColumnIfMissing(pool, 'match_streams', 'drm_type', "drm_type VARCHAR(40) DEFAULT 'none'");
  await addColumnIfMissing(pool, 'match_streams', 'drm_license_url', 'drm_license_url TEXT NULL');
  await addColumnIfMissing(pool, 'match_streams', 'drm_headers', 'drm_headers JSON NULL');
  await addColumnIfMissing(pool, 'match_streams', 'clear_key_key_id', 'clear_key_key_id VARCHAR(220) NULL');
  await addColumnIfMissing(pool, 'match_streams', 'clear_key_key', 'clear_key_key TEXT NULL');

  // Stream scheduling / visibility controls (Admin Panel "Live Stream" form).
  //   lifecycle_state    — draft | scheduled | active | disabled | expired
  //                        (admin intent; the public API still re-derives the
  //                        effective visibility from time + is_active so a
  //                        stale value can never wrongly reveal a stream)
  //   timezone           — IANA tz the admin entered start/end in (display aid)
  //   early_show_minutes — reveal "Watch Live" this many minutes before start
  //   auto_hide_after_end — hide automatically once ends_at passes
  await addColumnIfMissing(pool, 'match_streams', 'lifecycle_state', "lifecycle_state VARCHAR(20) DEFAULT 'scheduled'");
  await addColumnIfMissing(pool, 'match_streams', 'timezone', 'timezone VARCHAR(64) NULL');
  await addColumnIfMissing(pool, 'match_streams', 'early_show_minutes', 'early_show_minutes INT DEFAULT 0');
  await addColumnIfMissing(pool, 'match_streams', 'auto_hide_after_end', 'auto_hide_after_end TINYINT(1) DEFAULT 1');

  await pool.query(`CREATE TABLE IF NOT EXISTS app_devices (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    subscription_id VARCHAR(220) UNIQUE NOT NULL,
    push_token TEXT,
    platform VARCHAR(40) DEFAULT 'unknown',
    app_version VARCHAR(60),
    build_number VARCHAR(60),
    language VARCHAR(40),
    permission_status VARCHAR(40) DEFAULT 'unknown',
    metadata JSON,
    last_seen_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_app_devices_platform (platform),
    INDEX idx_app_devices_seen (last_seen_at)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`).catch(() => null);
  await pool.query(`CREATE TABLE IF NOT EXISTS notification_history (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    notification_id BIGINT,
    provider VARCHAR(80) DEFAULT 'onesignal',
    target_type VARCHAR(80) DEFAULT 'all',
    target_value VARCHAR(220),
    title VARCHAR(220),
    body TEXT,
    payload JSON,
    provider_response JSON,
    status VARCHAR(40) DEFAULT 'pending',
    sent_count INT DEFAULT 0,
    failed_count INT DEFAULT 0,
    error_message TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_notification_history_created (created_at),
    INDEX idx_notification_history_status (status)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`).catch(() => null);
  // Stable per-install identity (UUID generated once on the device, persisted
  // locally). Decouples the device/user record from the OneSignal
  // subscription_id, which can rotate when the OS refreshes the push token —
  // the historical cause of the same install showing up as multiple devices.
  // Nullable + idempotent so old apps that don't send installId keep working.
  await addColumnIfMissing(pool, 'app_devices', 'install_id', 'install_id VARCHAR(64) NULL');
  // Unique index on install_id (where present) so a re-register with the same
  // install_id but a rotated subscription_id updates the existing row instead of
  // creating a duplicate. MySQL allows multiple NULLs under a UNIQUE index, so
  // legacy rows without an install_id are unaffected.
  await addIndexIfMissing(
    pool,
    'app_devices',
    'uniq_app_devices_install',
    'ALTER TABLE `app_devices` ADD UNIQUE INDEX uniq_app_devices_install (install_id)',
  );

  // Analytics: ensure the sessions table and the first_seen index exist on
  // databases created before session tracking / calendar-day metrics landed.
  await pool.query(`CREATE TABLE IF NOT EXISTS analytics_sessions (
    session_id    VARCHAR(64) PRIMARY KEY,
    device_id     VARCHAR(64),
    started_at    DATETIME DEFAULT CURRENT_TIMESTAMP,
    last_seen     DATETIME DEFAULT CURRENT_TIMESTAMP,
    app_version   VARCHAR(20),
    platform      VARCHAR(10),
    INDEX idx_analytics_sessions_started (started_at),
    INDEX idx_analytics_sessions_device (device_id, started_at)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`).catch(() => null);
  await addIndexIfMissing(
    pool,
    'analytics_devices',
    'idx_analytics_devices_first',
    'ALTER TABLE `analytics_devices` ADD INDEX idx_analytics_devices_first (first_seen)',
  );

  await addColumnIfMissing(pool, 'push_notifications', 'payload', 'payload JSON NULL');
  await addColumnIfMissing(pool, 'push_notifications', 'provider_response', 'provider_response JSON NULL');
  await addColumnIfMissing(pool, 'push_notifications', 'error_message', 'error_message TEXT NULL');

  // Automated-notification de-duplication log. A UNIQUE dedupe_key guarantees a
  // logical event (stream published, new innings, ...) fires at most ONCE,
  // surviving repeated admin saves, duplicate poll ticks, and backend restarts.
  // See lib/notification-dedupe.js. status: pending | sent | failed | skipped.
  await pool.query(`CREATE TABLE IF NOT EXISTS notification_log (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    match_external_id VARCHAR(80) NOT NULL,
    event_type VARCHAR(40) NOT NULL,
    dedupe_key VARCHAR(180) NOT NULL,
    stream_id BIGINT NULL,
    status VARCHAR(20) DEFAULT 'pending',
    title VARCHAR(220) NULL,
    body TEXT NULL,
    provider_response JSON NULL,
    error_message TEXT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    sent_at DATETIME NULL,
    UNIQUE KEY uniq_notification_dedupe (dedupe_key),
    INDEX idx_notification_log_match (match_external_id, event_type),
    INDEX idx_notification_log_created (created_at)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`).catch(() => null);

  await addColumnIfMissing(pool, 'cache_events', 'cache_key', 'cache_key VARCHAR(300) NULL');
  await addColumnIfMissing(pool, 'cache_events', 'data_type', 'data_type VARCHAR(80) NULL');
  await addColumnIfMissing(pool, 'cache_events', 'action', 'action VARCHAR(80) NULL');
  await addColumnIfMissing(pool, 'cache_events', 'status', 'status VARCHAR(40) NULL');
  await addColumnIfMissing(pool, 'cache_events', 'provider_id', 'provider_id INT NULL');
  await addColumnIfMissing(pool, 'cache_events', 'duration_ms', 'duration_ms INT NULL');
  await addColumnIfMissing(pool, 'cache_events', 'error_message', 'error_message TEXT NULL');
  await addColumnIfMissing(pool, 'cache_events', 'details', 'details JSON NULL');

  // ----------------------------------------------------------------
  // Featured Series — manual entries managed from the Admin Panel.
  // The cricket provider does not expose a "featured series" feed, so
  // operators add these by hand with a poster, name, date range and
  // location. These columns are additive and backward compatible: rows
  // that only carry a provider series_external_id keep working.
  // ----------------------------------------------------------------
  await addColumnIfMissing(pool, 'featured_series', 'title', 'title VARCHAR(220) NULL');
  await addColumnIfMissing(pool, 'featured_series', 'subtitle', 'subtitle VARCHAR(220) NULL');
  await addColumnIfMissing(pool, 'featured_series', 'date_range', 'date_range VARCHAR(140) NULL');
  await addColumnIfMissing(pool, 'featured_series', 'location', 'location VARCHAR(180) NULL');
  await addColumnIfMissing(pool, 'featured_series', 'image_url', 'image_url TEXT NULL');
  // Series hero banner fields (admin-managed). These power the premium Series
  // screen hero: a format summary line and the two flanking teams (name, short
  // code and a server logo URL). All additive + nullable, so existing manual
  // featured-series rows keep working untouched.
  await addColumnIfMissing(pool, 'featured_series', 'format_text', 'format_text VARCHAR(180) NULL');
  await addColumnIfMissing(pool, 'featured_series', 'team_a_name', 'team_a_name VARCHAR(120) NULL');
  await addColumnIfMissing(pool, 'featured_series', 'team_a_short', 'team_a_short VARCHAR(24) NULL');
  await addColumnIfMissing(pool, 'featured_series', 'team_a_logo', 'team_a_logo TEXT NULL');
  await addColumnIfMissing(pool, 'featured_series', 'team_b_name', 'team_b_name VARCHAR(120) NULL');
  await addColumnIfMissing(pool, 'featured_series', 'team_b_short', 'team_b_short VARCHAR(24) NULL');
  await addColumnIfMissing(pool, 'featured_series', 'team_b_logo', 'team_b_logo TEXT NULL');
  await addColumnIfMissing(pool, 'featured_series', 'cta_label', 'cta_label VARCHAR(80) NULL');
  await addColumnIfMissing(pool, 'featured_series', 'cta_url', 'cta_url TEXT NULL');
  await addColumnIfMissing(pool, 'featured_series', 'starts_at', 'starts_at DATETIME NULL');
  await addColumnIfMissing(pool, 'featured_series', 'ends_at', 'ends_at DATETIME NULL');
  await addColumnIfMissing(pool, 'featured_series', 'updated_at', 'updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP');
  // The provider-linked id. Older databases (created from admin-panel-schema.sql)
  // shipped this column as `external_id` and lacked `series_external_id`, which
  // is the name every route/query uses. Add it idempotently so manual series
  // inserts (which write series_external_id) work on existing installs.
  await addColumnIfMissing(pool, 'featured_series', 'series_external_id', 'series_external_id VARCHAR(191) NULL');

  // The admin-panel-schema.sql variant of the featured_* tables only had
  // (id, external_id, sort_order, created_at). Every route also writes
  // sort_order / is_active / note / created_by, so ensure those exist on all
  // three tables. Idempotent and safe on freshly-created tables too.
  for (const table of ['featured_series', 'featured_matches', 'featured_news']) {
    await addColumnIfMissing(pool, table, 'sort_order', 'sort_order INT DEFAULT 100');
    await addColumnIfMissing(pool, table, 'is_active', 'is_active TINYINT(1) DEFAULT 1');
    await addColumnIfMissing(pool, table, 'note', 'note TEXT NULL');
    await addColumnIfMissing(pool, table, 'created_by', 'created_by INT NULL');
    await addColumnIfMissing(pool, table, 'created_at', 'created_at DATETIME DEFAULT CURRENT_TIMESTAMP');
  }
  // Canonical id columns each route uses (legacy schema used `external_id`).
  await addColumnIfMissing(pool, 'featured_matches', 'match_external_id', 'match_external_id VARCHAR(80) NULL');
  await addColumnIfMissing(pool, 'featured_matches', 'starts_at', 'starts_at DATETIME NULL');
  await addColumnIfMissing(pool, 'featured_matches', 'ends_at', 'ends_at DATETIME NULL');
  await addColumnIfMissing(pool, 'featured_news', 'news_id', 'news_id VARCHAR(120) NULL');

  // Backfill canonical id columns from a legacy `external_id` column, once.
  for (const [table, target] of [
    ['featured_series', 'series_external_id'],
    ['featured_matches', 'match_external_id'],
    ['featured_news', 'news_id'],
  ]) {
    // eslint-disable-next-line no-await-in-loop
    if (
      (await columnExists(pool, table, 'external_id')) &&
      (await columnExists(pool, table, target))
    ) {
      // eslint-disable-next-line no-await-in-loop
      await pool
        .execute(`UPDATE \`${table}\` SET \`${target}\` = \`external_id\` WHERE \`${target}\` IS NULL AND \`external_id\` IS NOT NULL`)
        .catch(() => null);
    }
  }

  // Allow purely-manual series that have no provider id.
  await pool
    .execute('ALTER TABLE `featured_series` MODIFY COLUMN `series_external_id` VARCHAR(191) NULL')
    .catch(() => null);

  // Legacy `external_id` columns were created NOT NULL with no default. Manual
  // inserts never set them (they use the canonical *_external_id / news_id
  // columns), so relax them to NULL to avoid ER_NO_DEFAULT_FOR_FIELD.
  for (const table of ['featured_series', 'featured_matches', 'featured_news']) {
    // eslint-disable-next-line no-await-in-loop
    if (await columnExists(pool, table, 'external_id')) {
      // eslint-disable-next-line no-await-in-loop
      await pool
        .execute(`ALTER TABLE \`${table}\` MODIFY COLUMN \`external_id\` VARCHAR(191) NULL`)
        .catch(() => null);
    }
  }

  // Featured Matches — add updated_at for parity with the admin list ordering.
  await addColumnIfMissing(pool, 'featured_matches', 'updated_at', 'updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP');

  // ---- Schema verification: log any still-missing required columns ----------
  const requiredCols = {
    featured_series: ['series_external_id', 'title', 'subtitle', 'date_range', 'location', 'image_url', 'cta_label', 'cta_url', 'sort_order', 'is_active', 'note', 'created_by', 'starts_at', 'ends_at'],
    featured_matches: ['match_external_id', 'sort_order', 'is_active', 'note', 'created_by', 'starts_at', 'ends_at'],
    featured_news: ['news_id', 'sort_order', 'is_active', 'note', 'created_by'],
  };
  for (const [table, cols] of Object.entries(requiredCols)) {
    const missing = [];
    for (const col of cols) {
      // eslint-disable-next-line no-await-in-loop
      if (!(await columnExists(pool, table, col))) missing.push(col);
    }
    if (missing.length) {
      logger.error(`${table} is MISSING columns after migration: ${missing.join(', ')}`);
    } else {
      logger.info(`${table} schema verified — all required columns present`);
    }
  }
}

// ====================================================
// Seed safe API-security defaults (idempotent).
//   - endpoint group rules
//   - allowed origins (admin panel + dev localhost)
//   - a default CricPro Android client (so the app keeps working)
// Uses INSERT ... ON DUPLICATE / existence checks so re-running is safe and
// never overwrites operator edits made from the Admin Panel.
// ====================================================
async function seedApiSecurityDefaults(pool) {
  // ----- Endpoint rules -----
  const endpointRules = [
    { group: 'health', pattern: '/health', auth: 'none', types: ['android', 'ios', 'web', 'server', 'admin'], rpm: 120, ttl: 0 },
    { group: 'app_config', pattern: '/app/config', auth: 'api_key', types: ['android', 'ios', 'web', 'server'], rpm: 120, ttl: 0 },
    { group: 'matches', pattern: '/matches', auth: 'api_key', types: ['android', 'ios', 'web', 'server'], rpm: 240, ttl: 0 },
    { group: 'match_details', pattern: '/match', auth: 'api_key', types: ['android', 'ios', 'web', 'server'], rpm: 240, ttl: 0 },
    { group: 'commentary', pattern: '/match/:id/commentary', auth: 'api_key', types: ['android', 'ios', 'web', 'server'], rpm: 300, ttl: 0 },
    { group: 'scorecard', pattern: '/match/:id/scorecard', auth: 'api_key', types: ['android', 'ios', 'web', 'server'], rpm: 240, ttl: 0 },
    { group: 'series', pattern: '/series', auth: 'api_key', types: ['android', 'ios', 'web', 'server'], rpm: 120, ttl: 0 },
    { group: 'players', pattern: '/player', auth: 'api_key', types: ['android', 'ios', 'web', 'server'], rpm: 120, ttl: 0 },
    { group: 'teams', pattern: '/team', auth: 'api_key', types: ['android', 'ios', 'web', 'server'], rpm: 120, ttl: 0 },
    { group: 'streams', pattern: '/match/:id/streams', auth: 'api_key', types: ['android', 'ios', 'web'], rpm: 120, ttl: 0 },
    { group: 'news', pattern: '/news', auth: 'api_key', types: ['android', 'ios', 'web', 'server'], rpm: 120, ttl: 0 },
    { group: 'rankings', pattern: '/rankings', auth: 'api_key', types: ['android', 'ios', 'web', 'server'], rpm: 120, ttl: 0 },
    { group: 'schedule', pattern: '/schedule', auth: 'api_key', types: ['android', 'ios', 'web', 'server'], rpm: 120, ttl: 0 },
    { group: 'notifications_device_register', pattern: '/app/device', auth: 'api_key', types: ['android', 'ios', 'web'], rpm: 60, ttl: 0 },
    { group: 'analytics_ingest', pattern: '/analytics/events', auth: 'none', types: ['android', 'ios', 'web', 'server'], rpm: 100, ttl: 0 },
    { group: 'admin', pattern: '/admin', auth: 'admin_jwt', types: ['admin'], rpm: 600, ttl: 0 },
  ];
  for (const r of endpointRules) {
    await pool.execute(
      `INSERT INTO api_endpoint_rules
         (group_name, path_pattern, methods, enabled, auth_required, allowed_client_types, rate_limit_per_minute, cache_ttl_seconds, logging_enabled)
       VALUES (?, ?, ?, 1, ?, ?, ?, ?, 1)
       ON DUPLICATE KEY UPDATE path_pattern = path_pattern`,
      [r.group, r.pattern, JSON.stringify(['GET', 'POST', 'PUT', 'DELETE']), r.auth, JSON.stringify(r.types), r.rpm, r.ttl],
    ).catch((err) => logger.warn(`seed endpoint rule ${r.group} failed: ${err.message}`));
  }

  // ----- Allowed origins (admin panel + dev) -----
  const adminOrigin = process.env.ADMIN_PANEL_ORIGIN || 'https://admin.webcrichd.co';
  const seedOrigins = [
    { origin: adminOrigin, domain: null, notes: 'Admin panel (auto-seeded)' },
  ];
  if (config.isDev) {
    seedOrigins.push(
      { origin: 'http://localhost:3000', domain: 'localhost', notes: 'Dev admin panel' },
      { origin: 'http://localhost:5173', domain: 'localhost', notes: 'Dev web' },
    );
  }
  for (const o of seedOrigins) {
    const [existing] = await pool.execute(
      `SELECT id FROM api_allowed_origins WHERE origin = ? LIMIT 1`,
      [o.origin],
    );
    if (existing.length) continue;
    await pool.execute(
      `INSERT INTO api_allowed_origins (origin, domain, status, allowed_endpoint_groups, rate_limit_per_minute, notes)
       VALUES (?, ?, 'active', NULL, 240, ?)`,
      [o.origin, o.domain, o.notes],
    ).catch((err) => logger.warn(`seed origin ${o.origin} failed: ${err.message}`));
  }

  // ----- Default CricPro Android client -----
  const keyHash = crypto.createHash('sha256').update(DEFAULT_APP_API_KEY).digest('hex');
  const [client] = await pool.execute(
    `SELECT id FROM api_clients WHERE api_key_hash = ? LIMIT 1`,
    [keyHash],
  );
  if (!client.length) {
    await pool.execute(
      `INSERT INTO api_clients
         (name, client_type, api_key_hash, api_key_prefix, allowed_origins, allowed_domains,
          allowed_package_names, allowed_bundle_ids, scopes, rate_limit_per_minute, rate_limit_per_hour,
          rate_limit_per_day, status, notes)
       VALUES (?, 'android', ?, ?, NULL, NULL, ?, ?, ?, 240, 8000, 200000, 'active', ?)`,
      [
        'CricPro Android (default)',
        keyHash,
        DEFAULT_APP_API_KEY.slice(0, 12),
        JSON.stringify(['com.example.cricpro_flutter', 'com.cricpro.app']),
        JSON.stringify(['com.cricpro.app']),
        JSON.stringify(['matches', 'match_details', 'commentary', 'scorecard', 'series', 'players', 'teams', 'streams', 'news', 'rankings', 'schedule', 'app_config', 'notifications_device_register']),
        'Auto-seeded default app client. Regenerate from Admin Panel for production.',
      ],
    ).catch((err) => logger.warn(`seed default client failed: ${err.message}`));
    logger.info('Seeded default CricPro Android API client');
  }
}

migrate().catch((err) => {
  console.error('Migration error:', err.message || err);
  process.exit(1);
});
