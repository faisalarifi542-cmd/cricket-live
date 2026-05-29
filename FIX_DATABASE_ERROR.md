# 🔧 Quick Fix: Database Tables Missing

## Your Error:
```
Error: Table 'webcrichdapi.admin_roles' doesn't exist
```

## The Fix (2 Simple Steps):

### Step 1: Import Database Schema

Run this command on your server:

```bash
cd ~/htdocs/api.webcrichd.co
mysql -u webcrichd_api -p webcrichdapi < migrations/admin-panel-schema.sql
```

**Note:** Replace `webcrichd_api` with your actual database username if different.

When prompted, enter your database password.

---

### Step 2: Run Seed Script

After the schema is imported, run:

```bash
node src/admin/db/admin-seed.js
```

---

## Expected Output:

You should see:

```
{"level":"info","message":"Seeding admin panel roles + permissions..."}
{"level":"info","message":"Created super admin: admin@cricpro.local"}
==============================================
 Super-admin credentials (save these now):
   email:    admin@cricpro.local
   password: [YOUR_RANDOM_PASSWORD]
==============================================
{"level":"info","message":"Admin seed complete."}
```

**⚠️ IMPORTANT:** Save the password shown! You'll need it to login to the admin panel.

---

## If migrations folder doesn't exist:

If you get "No such file or directory" error, the migrations folder wasn't uploaded. Create it:

```bash
cd ~/htdocs/api.webcrichd.co
mkdir -p migrations
```

Then upload the `admin-panel-schema.sql` file to the migrations folder, or create it manually:

```bash
nano migrations/admin-panel-schema.sql
```

Copy the entire content from `cricket-api/migrations/admin-panel-schema.sql` (from your local project), paste it, then save (Ctrl+X, Y, Enter).

Then run Step 1 and Step 2 above.

---

## Verify Tables Were Created:

```bash
mysql -u webcrichd_api -p webcrichdapi -e "SHOW TABLES;"
```

You should see 15 tables including:
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

---

## That's It!

After these steps, your admin panel database will be ready and you can login with the credentials shown in the seed script output.
