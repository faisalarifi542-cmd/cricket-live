# 🚀 START HERE - Database Setup Instructions

## Current Issue

You tried to run the seed script but got this error:
```
Error: Table 'webcrichdapi.admin_roles' doesn't exist
```

**Why?** The database tables haven't been created yet. You need to import the schema first.

---

## ✅ Solution (Follow These Steps)

### On Your Production Server (api.webcrichd.co)

**Step 1: Navigate to your API directory**
```bash
cd ~/htdocs/api.webcrichd.co
```

**Step 2: Check if migrations folder exists**
```bash
ls -la migrations/
```

**If migrations folder doesn't exist:**
```bash
mkdir -p migrations
```

Then you need to upload the `admin-panel-schema.sql` file to this folder. You can:
- Use SFTP/FTP to upload `cricket-api/migrations/admin-panel-schema.sql` from your local project
- Or create it manually (see FIX_DATABASE_ERROR.md for the full SQL)

**Step 3: Import the database schema**
```bash
mysql -u webcrichd_api -p webcrichdapi < migrations/admin-panel-schema.sql
```

Replace `webcrichd_api` with your actual database username if different.

When prompted, enter your database password.

**Step 4: Verify tables were created**
```bash
mysql -u webcrichd_api -p webcrichdapi -e "SHOW TABLES;"
```

You should see 15 tables listed.

**Step 5: Run the seed script**
```bash
node src/admin/db/admin-seed.js
```

**Step 6: Save your admin credentials**

The seed script will output something like:
```
==============================================
 Super-admin credentials (save these now):
   email:    admin@cricpro.local
   password: abc123xyz789
==============================================
```

**⚠️ SAVE THIS PASSWORD!** You'll need it to login.

---

## 📋 Quick Command Summary

```bash
# Navigate to API directory
cd ~/htdocs/api.webcrichd.co

# Import schema
mysql -u webcrichd_api -p webcrichdapi < migrations/admin-panel-schema.sql

# Run seed script
node src/admin/db/admin-seed.js

# Save the password shown in output!
```

---

## 🎯 What This Does

1. **Creates 15 database tables** for the admin panel
2. **Creates default roles** (super-admin, admin, editor, viewer)
3. **Creates default permissions** (all CRUD operations)
4. **Creates your first admin user** with email `admin@cricpro.local`
5. **Assigns super-admin role** to this user

---

## 📚 Additional Documentation

- **FIX_DATABASE_ERROR.md** - Detailed troubleshooting guide
- **DATABASE_SETUP.md** - Complete database setup documentation
- **CLOUDPANEL_VPS_DEPLOYMENT.md** - Full VPS deployment guide
- **DEPLOYMENT_OPTIONS.md** - Single domain vs subdomain options
- **QUICK_REFERENCE.md** - Daily operations reference

---

## 🔍 Troubleshooting

### "No such file or directory: migrations/admin-panel-schema.sql"
The migrations folder wasn't uploaded. Create it and upload the schema file:
```bash
mkdir -p migrations
# Then upload admin-panel-schema.sql to this folder
```

### "Access denied for user"
Check your database credentials in the `.env` file. Make sure DB_USER and DB_PASSWORD are correct.

### "Unknown database 'webcrichdapi'"
The database doesn't exist. Create it first:
```bash
mysql -u webcrichd_api -p -e "CREATE DATABASE webcrichdapi CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
```

### "Can't connect to MySQL server"
Make sure MySQL is running:
```bash
sudo systemctl status mysql
```

---

## ✨ After Setup

Once the seed script completes successfully:

1. **Start your API** (if not already running):
   ```bash
   pm2 restart cricket-api
   # or
   node src/server.js
   ```

2. **Access admin panel**:
   - URL: https://admin.webcrichd.co/login
   - Email: `admin@cricpro.local`
   - Password: [the one shown in seed script output]

3. **Change your password** after first login (recommended)

---

## 📦 Files You Need

Make sure these files are on your server:

```
~/htdocs/api.webcrichd.co/
├── migrations/
│   └── admin-panel-schema.sql    ← This creates all tables
├── src/
│   └── admin/
│       └── db/
│           └── admin-seed.js      ← This creates admin user
└── .env                           ← Database credentials
```

---

## 🆘 Need Help?

If you encounter any issues:

1. Check the error message carefully
2. Verify database credentials in `.env`
3. Make sure MySQL is running
4. Check if migrations folder exists
5. Verify the schema file is present

All error messages are logged with details to help troubleshoot.

---

**That's it!** Follow these steps and your admin panel database will be ready. 🎉
