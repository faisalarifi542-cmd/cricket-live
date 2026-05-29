# CricPro Admin Panel - Single Domain Deployment Guide

## Overview

This guide shows you how to run both the Backend API and Admin Panel on the **same VPS** using a **single domain** with different paths.

### Setup Options

You have **3 options** for deploying on the same VPS:

---

## Option 1: Single Domain with Paths (Recommended) ⭐

**Domain Structure:**
- Admin Panel: `https://yourdomain.com/admin`
- Backend API: `https://yourdomain.com/api`
- Main App: `https://yourdomain.com/` (optional)

**Advantages:**
- ✅ Only need 1 domain
- ✅ Easier SSL management
- ✅ Simpler DNS setup
- ✅ Better for SEO
- ✅ Shared SSL certificate

**Disadvantages:**
- ⚠️ Requires path-based routing
- ⚠️ Slightly more complex Nginx config

---

## Option 2: Subdomains on Same Domain

**Domain Structure:**
- Admin Panel: `https://admin.yourdomain.com`
- Backend API: `https://api.yourdomain.com`

**Advantages:**
- ✅ Clean separation
- ✅ Easier to configure
- ✅ Independent SSL certs
- ✅ Better for microservices

**Disadvantages:**
- ⚠️ Need to configure 2 subdomains
- ⚠️ 2 SSL certificates

---

## Option 3: Different Ports (Development Only)

**Domain Structure:**
- Admin Panel: `https://yourdomain.com:3000`
- Backend API: `https://yourdomain.com:5000`

**Not recommended for production!**

---

# Detailed Setup: Option 1 (Single Domain with Paths)

## Architecture

```
Internet
    ↓
https://yourdomain.com
    ↓
Nginx (Port 80/443)
    ↓
    ├─→ /admin/* → Admin Panel (Port 3000)
    ├─→ /api/*   → Backend API (Port 5000)
    └─→ /*       → Main Website (optional)
```

---

## Step-by-Step Configuration

### 1. Update Environment Variables

#### Backend API (.env)

```bash
cd /home/cricpro/cricket-live/cricket-api
nano .env
```

**Update these values:**

```env
# Server
NODE_ENV=production
PORT=5000
HOST=127.0.0.1  # Only listen on localhost

# CORS - Allow admin panel on same domain
CORS_ORIGIN=https://yourdomain.com

# Other settings remain the same...
```

#### Admin Panel (.env.local)

```bash
cd /home/cricpro/cricket-live/admin-panel
nano .env.local
```

**Update to use same domain:**

```env
NEXT_PUBLIC_API_BASE_URL=https://yourdomain.com/api
```

### 2. Configure Next.js for Path-Based Routing

```bash
cd /home/cricpro/cricket-live/admin-panel
nano next.config.mjs
```

**Update next.config.mjs:**

```javascript
/** @type {import('next').NextConfig} */
const nextConfig = {
  // Add basePath for admin panel
  basePath: '/admin',
  
  // Asset prefix for static files
  assetPrefix: '/admin',
  
  // Other existing config...
  reactStrictMode: true,
  swcMinify: true,
};

export default nextConfig;
```

**Rebuild the admin panel:**

```bash
npm run build
```

### 3. Configure Nginx (Single Domain)

```bash
sudo nano /etc/nginx/sites-available/yourdomain.com
```

**Complete Nginx Configuration:**

