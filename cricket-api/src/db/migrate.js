import { getPool } from '../lib/db.js';
import config from '../config/index.js';
import logger from '../lib/logger.js';

const TABLES = [
  // ====================================================
  // TEAMS
  // ====================================================
  `CREATE TABLE IF NOT EXISTS teams (
    id            INT AUTO_INCREMENT PRIMARY KEY,
    external_id   VARCHAR(50) UNIQUE,
    name          VARCHAR(200) NOT NULL,
    short_name    VARCHAR(20),
    logo_url      TEXT,
    country       VARCHAR(100),
    team_type     VARCHAR(20) DEFAULT 'international',
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
    title VARCHAR(250),
    quality ENUM('AUTO','FHD','HD','SD') DEFAULT 'AUTO',
    label VARCHAR(80),
    language VARCHAR(80) DEFAULT 'English',
    server_id INT,
    server_name VARCHAR(160),
    stream_type ENUM('hls','dash','iframe','external') DEFAULT 'hls',
    stream_url TEXT NOT NULL,
    is_active TINYINT(1) DEFAULT 1,
    is_premium TINYINT(1) DEFAULT 0,
    priority INT DEFAULT 100,
    status ENUM('working','slow','down','unknown') DEFAULT 'unknown',
    starts_at DATETIME,
    ends_at DATETIME,
    geo_blocked_countries JSON,
    user_agent_header VARCHAR(400),
    referer_header VARCHAR(400),
    drm_enabled TINYINT(1) DEFAULT 0,
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

  `CREATE TABLE IF NOT EXISTS ad_settings (
    id INT AUTO_INCREMENT PRIMARY KEY,
    setting_key VARCHAR(120) UNIQUE NOT NULL,
    setting_value JSON,
    is_public TINYINT(1) DEFAULT 1,
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

async function applyCompatibilityMigrations(pool) {
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

  await addColumnIfMissing(pool, 'cache_events', 'cache_key', 'cache_key VARCHAR(300) NULL');
  await addColumnIfMissing(pool, 'cache_events', 'data_type', 'data_type VARCHAR(80) NULL');
  await addColumnIfMissing(pool, 'cache_events', 'action', 'action VARCHAR(80) NULL');
  await addColumnIfMissing(pool, 'cache_events', 'status', 'status VARCHAR(40) NULL');
  await addColumnIfMissing(pool, 'cache_events', 'provider_id', 'provider_id INT NULL');
  await addColumnIfMissing(pool, 'cache_events', 'duration_ms', 'duration_ms INT NULL');
  await addColumnIfMissing(pool, 'cache_events', 'error_message', 'error_message TEXT NULL');
  await addColumnIfMissing(pool, 'cache_events', 'details', 'details JSON NULL');
}

migrate().catch((err) => {
  console.error('Migration error:', err.message || err);
  process.exit(1);
});
