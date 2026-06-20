# Database Setup Guide - Fix "Table doesn't exist" Error

## Problem

You're getting this error:
```
Error: Table 'webcrichdapi.admin_roles' doesn't exist
```

This means the database tables haven't been created yet.

---

## Solution: Create Database Tables

### Option 1: Quick Setup (Recommended)

Run these commands on your server:

```bash
# Navigate to your API directory
cd ~/htdocs/api.webcrichd.co

# Import the schema
mysql -u your_db_user -p webcrichdapi < migrations/admin-panel-schema.sql

# When prompted, enter your database password

# After schema is imported, run the seed script
node src/admin/db/admin-seed.js
```

### Option 2: Manual Setup

**Step 1: Login to MySQL**

```bash
mysql -u your_db_user -p webcrichdapi
```

**Step 2: Copy and paste the entire schema**

Open the file `migrations/admin-panel-schema.sql` and copy all the SQL commands, then paste them into the MySQL prompt.

Or run it directly:

```bash
mysql -u your_db_user -p webcrichdapi < migrations/admin-panel-schema.sql
```

**Step 3: Verify tables were created**

```sql
SHOW TABLES;
```

You should see these tables:
- admin_users
- admin_roles
- admin_permissions
- admin_user_roles
- admin_role_permissions
- admin_audit_logs
- admin_login_attempts
- home_sections
- featured_matches
- featured_series
- featured_news
- banners
- news
- notifications
- app_settings

**Step 4: Exit MySQL and run seed script**

```bash
exit
node src/admin/db/admin-seed.js
```

---

## Complete Command Sequence

Here's the exact sequence of commands to run on your server:

```bash
# 1. Navigate to API directory
cd ~/htdocs/api.webcrichd.co

# 2. Check if migrations folder exists
ls -la migrations/

# 3. Import schema (replace 'your_db_user' with your actual username)
mysql -u your_db_user -p webcrichdapi < migrations/admin-panel-schema.sql

# 4. Verify tables were created
mysql -u your_db_user -p webcrichdapi -e "SHOW TABLES;"

# 5. Run seed script
node src/admin/db/admin-seed.js

# 6. You should see output like:
# {"level":"info","message":"Seeding admin panel roles + permissions..."}
# {"level":"info","message":"Created super admin: admin@cricpro.local"}
# ==============================================
#  Super-admin credentials (save these now):
#    email:    admin@cricpro.local
#    password: [RANDOM_PASSWORD]
# ==============================================
```

---

## If migrations folder doesn't exist

The schema file is in the deployment package. You need to:

1. **Create the migrations folder:**
```bash
cd ~/htdocs/api.webcrichd.co
mkdir -p migrations
```

2. **Create the schema file:**
```bash
nano migrations/admin-panel-schema.sql
```

3. **Copy the schema** from the file I created (see below)

4. **Save and exit** (Ctrl+X, then Y, then Enter)

5. **Run the import:**
```bash
mysql -u your_db_user -p webcrichdapi < migrations/admin-panel-schema.sql
```

---

## Quick Copy-Paste Schema

If you need to create the file manually, here's a minimal version:

```sql
-- Admin Users
CREATE TABLE IF NOT EXISTS `admin_users` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `email` VARCHAR(255) NOT NULL,
  `name` VARCHAR(255) NOT NULL,
  `password_hash` VARCHAR(255) NOT NULL,
  `is_active` TINYINT(1) NOT NULL DEFAULT 1,
  `last_login_at` DATETIME NULL,
  `last_login_ip` VARCHAR(45) NULL,
  `password_changed_at` DATETIME NULL,
  `refresh_token_hash` VARCHAR(255) NULL,
  `refresh_token_expires_at` DATETIME NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `email` (`email`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Admin Roles
CREATE TABLE IF NOT EXISTS `admin_roles` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `slug` VARCHAR(50) NOT NULL,
  `name` VARCHAR(100) NOT NULL,
  `description` TEXT NULL,
  `is_system` TINYINT(1) NOT NULL DEFAULT 0,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `slug` (`slug`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Admin Permissions
CREATE TABLE IF NOT EXISTS `admin_permissions` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `slug` VARCHAR(100) NOT NULL,
  `name` VARCHAR(100) NOT NULL,
  `description` TEXT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `slug` (`slug`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Admin User Roles
CREATE TABLE IF NOT EXISTS `admin_user_roles` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id` INT UNSIGNED NOT NULL,
  `role_id` INT UNSIGNED NOT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `user_role` (`user_id`, `role_id`),
  CONSTRAINT `admin_user_roles_user_fk` FOREIGN KEY (`user_id`) REFERENCES `admin_users` (`id`) ON DELETE CASCADE,
  CONSTRAINT `admin_user_roles_role_fk` FOREIGN KEY (`role_id`) REFERENCES `admin_roles` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Admin Role Permissions
CREATE TABLE IF NOT EXISTS `admin_role_permissions` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `role_id` INT UNSIGNED NOT NULL,
  `permission_id` INT UNSIGNED NOT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `role_permission` (`role_id`, `permission_id`),
  CONSTRAINT `admin_role_permissions_role_fk` FOREIGN KEY (`role_id`) REFERENCES `admin_roles` (`id`) ON DELETE CASCADE,
  CONSTRAINT `admin_role_permissions_permission_fk` FOREIGN KEY (`permission_id`) REFERENCES `admin_permissions` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Admin Audit Logs