```nginx
# Upstream definitions
upstream cricket_api {
    server 127.0.0.1:5000;
    keepalive 64;
}

upstream admin_panel {
    server 127.0.0.1:3000;
    keepalive 64;
}

# HTTP to HTTPS redirect
server {
    listen 80;
    listen [::]:80;
    server_name yourdomain.com www.yourdomain.com;
    
    return 301 https://$server_name$request_uri;
}

# Main HTTPS server
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name yourdomain.com www.yourdomain.com;

    # SSL Configuration
    ssl_certificate /etc/letsencrypt/live/yourdomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/yourdomain.com/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    # Security Headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

    # Logging
    access_log /var/log/nginx/yourdomain.com.access.log;
    error_log /var/log/nginx/yourdomain.com.error.log;

    # Client body size
    client_max_body_size 10M;

    # ============================================
    # Backend API Routes (/api/*)
    # ============================================
    location /api/ {
        # Remove /api prefix before proxying
        rewrite ^/api/(.*) /$1 break;
        
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

    # WebSocket support for API
    location /api/ws {
        rewrite ^/api/(.*) /$1 break;
        
        proxy_pass http://cricket_api;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 86400;
    }

    # ============================================
    # Admin Panel Routes (/admin/*)
    # ============================================
    
    # Next.js static files
    location /admin/_next/static {
        proxy_pass http://admin_panel;
        proxy_cache_valid 200 60m;
        add_header Cache-Control "public, immutable";
    }

    # Admin panel routes
    location /admin {
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

    # ============================================
    # Main Website (Optional)
    # ============================================
    location / {
        # Serve your main website here
        # Or redirect to admin panel
        return 301 https://$server_name/admin;
        
        # Or serve static files
        # root /var/www/yourdomain.com;
        # index index.html;
    }
}
```

### 4. Enable Site and Get SSL Certificate

```bash
# Enable the site
sudo ln -s /etc/nginx/sites-available/yourdomain.com /etc/nginx/sites-enabled/

# Test Nginx configuration
sudo nginx -t

# Get SSL certificate
sudo certbot --nginx -d yourdomain.com -d www.yourdomain.com

# Restart Nginx
sudo systemctl restart nginx
```

### 5. Update PM2 Configuration

The PM2 configuration remains the same since both services run on localhost:

```bash
# Backend API (Port 5000)
pm2 start /home/cricpro/cricket-live/cricket-api/src/server.js --name cricket-api

# Admin Panel (Port 3000)
cd /home/cricpro/cricket-live/admin-panel
pm2 start npm --name admin-panel -- start

# Save configuration
pm2 save
```

### 6. Update CORS in Backend

```bash
cd /home/cricpro/cricket-live/cricket-api
nano src/server.js
```

**Find the CORS configuration and update:**

```javascript
// CORS configuration
fastify.register(cors, {
  origin: [
    'https://yourdomain.com',
    'https://www.yourdomain.com',
    process.env.CORS_ORIGIN
  ].filter(Boolean),
  credentials: true,
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'OPTIONS']
});
```

**Restart the API:**

```bash
pm2 restart cricket-api
```

---

## Testing the Setup

### 1. Test Backend API

```bash
# Health check
curl https://yourdomain.com/api/health

# Should return API health status
```

### 2. Test Admin Panel

```bash
# Access admin panel
curl https://yourdomain.com/admin

# Should return HTML
```

### 3. Test in Browser

1. **Open Admin Panel**: `https://yourdomain.com/admin`
2. **Login** with your credentials
3. **Check Network Tab**: API calls should go to `https://yourdomain.com/api/*`
4. **Test CRUD operations**: Create, edit, delete items

---

## Alternative: Option 2 (Subdomains)

If you prefer subdomains, here's the simpler configuration:

### DNS Configuration

Add these A records:

```
Type    Name    Value           TTL
A       @       your-vps-ip     3600
A       admin   your-vps-ip     3600
A       api     your-vps-ip     3600
```

### Environment Variables

**Backend API (.env):**
```env
CORS_ORIGIN=https://admin.yourdomain.com
```

**Admin Panel (.env.local):**
```env
NEXT_PUBLIC_API_BASE_URL=https://api.yourdomain.com
```

### Nginx Configuration (Separate Files)

**For API (api.yourdomain.com):**

```bash
sudo nano /etc/nginx/sites-available/api.yourdomain.com
```

```nginx
upstream cricket_api {
    server 127.0.0.1:5000;
    keepalive 64;
}

server {
    listen 80;
    server_name api.yourdomain.com;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name api.yourdomain.com;

    ssl_certificate /etc/letsencrypt/live/api.yourdomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/api.yourdomain.com/privkey.pem;

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
    }
}
```

