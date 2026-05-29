# 📋 Deployment Checklist

Use this checklist to ensure all files are properly deployed to your VPS.

---

## 🎯 Backend API (api.webcrichd.co)

### Files to Upload:
- [ ] `src/` - All source code
- [ ] `migrations/` - Database schema files
- [ ] `admin/` - Admin routes and middleware
- [ ] `nginx/` - Nginx configuration (if needed)
- [ ] `.env` - Environment variables (configure for production)
- [ ] `package.json` - Dependencies
- [ ] `package-lock.json` - Locked dependencies

### Setup Commands:
```bash
cd ~/htdocs/api.webcrichd.co

# Install dependencies
npm install

# Import database schema
mysql -u your_db_user -p webcrichdapi < migrations/admin-panel-schema.sql

# Run seed script
node src/admin/db/admin-seed.js

# Start API
pm2 start src/server.js --name "cricket-api"
pm2 save
```

### Verify:
- [ ] API responds at https://api.webcrichd.co/health
- [ ] Database tables created (15 tables)
- [ ] Admin user created
- [ ] PM2 process running

---

## 🎨 Admin Panel (app.webcrichd.co or admin.webcrichd.co)

### Files to Upload:
- [ ] `app/` - **CRITICAL** - All page components
- [ ] `components/` - Reusable components
- [ ] `lib/` - Utility functions
- [ ] `types/` - TypeScript types
- [ ] `.env.local` - Environment variables
- [ ] `next.config.mjs` - Next.js config
- [ ] `package.json` - Dependencies
- [ ] `package-lock.json` - Locked dependencies
- [ ] `tsconfig.json` - TypeScript config
- [ ] `tailwind.config.ts` - Tailwind config
- [ ] `postcss.config.mjs` - PostCSS config

### Setup Commands:
```bash
cd ~/htdocs/app.webcrichd.co

# Install dependencies
npm install

# Build application
npm run build

# Start application
pm2 start npm --name "admin-panel" -- start
pm2 save
```

### Verify:
- [ ] Build completes without errors
- [ ] Admin panel accessible at https://app.webcrichd.co or https://admin.webcrichd.co
- [ ] Login page loads
- [ ] Can login with admin credentials
- [ ] PM2 process running

---

## 🔐 Environment Variables

### Backend API (.env):
```bash
# Server
NODE_ENV=production
PORT=5000
API_BASE_URL=https://api.webcrichd.co

# Database
DB_HOST=127.0.0.1
DB_PORT=3306
DB_USER=your_db_user
DB_PASSWORD=your_db_password
DB_NAME=webcrichdapi

# JWT
JWT_SECRET=your-super-secret-jwt-key-change-this
JWT_EXPIRES_IN=1h
REFRESH_TOKEN_SECRET=your-super-secret-refresh-token-key
REFRESH_TOKEN_EXPIRES_IN=7d

# Admin
ADMIN_SEED_PASSWORD=your-secure-admin-password

# Redis (if using)
REDIS_HOST=127.0.0.1
REDIS_PORT=6379

# Logging
LOG_LEVEL=info
```

### Admin Panel (.env.local):
```bash
NEXT_PUBLIC_API_BASE_URL=https://api.webcrichd.co
```

---

## 🌐 Nginx Configuration

### For Subdomain Setup (Recommended):

