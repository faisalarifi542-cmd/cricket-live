# 🔧 Current Issues & Fixes

## Overview

You're encountering two issues during deployment. Both are easy to fix!

---

## ❌ Issue #1: Database Tables Missing

### Error Message:
```
Error: Table 'webcrichdapi.admin_roles' doesn't exist
```

### What Happened:
The seed script tried to insert data, but the database tables haven't been created yet.

### ✅ Fix:
```bash
cd ~/htdocs/api.webcrichd.co
mysql -u webcrichd_api -p webcrichdapi < migrations/admin-panel-schema.sql
node src/admin/db/admin-seed.js
```

### Detailed Guide:
📄 See **START_HERE.md** for step-by-step instructions

---

## ❌ Issue #2: Admin Panel Build Failing

### Error Message:
```
Error: > Couldn't find a `pages` directory. Please create one under the project root
```

### What Happened:
The `app` directory (which contains all the page components) wasn't uploaded to the server. Next.js can't find the pages to build.

### ✅ Fix:
Upload the entire `admin-panel` folder structure, especially the `app` directory.

**Quick verification:**
```bash
cd ~/htdocs/app.webcrichd.co
ls -la app/
```

You should see directories like:
- dashboard/
- login/
- matches/
- homepage/
- news/
- etc.

If the `app` directory is missing or empty, re-upload it from your local project.

### Detailed Guide:
📄 See **FIX_ADMIN_PANEL_BUILD.md** for complete instructions

---

## 🎯 Quick Fix Summary

### For Backend API:
```bash
# 1. Navigate to API directory
cd ~/htdocs/api.webcrichd.co

# 2. Import database schema
mysql -u webcrichd_api -p webcrichdapi < migrations/admin-panel-schema.sql

# 3. Run seed script
node src/admin/db/admin-seed.js

# 4. Save the admin password shown in output!
```

### For Admin Panel:
```bash
# 1. Verify app directory exists
cd ~/htdocs/app.webcrichd.co
ls -la app/

# 2. If missing, re-upload the entire admin-panel folder

# 3. Install dependencies
npm install

# 4. Build
npm run build

# 5. Start
pm2 start npm --name "admin-panel" -- start
```

---

## 📚 Documentation Index

| Document | Purpose |
|----------|---------|
| **START_HERE.md** | Fix database error (Issue #1) |
| **FIX_ADMIN_PANEL_BUILD.md** | Fix build error (Issue #2) |
| **FIX_DATABASE_ERROR.md** | Alternative database fix guide |
| **DATABASE_SETUP.md** | Complete database documentation |
| **DEPLOYMENT_CHECKLIST.md** | Full deployment checklist |
| **CLOUDPANEL_VPS_DEPLOYMENT.md** | Complete VPS setup guide |
| **DEPLOYMENT_OPTIONS.md** | Single domain vs subdomain |
| **QUICK_REFERENCE.md** | Daily operations reference |

---

## 🔄 Correct Deployment Order

Follow this order to avoid issues:

### 1️⃣ Backend API Setup:
```bash
# Upload files
# Configure .env
# Install dependencies
npm install

# Create database tables
mysql -u user -p database < migrations/admin-panel-schema.sql

# Create admin user
node src/admin/db/admin-seed.js

# Start API
pm2 start src/server.js --name "cricket-api"
```

### 2️⃣ Admin Panel Setup:
```bash
# Upload ALL files (including app directory!)
# Configure .env.local
# Install dependencies
npm install

# Build
npm run build

# Start
pm2 start npm --name "admin-panel" -- start
```

### 3️⃣ Verify:
```bash
# Check processes
pm2 list

# Check API
curl https://api.webcrichd.co/health

# Check admin panel
curl -I https://admin.webcrichd.co

# Login to admin panel
# Visit: https://admin.webcrichd.co/login
```

---

## 🆘 Need Help?

### If database import fails:
1. Check database credentials in `.env`
2. Verify database exists: `mysql -u user -p -e "SHOW DATABASES;"`
3. Check if migrations folder exists: `ls -la migrations/`
4. See **DATABASE_SETUP.md** for troubleshooting

### If build still fails:
1. Verify `app` directory exists: `ls -la app/`
2. Check all subdirectories: `ls -la app/dashboard/`
3. Verify package.json exists: `cat package.json`
4. See **FIX_ADMIN_PANEL_BUILD.md** for troubleshooting

### If login doesn't work:
1. Check API is running: `pm2 list`
2. Check API URL in `.env.local`: `cat .env.local`
3. Verify admin user exists: `mysql -u user -p database -e "SELECT * FROM admin_users;"`
4. Check browser console for errors

---

## ✅ Success Indicators

You'll know everything is working when:

1. ✅ Database has 15 tables
2. ✅ Seed script shows admin credentials
3. ✅ API responds at `/health` endpoint
4. ✅ Admin panel build completes
5. ✅ Both PM2 processes running
6. ✅ Can access login page
7. ✅ Can login with credentials
8. ✅ Dashboard loads with data

---

## 🎯 Next Steps

After fixing both issues:

1. **Test all admin panel features:**
   - Create/edit matches
   - Manage homepage sections
   - Create news articles
   - Send notifications
   - Manage users and roles

2. **Configure production settings:**
   - Set strong JWT secrets
   - Configure Redis (if using)
   - Set up SSL certificates
   - Configure firewall

3. **Set up monitoring:**
   - PM2 monitoring
   - Log rotation
   - Database backups
   - Uptime monitoring

4. **Security hardening:**
   - Change default admin password
   - Review user permissions
   - Enable rate limiting
   - Configure CORS properly

---

## 📞 Quick Commands Reference

```bash
# Check database tables
mysql -u user -p database -e "SHOW TABLES;"

# Check if app directory exists
ls -la ~/htdocs/app.webcrichd.co/app/

# Check PM2 processes
pm2 list

# View logs
pm2 logs

# Restart services
pm2 restart all

# Check API health
curl https://api.webcrichd.co/health

# Check admin panel
curl -I https://admin.webcrichd.co
```

---

## 🎉 Summary

**Two issues, two simple fixes:**

1. **Database tables missing** → Import schema file
2. **App directory missing** → Re-upload admin-panel folder

Follow the guides linked above and you'll be up and running in minutes! 🚀
