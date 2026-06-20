# CricPro Admin Panel - Production Deployment Package

## 📦 Package Contents

This zip file contains everything you need to deploy the CricPro Admin Panel to your server.

### Included Files:
- ✅ **admin-panel/** - Next.js frontend application
- ✅ **cricket-api/** - Node.js backend API
- ✅ **admin/** - Admin authentication and RBAC system
- ✅ **Documentation** - Complete deployment guides

### Excluded (will be installed on server):
- ❌ node_modules (install with `npm install`)
- ❌ .next build folder (create with `npm run build`)
- ❌ Log files

---

## 🚀 Quick Start

### 1. Extract Files on Server
```bash
# Upload zip to server
scp cricket-live-production-ready.zip user@your-server:/home/cricpro/

# SSH into server
ssh user@your-server

# Extract
cd /home/cricpro
unzip cricket-live-production-ready.zip
```

### 2. Install Dependencies

**Backend API:**
```bash
cd cricket-api
npm install --production
```

**Admin Panel:**
```bash
cd admin-panel
npm install
```

### 3. Configure Environment

**Backend (.env):**
```bash
cd cricket-api
nano .env
```

Update these values:
- `DB_USER`, `DB_PASSWORD`, `DB_NAME`
- `JWT_SECRET` (generate with: `node -e "console.log(require('crypto').randomBytes(64).toString('hex'))"`)
- `ADMIN_SEED_EMAIL`, `ADMIN_SEED_PASSWORD`
- `CORS_ORIGIN` (your admin panel URL)

**Frontend (.env.local):**
```bash
cd admin-panel
nano .env.local
```

Update:
- `NEXT_PUBLIC_API_BASE_URL=https://api.yourdomain.com`

### 4. Setup Database
```bash
# Create database
mysql -u root -p -e "CREATE DATABASE crickadmin;"

# Seed admin user
cd cricket-api
node src/admin/db/admin-seed.js
```

### 5. Build Admin Panel
```bash
cd admin-panel
npm run build
```

### 6. Start Services with PM2
```bash
# Backend API
cd cricket-api
pm2 start src/server.js --name cricket-api

# Admin Panel
cd admin-panel
pm2 start npm --name admin-panel -- start

# Save PM2 configuration
pm2 save
```

---

## 📚 Documentation Files Included

1. **CLOUDPANEL_VPS_DEPLOYMENT.md** - Complete VPS deployment guide
2. **SETUP_INSTRUCTIONS.md** - Local development setup
3. **QUICK_REFERENCE.md** - Command reference
4. **IMPLEMENTATION_SUMMARY.md** - What was implemented
5. **VERIFICATION_CHECKLIST.md** - Testing checklist

---

## 🔐 Default Credentials

**Email:** `admin@cricpro.local`
**Password:** Set in `.env` or check seed script output

---

## 🌐 Access URLs

- **API:** https://api.yourdomain.com
- **Admin Panel:** https://admin.yourdomain.com

---

## ✅ Deployment Checklist

- [ ] Files extracted to server
- [ ] Dependencies installed
- [ ] Environment configured
- [ ] Database created and seeded
- [ ] Frontend built
- [ ] PM2 processes started
- [ ] Nginx configured
- [ ] SSL certificates installed

---

**Ready to deploy! Follow the steps above and refer to the documentation for detailed instructions.** 🚀