**API (api.webcrichd.co):**
```nginx
server {
    listen 80;
    server_name api.webcrichd.co;
    
    location / {
        proxy_pass http://localhost:5000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

**Admin Panel (admin.webcrichd.co):**
```nginx
server {
    listen 80;
    server_name admin.webcrichd.co;
    
    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }
}
```

---

## 🔍 Verification Steps

### 1. Database Check:
```bash
mysql -u your_db_user -p webcrichdapi -e "SHOW TABLES;"
```

Expected: 15 tables listed

### 2. API Health Check:
```bash
curl https://api.webcrichd.co/health
```

Expected: `{"status":"ok"}`

### 3. Admin Panel Check:
```bash
curl -I https://admin.webcrichd.co
```

Expected: `200 OK`

### 4. PM2 Processes:
```bash
pm2 list
```

Expected: Both `cricket-api` and `admin-panel` running

### 5. Login Test:
- Visit https://admin.webcrichd.co/login
- Enter credentials
- Should redirect to dashboard

---

## 🚨 Common Issues

### Issue: "Table doesn't exist"
**Fix:** Import database schema
```bash
cd ~/htdocs/api.webcrichd.co
mysql -u your_db_user -p webcrichdapi < migrations/admin-panel-schema.sql
```

### Issue: "Couldn't find pages directory"
**Fix:** Upload the `app` directory
```bash
cd ~/htdocs/app.webcrichd.co
ls -la app/  # Should show all page directories
```

### Issue: "Cannot connect to API"
**Fix:** Check `.env.local` in admin panel
```bash
cat ~/htdocs/app.webcrichd.co/.env.local
# Should show: NEXT_PUBLIC_API_BASE_URL=https://api.webcrichd.co
```

### Issue: "502 Bad Gateway"
**Fix:** Check if processes are running
```bash
pm2 list
pm2 logs cricket-api
pm2 logs admin-panel
```

### Issue: "Permission denied"
**Fix:** Set correct ownership
```bash
sudo chown -R webcrichd-api:webcrichd-api ~/htdocs/api.webcrichd.co
sudo chown -R webcrichd-app:webcrichd-app ~/htdocs/app.webcrichd.co
```

---

## 📦 File Upload Methods

### Method 1: SFTP (FileZilla, WinSCP)
1. Connect to server
2. Navigate to `~/htdocs/`
3. Upload folders
4. Verify all files uploaded

### Method 2: rsync (Recommended)
```bash
# From local machine - API
rsync -avz --exclude 'node_modules' --exclude '.env' cricket-api/* user@server:~/htdocs/api.webcrichd.co/

# From local machine - Admin Panel
rsync -avz --exclude 'node_modules' --exclude '.next' admin-panel/* user@server:~/htdocs/app.webcrichd.co/
```

### Method 3: Git (Best for updates)
```bash
# On server
cd ~/htdocs/api.webcrichd.co
git pull origin main
npm install
pm2 restart cricket-api

cd ~/htdocs/app.webcrichd.co
git pull origin main
npm install
npm run build
pm2 restart admin-panel
```

---

## ✅ Final Checklist

Before going live:

- [ ] All files uploaded to server
- [ ] Database schema imported
- [ ] Admin user created (seed script run)
- [ ] Environment variables configured
- [ ] Dependencies installed (npm install)
- [ ] Admin panel built (npm run build)
- [ ] Both processes running in PM2
- [ ] Nginx configured and reloaded
- [ ] SSL certificates installed
- [ ] API health check passes
- [ ] Admin panel accessible
- [ ] Can login to admin panel
- [ ] All pages load without errors
- [ ] PM2 startup configured
- [ ] Firewall configured
- [ ] Backups configured

---

## 🎉 Success Criteria

Your deployment is successful when:

1. ✅ API responds at https://api.webcrichd.co/health
2. ✅ Admin panel loads at https://admin.webcrichd.co
3. ✅ Can login with admin credentials
4. ✅ Dashboard shows data
5. ✅ All menu items work
6. ✅ Can create/edit/delete records
7. ✅ PM2 shows both processes running
8. ✅ Logs show no errors

---

## 📞 Quick Reference

**Start services:**
```bash
pm2 start all
```

**Stop services:**
```bash
pm2 stop all
```

**Restart services:**
```bash
pm2 restart all
```

**View logs:**
```bash
pm2 logs
```

**Check status:**
```bash
pm2 status
```

**Save PM2 config:**
```bash
pm2 save
```

---

That's it! Follow this checklist step by step and your deployment will be successful. 🚀