**For Admin Panel (admin.yourdomain.com):**

```bash
sudo nano /etc/nginx/sites-available/admin.yourdomain.com
```

```nginx
upstream admin_panel {
    server 127.0.0.1:3000;
    keepalive 64;
}

server {
    listen 80;
    server_name admin.yourdomain.com;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name admin.yourdomain.com;

    ssl_certificate /etc/letsencrypt/live/admin.yourdomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/admin.yourdomain.com/privkey.pem;

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
    }
}
```

**Enable and get SSL:**

```bash
sudo ln -s /etc/nginx/sites-available/api.yourdomain.com /etc/nginx/sites-enabled/
sudo ln -s /etc/nginx/sites-available/admin.yourdomain.com /etc/nginx/sites-enabled/

sudo certbot --nginx -d api.yourdomain.com
sudo certbot --nginx -d admin.yourdomain.com

sudo nginx -t
sudo systemctl restart nginx
```

---

## Comparison Table

| Feature | Single Domain + Paths | Subdomains | Different Ports |
|---------|----------------------|------------|-----------------|
| **Domains Needed** | 1 | 1 (with subdomains) | 1 |
| **SSL Certificates** | 1 | 2 | 1 |
| **DNS Records** | 1 A record | 3 A records | 1 A record |
| **Nginx Complexity** | Medium | Simple | Simple |
| **URL Structure** | `/admin`, `/api` | `admin.`, `api.` | `:3000`, `:5000` |
| **Production Ready** | ✅ Yes | ✅ Yes | ❌ No |
| **SEO Friendly** | ✅ Yes | ⚠️ Neutral | ❌ No |
| **Ease of Setup** | ⚠️ Medium | ✅ Easy | ✅ Easy |
| **Recommended** | ⭐ Yes | ⭐ Yes | ❌ Dev only |

---

## Troubleshooting

### Issue: 404 on /admin routes

**Solution:**
```bash
# Check Next.js basePath is set
cat admin-panel/next.config.mjs | grep basePath

# Rebuild admin panel
cd admin-panel
npm run build
pm2 restart admin-panel
```

### Issue: API calls failing

**Solution:**
```bash
# Check CORS settings
cat cricket-api/.env | grep CORS

# Check Nginx rewrite rules
sudo nginx -t
sudo tail -f /var/log/nginx/error.log
```

### Issue: SSL certificate errors

**Solution:**
```bash
# Renew certificates
sudo certbot renew

# Check certificate
sudo certbot certificates
```

### Issue: 502 Bad Gateway

**Solution:**
```bash
# Check if services are running
pm2 status

# Check if ports are listening
sudo lsof -i :5000
sudo lsof -i :3000

# Restart services
pm2 restart all
```

---

## Recommended Setup

For most use cases, I recommend **Option 2 (Subdomains)** because:

1. ✅ **Simpler configuration** - Less complex Nginx setup
2. ✅ **Cleaner URLs** - `admin.yourdomain.com` vs `yourdomain.com/admin`
3. ✅ **Better separation** - API and Admin are independent
4. ✅ **Easier debugging** - Separate logs and SSL certs
5. ✅ **More flexible** - Can move to different servers later

However, if you only have **one domain** and don't want to configure subdomains, **Option 1 (Single Domain + Paths)** works perfectly fine!

---

## Summary

✅ **Yes, you can run both on the same VPS and same domain!**

**Best Options:**
1. **Subdomains** (Recommended): `admin.yourdomain.com` + `api.yourdomain.com`
2. **Path-based**: `yourdomain.com/admin` + `yourdomain.com/api`

**Both services run on:**
- Same VPS
- Same Nginx instance
- Different ports (3000 and 5000)
- Proxied through Nginx
- Single SSL certificate (Option 1) or separate certs (Option 2)

Choose the option that best fits your needs! 🚀