CREATE TABLE IF NOT EXISTS `admin_audit_logs` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `admin_user_id` INT UNSIGNED NULL,
  `admin_email` VARCHAR(255) NULL,
  `action` VARCHAR(100) NOT NULL,
  `entity_type` VARCHAR(50) NULL,
  `entity_id` VARCHAR(100) NULL,
  `old_value` JSON NULL,
  `new_value` JSON NULL,
  `ip_address` VARCHAR(45) NULL,
  `user_agent` TEXT NULL,
  `status` VARCHAR(20) NULL DEFAULT 'success',
  `error_message` TEXT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `action` (`action`),
  KEY `created_at` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Admin Login Attempts
CREATE TABLE IF NOT EXISTS `admin_login_attempts` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `ip_address` VARCHAR(45) NOT NULL,
  `email` VARCHAR(255) NULL,
  `success` TINYINT(1) NOT NULL DEFAULT 0,
  `user_agent` TEXT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `ip_address` (`ip_address`),
  KEY `created_at` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Home Sections
CREATE TABLE IF NOT EXISTS `home_sections` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `slug` VARCHAR(100) NOT NULL,
  `title` VARCHAR(255) NOT NULL,
  `section_type` VARCHAR(50) NOT NULL,
  `sort_order` INT NOT NULL DEFAULT 100,
  `is_active` TINYINT(1) NOT NULL DEFAULT 1,
  `starts_at` DATETIME NULL,
  `ends_at` DATETIME NULL,
  `payload` JSON NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `slug` (`slug`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Featured Matches
CREATE TABLE IF NOT EXISTS `featured_matches` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `external_id` VARCHAR(100) NOT NULL,
  `sort_order` INT NOT NULL DEFAULT 100,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `external_id` (`external_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Featured Series
CREATE TABLE IF NOT EXISTS `featured_series` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `external_id` VARCHAR(100) NOT NULL,
  `sort_order` INT NOT NULL DEFAULT 100,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `external_id` (`external_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Featured News
CREATE TABLE IF NOT EXISTS `featured_news` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `external_id` VARCHAR(100) NOT NULL,
  `sort_order` INT NOT NULL DEFAULT 100,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `external_id` (`external_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Banners
CREATE TABLE IF NOT EXISTS `banners` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `placement` VARCHAR(50) NOT NULL,
  `title` VARCHAR(255) NULL,
  `image_url` TEXT NOT NULL,
  `cta_url` TEXT NULL,
  `is_active` TINYINT(1) NOT NULL DEFAULT 1,
  `sort_order` INT NOT NULL DEFAULT 100,
  `starts_at` DATETIME NULL,
  `ends_at` DATETIME NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- News
CREATE TABLE IF NOT EXISTS `news` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `headline` VARCHAR(500) NOT NULL,
  `context` TEXT NULL,
  `body` TEXT NULL,
  `story_type` VARCHAR(50) NOT NULL DEFAULT 'custom',
  `image_url` TEXT NULL,
  `source` VARCHAR(100) NOT NULL DEFAULT 'CricPro',
  `is_featured` TINYINT(1) NOT NULL DEFAULT 0,
  `is_hidden` TINYINT(1) NOT NULL DEFAULT 0,
  `sort_order` INT NOT NULL DEFAULT 100,
  `published_at` DATETIME NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Notifications
CREATE TABLE IF NOT EXISTS `notifications` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `title` VARCHAR(255) NOT NULL,
  `body` TEXT NOT NULL,
  `image_url` TEXT NULL,
  `target_type` VARCHAR(50) NOT NULL DEFAULT 'all',
  `target_value` VARCHAR(255) NULL,
  `deep_link_type` VARCHAR(50) NULL,
  `deep_link_value` VARCHAR(255) NULL,
  `status` VARCHAR(20) NOT NULL DEFAULT 'draft',
  `scheduled_at` DATETIME NULL,
  `sent_at` DATETIME NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- App Settings
CREATE TABLE IF NOT EXISTS `app_settings` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `setting_key` VARCHAR(100) NOT NULL,
  `setting_value` JSON NOT NULL,
  `setting_group` VARCHAR(50) NOT NULL DEFAULT 'general',
  `description` TEXT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `setting_key` (`setting_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

---

## Troubleshooting

### Error: "Access denied for user"
- Check your database credentials in `.env` file
- Make sure DB_USER and DB_PASSWORD are correct

### Error: "Unknown database"
- Create the database first:
```bash
mysql -u your_db_user -p -e "CREATE DATABASE webcrichdapi CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
```

### Error: "Can't connect to MySQL server"
- Make sure MySQL is running:
```bash
sudo systemctl status mysql
```

### Schema file not found
- Make sure you're in the correct directory
- Check if migrations folder exists
- Create the schema file manually (see above)

---

## After Successful Setup

You should see output like this:

```
{"level":"info","message":"Seeding admin panel roles + permissions..."}
{"level":"info","message":"Created super admin: admin@cricpro.local"}
==============================================
 Super-admin credentials (save these now):
   email:    admin@cricpro.local
   password: [RANDOM_PASSWORD_HERE]
==============================================
{"level":"info","message":"Admin seed complete."}
```

**IMPORTANT:** Save the password shown in the output! You'll need it to login.

---

## Summary

**Quick Fix:**
```bash
cd ~/htdocs/api.webcrichd.co
mysql -u your_db_user -p webcrichdapi < migrations/admin-panel-schema.sql
node src/admin/db/admin-seed.js
```

That's it! The tables will be created and your admin user will be ready to use.
