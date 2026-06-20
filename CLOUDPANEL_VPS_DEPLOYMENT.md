# CricPro Admin Panel - CloudPanel VPS Deployment Guide

## Table of Contents
1. [Prerequisites](#prerequisites)
2. [Server Setup](#server-setup)
3. [Install Dependencies](#install-dependencies)
4. [Database Setup](#database-setup)
5. [Backend API Deployment](#backend-api-deployment)
6. [Admin Panel Deployment](#admin-panel-deployment)
7. [SSL Certificate Setup](#ssl-certificate-setup)
8. [Process Management with PM2](#process-management-with-pm2)
9. [Nginx Configuration](#nginx-configuration)
10. [Security Hardening](#security-hardening)
11. [Monitoring & Maintenance](#monitoring--maintenance)

---

## Prerequisites

### What You Need:
- CloudPanel VPS (Ubuntu 20.04/22.04 recommended)
- Domain names:
  - `api.yourdomain.com` (for Backend API)
  - `admin.yourdomain.com` (for Admin Panel)
- SSH access to your VPS
- CloudPanel admin access

### Recommended VPS Specs:
- **Minimum**: 2 CPU cores, 4GB RAM, 50GB SSD
- **Recommended**: 4 CPU cores, 8GB RAM, 100GB SSD

---

## 1. Server Setup

### Step 1.1: Connect to Your VPS

```bash
ssh root@your-vps-ip
```

### Step 1.2: Update System

```bash
apt update && apt upgrade -y
```

### Step 1.3: Install CloudPanel (if not already installed)

```bash
# For Ubuntu 22.04
curl -sS https://installer.cloudpanel.io/ce/v2/install.sh -o install.sh
sudo bash install.sh

# Access CloudPanel at: https://your-vps-ip:8443
```

### Step 1.4: Create a Non-Root User

```bash
adduser cricpro
usermod -aG sudo cricpro
su - cricpro
```

---

## 2. Install Dependencies

### Step 2.1: Install Node.js (v18 or higher)

```bash
# Install NVM
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
source ~/.bashrc

# Install Node.js
nvm install 18
nvm use 18
nvm alias default 18

# Verify
node -v  # Should show v18.x.x
npm -v
```

### Step 2.2: Install MySQL (via CloudPanel)

CloudPanel comes with MySQL pre-installed. Access it via:

```bash
# Check MySQL status
sudo systemctl status mysql

# Access MySQL
mysql -u root -p
```

**Or install manually:**

```bash
sudo apt install mysql-server -y
sudo mysql_secure_installation
```

### Step 2.3: Install Redis

```bash
sudo apt install redis-server -y
sudo systemctl enable redis-server
sudo systemctl start redis-server

# Verify
redis-cli ping  # Should return PONG
```

### Step 2.4: Install PM2 (Process Manager)

```bash
npm install -g pm2
pm2 startup
# Follow the instructions to enable PM2 on boot
```

### Step 2.5: Install Git

```bash
sudo apt install git -y
git --version
```

---

## 3. Database Setup

### Step 3.1: Create Database

```bash
mysql -u root -p
```

```sql
-- Create database
CREATE DATABASE crickadmin CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Create database user
CREATE USER 'cricpro'@'localhost' IDENTIFIED BY 'your_strong_password_here';

-- Grant privileges
GRANT ALL PRIVILEGES ON crickadmin.* TO 'cricpro'@'localhost';
FLUSH PRIVILEGES;

-- Verify
SHOW DATABASES;
EXIT;
```

### Step 3.2: Import Database Schema

```bash
# If you have a schema file
mysql -u cricpro -p crickadmin < /path/to/schema.sql

# Or run migrations (if available)
cd /home/cricpro/cricket-api
npm run migrate
```

---

## 4. Backend API Deployment

### Step 4.1: Clone Repository

```bash
cd /home/cricpro
git clone https://github.com/yourusername/cricket-live.git
cd cricket-live/cricket-api
```

### Step 4.2: Install Dependencies

```bash
npm install --production
```

### Step 4.3: Configure Environment

```bash
nano .env
```

**Production .env configuration:**

```env
# ====================================================
# Cricket Scoring API — Production Configuration
# ====================================================

# Server
NODE_ENV=production
PORT=5000
HOST=0.0.0.0

# MySQL / Percona
DB_HOST=127.0.0.1
DB_PORT=3306
DB_USER=cricpro
DB_PASSWORD=your_strong_password_here
DB_NAME=crickadmin
DB_POOL_MIN=2
DB_POOL_MAX=20

# Redis
REDIS_URL=redis://localhost:6379
REDIS_PASSWORD=

# Auth - IMPORTANT: Generate strong random strings
JWT_SECRET=CHANGE_THIS_TO_A_VERY_LONG_RANDOM_STRING_AT_LEAST_64_CHARS
JWT_EXPIRES_IN=7d
API_KEY_HEADER=x-api-key

# Rate Limiting
RATE_LIMIT_MAX=100
RATE_LIMIT_WINDOW_MS=60000

# Admin Seed Credentials
ADMIN_SEED_EMAIL=admin@cricpro.local
ADMIN_SEED_PASSWORD=your_admin_password_here

# Provider: Cricbuzz
CRICBUZZ_BASE_URL=https://www.cricbuzz.com

# Provider: CricketData.org
CRICKETDATA_API_KEY=your_api_key_if_available
CRICKETDATA_BASE_URL=https://api.cricapi.com/v1

# Provider: ESPN Cricinfo
CRICINFO_BASE_URL=https://hs-consumer-api.espncricinfo.com/v1

# Polling Intervals (ms)
POLL_LIVE_INTERVAL=3000
POLL_INNINGS_BREAK_INTERVAL=15000
POLL_UPCOMING_INTERVAL=300000
POLL_COMMENTARY_INTERVAL=5000
POLL_SCORECARD_INTERVAL=10000

# Workers
WORKER_CONCURRENCY=5
WORKER_LIMITER_MAX=10
WORKER_LIMITER_DURATION=1000

# WebSocket
WS_HEARTBEAT_INTERVAL=30000
WS_MAX_CONNECTIONS=50000

# Monitoring
LOG_LEVEL=info
METRICS_ENABLED=true
METRICS_PORT=9090

# CORS - Update with your admin panel domain
CORS_ORIGIN=https://admin.yourdomain.com
```

**Generate strong JWT secret:**

```bash
node -e "console.log(require('crypto').randomBytes(64).toString('hex'))"
```

### Step 4.4: Seed Admin User

```bash
node src/admin/db/admin-seed.js
```

**Save the credentials shown in the output!**

### Step 4.5: Test Backend API

```bash
# Test run
node src/server.js

# Should see:
# Server listening on http://0.0.0.0:5000
# Redis connected
# MySQL connected

# Press Ctrl+C to stop
```

### Step 4.6: Setup PM2 for Backend

```bash
# Create PM2 ecosystem file
nano ecosystem.config.js
```

**ecosystem.config.js:**

```javascript
module.exports = {
  apps: [{
    name: 'cricket-api',
    script: './src/server.js',
    instances: 2,
    exec_mode: 'cluster',
    env: {
      NODE_ENV: 'production',
      PORT: 5000
    },
    error_file: './logs/err.log',
    out_file: './logs/out.log',
    log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
    merge_logs: true,
    autorestart: true,
    watch: false,
    max_memory_restart: '1G'
  }]
};
```

**Start with PM2:**

```bash
# Create logs directory
mkdir -p logs

# Start the API
pm2 start ecosystem.config.js

# Save PM2 configuration
pm2 save

# Check status
pm2 status
pm2 logs cricket-api
```

---

## 5. Admin Panel Deployment

### Step 5.1: Navigate to Admin Panel Directory

```bash
cd /home/cricpro/cricket-live/admin-panel
```

### Step 5.2: Install Dependencies

```bash
npm install
```

### Step 5.3: Configure Environment

```bash
nano .env.local
```

**Production .env.local:**

```env
NEXT_PUBLIC_API_BASE_URL=https://api.yourdomain.com
```

### Step 5.4: Build Admin Panel

```bash
npm run build

# This creates an optimized production build in .next/
```

### Step 5.5: Test Production Build

```bash
npm start
# Should start on port 3000
# Press Ctrl+C to stop
```

### Step 5.6: Setup PM2 for Admin Panel

```bash
nano ecosystem.config.js
```

**ecosystem.config.js:**

```javascript
module.exports = {
  apps: [{
    name: 'admin-panel',
    script: 'node_modules/next/dist/bin/next',
    args: 'start -p 3000',
    instances: 1,
    exec_mode: 'cluster',
    env: {
      NODE_ENV: 'production',
      PORT: 3000
    },
    error_file: './logs/err.log',
    out_file: './logs/out.log',
    log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
    merge_logs: true,
    autorestart: true,
    watch: false,
    max_memory_restart: '512M'
  }]
};
```

**Start with PM2:**

```bash
mkdir -p logs
pm2 start ecosystem.config.js
pm2 save
pm2 status
```

---

## 6. SSL Certificate Setup

### Option 1: Using CloudPanel (Recommended)

1. **Login to CloudPanel**: `https://your-vps-ip:8443`
2. **Add Site**:
   - Click "Sites" → "Add Site"
   - Domain: `api.yourdomain.com`
   - Type: "Node.js"
   - Port: 5000
3. **Add SSL**:
   - Click on the site → "SSL/TLS"
   - Select "Let's Encrypt"
   - Click "Install"
4. **Repeat for Admin Panel**:
   - Domain: `admin.yourdomain.com`
   - Port: 3000

### Option 2: Manual Certbot Setup

```bash
# Install Certbot
sudo apt install certbot python3-certbot-nginx -y

# Get certificates
sudo certbot --nginx -d api.yourdomain.com
sudo certbot --nginx -d admin.yourdomain.com

# Auto-renewal
sudo certbot renew --dry-run
```

---

## 7. Nginx Configuration

### Step 7.1: Backend API Nginx Config

```bash
sudo nano /etc/nginx/sites-available/api.yourdomain.com
```

**api.yourdomain.com.conf:**

```nginx
upstream cricket_api {
    server 127.0.0.1:5000;
    keepalive 64;
}

server {
    listen 80;
    listen [::]:80;
    server_name api.yourdomain.com;
    
    # Redirect to HTTPS
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name api.yourdomain.com;

    # SSL Configuration
    ssl_certificate /etc/letsencrypt/live/api.yourdomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/api.yourdomain.com/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    # Security Headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

    # Logging
    access_log /var/log/nginx/api.yourdomain.com.access.log;
    error_log /var/log/nginx/api.yourdomain.com.error.log;

    # Client body size
    client_max_body_size 10M;

    # Proxy settings
    location / {
        proxy_pass http://cricket_api;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
        proxy_read_timeout 300s;
        proxy_connect_timeout 75s;
    }

    # WebSocket support
    location /ws {
        proxy_pass http://cricket_api;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 86400;
    }
}
```

### Step 7.2: Admin Panel Nginx Config

```bash
sudo nano /etc/nginx/sites-available/admin.yourdomain.com
```

**admin.yourdomain.com.conf:**

```nginx
upstream admin_panel {
    server 127.0.0.1:3000;
    keepalive 64;
}

server {
    listen 80;
    listen [::]:80;
    server_name admin.yourdomain.com;
    
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name admin.yourdomain.com;

    # SSL Configuration
    ssl_certificate /etc/letsencrypt/live/admin.yourdomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/admin.yourdomain.com/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    # Security Headers
    add_header X-Frame-Options "DENY" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header Content-Security-Policy "default-src 'self' https:; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline';" always;

    # Logging
    access_log /var/log/nginx/admin.yourdomain.com.access.log;
    error_log /var/log/nginx/admin.yourdomain.com.error.log;

    # Next.js static files
    location /_next/static {
        proxy_pass http://admin_panel;
        proxy_cache_valid 200 60m;
        add_header Cache-Control "public, immutable";
    }

    # Proxy to Next.js
    location / {
        proxy_pass http://admin_panel;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
        proxy_read_timeout 300s;
    }
}
```

### Step 7.3: Enable Sites and Restart Nginx

```bash
# Enable sites
sudo ln -s /etc/nginx/sites-available/api.yourdomain.com /etc/nginx/sites-enabled/
sudo ln -s /etc/nginx/sites-available/admin.yourdomain.com /etc/nginx/sites-enabled/

# Test configuration
sudo nginx -t

# Restart Nginx
sudo systemctl restart nginx
```

---

## 8. Security Hardening

### Step 8.1: Configure Firewall (UFW)

```bash
# Enable UFW
sudo ufw enable

# Allow SSH
sudo ufw allow 22/tcp

# Allow HTTP/HTTPS
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# Allow CloudPanel
sudo ufw allow 8443/tcp

# Check status
sudo ufw status
```

### Step 8.2: Secure MySQL

```bash
# Run security script
sudo mysql_secure_installation

# Disable remote root login
mysql -u root -p
```

```sql
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
FLUSH PRIVILEGES;
EXIT;
```

### Step 8.3: Secure Redis

```bash
sudo nano /etc/redis/redis.conf
```

**Update these settings:**

```conf
# Bind to localhost only
bind 127.0.0.1 ::1

# Require password
requirepass your_redis_password_here

# Disable dangerous commands
rename-command FLUSHDB ""
rename-command FLUSHALL ""
rename-command CONFIG ""
```

**Restart Redis:**

```bash
sudo systemctl restart redis-server
```

**Update .env with Redis password:**

```env
REDIS_URL=redis://:your_redis_password_here@localhost:6379
```

### Step 8.4: Setup Fail2Ban

```bash
# Install Fail2Ban
sudo apt install fail2ban -y

# Create custom jail
sudo nano /etc/fail2ban/jail.local
```

**jail.local:**

```ini
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true
port = 22

[nginx-http-auth]
enabled = true
port = http,https

[nginx-noscript]
enabled = true
port = http,https

[nginx-badbots]
enabled = true
port = http,https
```

**Start Fail2Ban:**

```bash
sudo systemctl enable fail2ban
sudo systemctl start fail2ban
sudo fail2ban-client status
```

### Step 8.5: Regular Security Updates

```bash
# Enable automatic security updates
sudo apt install unattended-upgrades -y
sudo dpkg-reconfigure -plow unattended-upgrades
```

---

## 9. Process Management with PM2

### PM2 Commands

```bash
# View all processes
pm2 list

# View logs
pm2 logs cricket-api
pm2 logs admin-panel

# Restart services
pm2 restart cricket-api
pm2 restart admin-panel

# Stop services
pm2 stop cricket-api
pm2 stop admin-panel

# Monitor resources
pm2 monit

# View detailed info
pm2 info cricket-api

# Flush logs
pm2 flush

# Reload (zero-downtime)
pm2 reload cricket-api
```

### PM2 Monitoring

```bash
# Install PM2 monitoring (optional)
pm2 install pm2-logrotate

# Configure log rotation
pm2 set pm2-logrotate:max_size 10M
pm2 set pm2-logrotate:retain 7
```

---

## 10. Monitoring & Maintenance

### Step 10.1: Setup Log Rotation

```bash
sudo nano /etc/logrotate.d/cricket-api
```

**cricket-api logrotate config:**

```
/home/cricpro/cricket-live/cricket-api/logs/*.log {
    daily
    rotate 14
    compress
    delaycompress
    notifempty
    create 0640 cricpro cricpro
    sharedscripts
    postrotate
        pm2 reloadLogs
    endscript
}
```

### Step 10.2: Database Backup Script

```bash
nano /home/cricpro/backup-db.sh
```

**backup-db.sh:**

```bash
#!/bin/bash

# Configuration
DB_NAME="crickadmin"
DB_USER="cricpro"
DB_PASS="your_password"
BACKUP_DIR="/home/cricpro/backups"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/crickadmin_$DATE.sql.gz"

# Create backup directory
mkdir -p $BACKUP_DIR

# Dump database
mysqldump -u $DB_USER -p$DB_PASS $DB_NAME | gzip > $BACKUP_FILE

# Keep only last 7 days
find $BACKUP_DIR -name "crickadmin_*.sql.gz" -mtime +7 -delete

echo "Backup completed: $BACKUP_FILE"
```

**Make executable and schedule:**

```bash
chmod +x /home/cricpro/backup-db.sh

# Add to crontab
crontab -e

# Add this line (daily at 2 AM)
0 2 * * * /home/cricpro/backup-db.sh >> /home/cricpro/backup.log 2>&1
```

### Step 10.3: Health Check Script

```bash
nano /home/cricpro/health-check.sh
```

**health-check.sh:**

```bash
#!/bin/bash

# Check API
API_STATUS=$(curl -s -o /dev/null -w "%{http_code}" https://api.yourdomain.com/health)
if [ $API_STATUS -ne 200 ]; then
    echo "API is down! Status: $API_STATUS"
    pm2 restart cricket-api
fi

# Check Admin Panel
ADMIN_STATUS=$(curl -s -o /dev/null -w "%{http_code}" https://admin.yourdomain.com)
if [ $ADMIN_STATUS -ne 200 ]; then
    echo "Admin Panel is down! Status: $ADMIN_STATUS"
    pm2 restart admin-panel
fi

# Check Redis
redis-cli ping > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "Redis is down!"
    sudo systemctl restart redis-server
fi

# Check MySQL
mysqladmin -u cricpro -pyour_password ping > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "MySQL is down!"
    sudo systemctl restart mysql
fi
```

**Schedule health checks:**

```bash
chmod +x /home/cricpro/health-check.sh

# Add to crontab (every 5 minutes)
crontab -e

# Add this line
*/5 * * * * /home/cricpro/health-check.sh >> /home/cricpro/health-check.log 2>&1
```

### Step 10.4: Monitoring Tools

**Install htop:**

```bash
sudo apt install htop -y
htop
```

**Install netdata (optional):**

```bash
bash <(curl -Ss https://my-netdata.io/kickstart.sh)
# Access at: http://your-vps-ip:19999
```

---

## 11. Deployment Checklist

### Pre-Deployment

- [ ] VPS provisioned with CloudPanel
- [ ] Domain DNS configured (A records pointing to VPS IP)
- [ ] SSH access configured
- [ ] Non-root user created

### Installation

- [ ] Node.js installed (v18+)
- [ ] MySQL installed and secured
- [ ] Redis installed and secured
- [ ] PM2 installed globally
- [ ] Git installed

### Database

- [ ] Database created
- [ ] Database user created with proper privileges
- [ ] Schema imported/migrations run
- [ ] Admin user seeded

### Backend API

- [ ] Repository cloned
- [ ] Dependencies installed
- [ ] .env configured with production values
- [ ] JWT secret generated
- [ ] PM2 ecosystem configured
- [ ] API started with PM2
- [ ] API accessible on port 5000

### Admin Panel

- [ ] Dependencies installed
- [ ] .env.local configured
- [ ] Production build created
- [ ] PM2 ecosystem configured
- [ ] Panel started with PM2
- [ ] Panel accessible on port 3000

### Web Server

- [ ] Nginx configurations created
- [ ] SSL certificates installed
- [ ] Sites enabled
- [ ] Nginx restarted
- [ ] HTTPS working for both domains

### Security

- [ ] Firewall configured
- [ ] MySQL secured
- [ ] Redis password set
- [ ] Fail2Ban configured
- [ ] Security headers added
- [ ] Automatic updates enabled

### Monitoring

- [ ] PM2 monitoring setup
- [ ] Log rotation configured
- [ ] Database backup script created
- [ ] Health check script created
- [ ] Cron jobs scheduled

### Testing

- [ ] API health endpoint responding
- [ ] Admin panel loads
- [ ] Login works
- [ ] All pages accessible
- [ ] CRUD operations work
- [ ] WebSocket connections work
- [ ] SSL certificates valid

---

## 12. Post-Deployment

### Update DNS Records

```
Type    Name    Value               TTL
A       api     your-vps-ip         3600
A       admin   your-vps-ip         3600
```

### Test Everything

```bash
# Test API
curl https://api.yourdomain.com/health

# Test Admin Panel
curl https://admin.yourdomain.com

# Check SSL
curl -I https://api.yourdomain.com
curl -I https://admin.yourdomain.com
```

### Login to Admin Panel

1. Open: `https://admin.yourdomain.com`
2. Login with:
   - Email: `admin@cricpro.local`
   - Password: (from seed script output)
3. Test all pages and features

---

## 13. Updating the Application

### Update Backend API

```bash
cd /home/cricpro/cricket-live/cricket-api
git pull origin main
npm install --production
pm2 restart cricket-api
pm2 logs cricket-api
```

### Update Admin Panel

```bash
cd /home/cricpro/cricket-live/admin-panel
git pull origin main
npm install
npm run build
pm2 restart admin-panel
pm2 logs admin-panel
```

---

## 14. Troubleshooting

### API Not Starting

```bash
# Check logs
pm2 logs cricket-api

# Check if port is in use
sudo lsof -i :5000

# Check Redis
redis-cli ping

# Check MySQL
mysql -u cricpro -p crickadmin -e "SELECT 1;"
```

### Admin Panel Not Loading

```bash
# Check logs
pm2 logs admin-panel

# Check build
cd /home/cricpro/cricket-live/admin-panel
npm run build

# Check if port is in use
sudo lsof -i :3000
```

### SSL Issues

```bash
# Renew certificates
sudo certbot renew

# Check certificate expiry
sudo certbot certificates
```

### Database Connection Issues

```bash
# Check MySQL status
sudo systemctl status mysql

# Check connection
mysql -u cricpro -p crickadmin

# Check .env credentials
cat /home/cricpro/cricket-live/cricket-api/.env | grep DB_
```

---

## 15. Support & Resources

### Useful Commands

```bash
# View all PM2 processes
pm2 list

# View system resources
htop

# View disk usage
df -h

# View memory usage
free -h

# View Nginx logs
sudo tail -f /var/log/nginx/access.log
sudo tail -f /var/log/nginx/error.log

# View application logs
pm2 logs

# Restart all services
pm2 restart all
sudo systemctl restart nginx
sudo systemctl restart mysql
sudo systemctl restart redis-server
```

### CloudPanel Resources

- Documentation: https://www.cloudpanel.io/docs/
- Community: https://community.cloudpanel.io/

---

## Summary

Your CricPro Admin Panel is now deployed on CloudPanel VPS with:

✅ **Backend API**: `https://api.yourdomain.com`
✅ **Admin Panel**: `https://admin.yourdomain.com`
✅ **SSL Certificates**: Auto-renewing Let's Encrypt
✅ **Process Management**: PM2 with auto-restart
✅ **Security**: Firewall, Fail2Ban, secured services
✅ **Monitoring**: Health checks, backups, log rotation
✅ **High Availability**: Nginx reverse proxy, clustered Node.js

**Next Steps:**
1. Test all functionality
2. Set up monitoring alerts
3. Configure backup retention
4. Document your specific configurations
5. Train your team on the admin panel

**Production Ready!** 🚀
