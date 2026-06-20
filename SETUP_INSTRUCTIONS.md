# Setup Instructions for CricPro Admin Panel

## Issue Resolved ✅

The error "body must have required property 'username'" was caused by the frontend trying to connect to a production API URL instead of your local backend.

### What Was Fixed:
1. Updated `.env.local` to point to local backend: `http://localhost:5000`
2. Restarted the admin panel dev server

## Current Status

### ✅ Running:
- **Admin Panel**: http://localhost:3000 (Port 3000)

### ❌ Not Running (Required):
- **Backend API**: Port 5000 (needs Redis and MySQL)
- **Redis**: Port 6379
- **MySQL**: Port 3306

## Prerequisites

To run the complete system, you need:

1. **MySQL/Percona** - Database
2. **Redis** - Caching and sessions
3. **Node.js** - Runtime

## Setup Steps

### 1. Start Redis

**Windows (using WSL or Docker):**
```bash
# Using Docker
docker run -d -p 6379:6379 redis:latest

# Or using WSL
wsl
sudo service redis-server start
```

**Check if Redis is running:**
```bash
redis-cli ping
# Should return: PONG
```

### 2. Start MySQL

**Windows:**
```bash
# If using XAMPP
Start XAMPP Control Panel → Start MySQL

# If using standalone MySQL
net start MySQL80
```

**Check if MySQL is running:**
```bash
mysql -u root -p
# Enter password (empty by default in .env)
```

### 3. Create Database and Run Migrations

```bash
cd cricket-api

# Create database
mysql -u root -p -e "CREATE DATABASE IF NOT EXISTS crickadmin;"

# Run migrations (if you have migration files)
# npm run migrate

# Or manually import the schema if you have a SQL file
# mysql -u root -p crickadmin < schema.sql
```

### 4. Seed Admin User

```bash
cd cricket-api

# Option 1: Set credentials in .env first
# Add to cricket-api/.env:
# ADMIN_SEED_EMAIL=admin@cricpro.local
# ADMIN_SEED_PASSWORD=admin123

# Then run seed
node src/admin/db/admin-seed.js

# Option 2: Run without setting password (generates random)
# The password will be printed to console ONCE
node src/admin/db/admin-seed.js
```

### 5. Start Backend API

```bash
cd cricket-api
node src/server.js
```

**Expected output:**
```
Server listening on http://0.0.0.0:5000
Redis connected
MySQL connected
```

### 6. Start Admin Panel (Already Running)

```bash
cd admin-panel
npm run dev
```

**Already running at:** http://localhost:3000

## Login Credentials

### Default Email:
```
admin@cricpro.local
```

### Password Options:

**Option 1: Set in .env (Recommended for development)**
Add to `cricket-api/.env`:
```env
ADMIN_SEED_EMAIL=admin@cricpro.local
ADMIN_SEED_PASSWORD=admin123
```

Then run: `node src/admin/db/admin-seed.js`

**Option 2: Use generated password**
If you didn't set `ADMIN_SEED_PASSWORD`, the seed script generates a random password and prints it to console. Look for:
```
==============================================
 Super-admin credentials (save these now):    
   email:    admin@cricpro.local
   password: [RANDOM_PASSWORD_HERE]
==============================================
```

## Quick Start (If Everything is Installed)

```bash
# Terminal 1: Start Redis
docker run -d -p 6379:6379 redis:latest

# Terminal 2: Start MySQL (if not already running)
# XAMPP or: net start MySQL80

# Terminal 3: Start Backend API
cd cricket-api
node src/server.js

# Terminal 4: Admin Panel (already running)
# http://localhost:3000
```

## Troubleshooting

### Error: "ECONNREFUSED ::1:6379"
**Solution:** Redis is not running. Start Redis first.

### Error: "ECONNREFUSED 127.0.0.1:3306"
**Solution:** MySQL is not running. Start MySQL first.

### Error: "body must have required property 'username'"
**Solution:** ✅ Already fixed! The .env.local now points to localhost.

### Error: "Invalid email or password"
**Solutions:**
1. Make sure you ran the seed script: `node src/admin/db/admin-seed.js`
2. Check the password you're using matches what was set/generated
3. Try resetting by adding password to .env and re-running seed

### Backend API won't start
**Check:**
1. Redis is running: `redis-cli ping`
2. MySQL is running: `mysql -u root -p`
3. Database exists: `mysql -u root -p -e "SHOW DATABASES;"`
4. .env file has correct credentials

## Environment Files

### cricket-api/.env
```env
NODE_ENV=development
PORT=5000
HOST=0.0.0.0

DB_HOST=127.0.0.1
DB_PORT=3306
DB_USER=root
DB_PASSWORD=
DB_NAME=crickadmin

REDIS_URL=redis://localhost:6379
REDIS_PASSWORD=

JWT_SECRET=change-this-to-a-very-long-random-string
JWT_EXPIRES_IN=7d

# Admin seed credentials (optional)
ADMIN_SEED_EMAIL=admin@cricpro.local
ADMIN_SEED_PASSWORD=admin123
```

### admin-panel/.env.local
```env
NEXT_PUBLIC_API_BASE_URL=http://localhost:5000
```

## Testing the Setup

1. **Open Admin Panel**: http://localhost:3000
2. **Login with**:
   - Email: `admin@cricpro.local`
   - Password: `admin123` (or your generated password)
3. **Test pages**:
   - Dashboard
   - Streams
   - Matches
   - All new pages (Homepage, News, Notifications, etc.)

## Production Deployment

For production, update:

1. **admin-panel/.env.local**:
   ```env
   NEXT_PUBLIC_API_BASE_URL=https://api.webcrichd.co
   ```

2. **cricket-api/.env**:
   ```env
   NODE_ENV=production
   JWT_SECRET=[STRONG_RANDOM_STRING]
   ADMIN_SEED_PASSWORD=[STRONG_PASSWORD]
   ```

## Summary

✅ **Admin Panel**: Running on port 3000
✅ **Environment**: Configured for localhost
⏳ **Backend API**: Needs Redis and MySQL to start
⏳ **Database**: Needs to be created and seeded

Once Redis and MySQL are running, the backend API will start successfully and you'll be able to login!
