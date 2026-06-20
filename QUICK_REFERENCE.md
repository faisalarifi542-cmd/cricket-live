# CricPro Admin Panel - Quick Reference Card

## 🚀 Quick Start Commands

### Start Services
```bash
pm2 start cricket-api
pm2 start admin-panel
```

### Stop Services
```bash
pm2 stop cricket-api
pm2 stop admin-panel
```

### Restart Services
```bash
pm2 restart cricket-api
pm2 restart admin-panel
```

### View Logs
```bash
pm2 logs cricket-api
pm2 logs admin-panel
pm2 logs --lines 100
```

### Check Status
```bash
pm2 status
pm2 monit
```

---

## 🔧 Service Management

### Nginx
```bash
sudo systemctl status nginx
sudo systemctl restart nginx
sudo systemctl reload nginx
sudo nginx -t  # Test configuration
```

### MySQL
```bash
sudo systemctl status mysql
sudo systemctl restart mysql
mysql -u cricpro -p crickadmin
```

### Redis
```bash
sudo systemctl status redis-server
sudo systemctl restart redis-server
redis-cli ping
redis-cli
```

---

## 📁 Important Paths

### Application
```
Backend API:    /home/cricpro/cricket-live/cricket-api
Admin Panel:    /home/cricpro/cricket-live/admin-panel
Logs:           /home/cricpro/cricket-live/*/logs/
Backups:        /home/cricpro/backups/
```

### Configuration
```
API .env:       /home/cricpro/cricket-live/cricket-api/.env
Panel .env:     /home/cricpro/cricket-live/admin-panel/.env.local
Nginx API:      /etc/nginx/sites-available/api.yourdomain.com
Nginx Admin:    /etc/nginx/sites-available/admin.yourdomain.com
```

### Logs
```
Nginx Access:   /var/log/nginx/access.log
Nginx Error:    /var/log/nginx/error.log
PM2 Logs:       ~/.pm2/logs/
MySQL Logs:     /var/log/mysql/error.log
```

---

## 🔐 Access URLs

### Production
```
API:            https://api.yourdomain.com
Admin Panel:    https://admin.yourdomain.com
CloudPanel:     https://your-vps-ip:8443
```

### Local Development
```
API:            http://localhost:5000
Admin Panel:    http://localhost:3000
```

---

## 👤 Default Credentials

### Admin Panel
```
Email:          admin@cricpro.local
Password:       (from seed script output)
```

### Database
```
Host:           localhost
Port:           3306
Database:       crickadmin
User:           cricpro
Password:       (from .env)
```

---

## 🔄 Update Application

### Backend API
```bash
cd /home/cricpro/cricket-live/cricket-api
git pull
npm install --production
pm2 restart cricket-api
```

### Admin Panel
```bash
cd /home/cricpro/cricket-live/admin-panel
git pull
npm install
npm run build
pm2 restart admin-panel
```

---

## 🗄️ Database Operations

### Backup Database
```bash
mysqldump -u cricpro -p crickadmin > backup_$(date +%Y%m%d).sql
```

### Restore Database
```bash
mysql -u cricpro -p crickadmin < backup_20240101.sql
```

### Access Database
```bash
mysql -u cricpro -p crickadmin
```

### Common Queries
```sql
-- Show all tables
SHOW TABLES;

-- Count admin users
SELECT COUNT(*) FROM admin_users;

-- List active streams
SELECT * FROM streams WHERE is_active = 1;

-- Recent audit logs
SELECT * FROM admin_audit_logs ORDER BY created_at DESC LIMIT 10;
```

---

## 🔍 Troubleshooting

### Check if services are running
```bash
pm2 status
sudo systemctl status nginx
sudo systemctl status mysql
sudo systemctl status redis-server
```

### Check ports
```bash
sudo lsof -i :5000  # API
sudo lsof -i :3000  # Admin Panel
sudo lsof -i :80    # HTTP
sudo lsof -i :443   # HTTPS
```

### Check disk space
```bash
df -h
du -sh /home/cricpro/*
```

### Check memory
```bash
free -h
htop
```

### View recent errors
```bash
pm2 logs cricket-api --err --lines 50
pm2 logs admin-panel --err --lines 50
sudo tail -50 /var/log/nginx/error.log
```

### Test API endpoint
```bash
curl https://api.yourdomain.com/health
curl -I https://api.yourdomain.com
```

### Test Admin Panel
```bash
curl https://admin.yourdomain.com
curl -I https://admin.yourdomain.com
```

---

## 🛡️ Security

### Check firewall
```bash
sudo ufw status
```

### Check SSL certificates
```bash
sudo certbot certificates
sudo certbot renew --dry-run
```

### Check Fail2Ban
```bash
sudo fail2ban-client status
sudo fail2ban-client status sshd
```

### View failed login attempts
```bash
sudo grep "Failed password" /var/log/auth.log
```

---

## 📊 Monitoring

### System resources
```bash
htop
top
vmstat 1
iostat 1
```

### Network connections
```bash
netstat -tulpn
ss -tulpn
```

### Process information
```bash
ps aux | grep node
ps aux | grep nginx
```

### Disk I/O
```bash
iotop
```

---

## 🔄 Maintenance Tasks

### Daily
- [ ] Check PM2 status: `pm2 status`
- [ ] Check logs for errors: `pm2 logs --err`
- [ ] Monitor disk space: `df -h`

### Weekly
- [ ] Review Nginx logs
- [ ] Check database size
- [ ] Verify backups exist
- [ ] Update system packages: `sudo apt update && sudo apt upgrade`

### Monthly
- [ ] Review security logs
- [ ] Check SSL certificate expiry
- [ ] Clean old logs: `pm2 flush`
- [ ] Optimize database: `mysqlcheck -o crickadmin -u cricpro -p`

---

## 📞 Emergency Contacts

### Service Down
1. Check PM2: `pm2 status`
2. Check logs: `pm2 logs`
3. Restart service: `pm2 restart all`
4. Check Nginx: `sudo systemctl status nginx`

### Database Issues
1. Check MySQL: `sudo systemctl status mysql`
2. Check connections: `mysql -u cricpro -p`
3. Review logs: `sudo tail -100 /var/log/mysql/error.log`

### High Load
1. Check processes: `htop`
2. Check disk: `df -h`
3. Check memory: `free -h`
4. Restart services if needed

---

## 🎯 Performance Optimization

### Clear Redis cache
```bash
redis-cli FLUSHDB
```

### Optimize MySQL tables
```bash
mysqlcheck -o crickadmin -u cricpro -p
```

### Clear PM2 logs
```bash
pm2 flush
```

### Clear Nginx cache (if enabled)
```bash
sudo rm -rf /var/cache/nginx/*
sudo systemctl reload nginx
```

---

## 📝 Useful Aliases

Add to `~/.bashrc`:

```bash
# PM2 shortcuts
alias pm2l='pm2 logs'
alias pm2s='pm2 status'
alias pm2r='pm2 restart all'

# Service shortcuts
alias ngr='sudo systemctl restart nginx'
alias ngs='sudo systemctl status nginx'
alias ngt='sudo nginx -t'

# Log shortcuts
alias apilogs='pm2 logs cricket-api'
alias adminlogs='pm2 logs admin-panel'
alias nginxlogs='sudo tail -f /var/log/nginx/error.log'

# Navigation
alias cdapi='cd /home/cricpro/cricket-live/cricket-api'
alias cdadmin='cd /home/cricpro/cricket-live/admin-panel'

# Database
alias dblogin='mysql -u cricpro -p crickadmin'
alias dbbackup='mysqldump -u cricpro -p crickadmin > ~/backups/backup_$(date +%Y%m%d_%H%M%S).sql'
```

Then reload: `source ~/.bashrc`

---

## 🆘 Common Issues & Solutions

### Issue: API returns 502 Bad Gateway
**Solution:**
```bash
pm2 restart cricket-api
pm2 logs cricket-api
```

### Issue: Admin Panel shows blank page
**Solution:**
```bash
cd /home/cricpro/cricket-live/admin-panel
npm run build
pm2 restart admin-panel
```

### Issue: Database connection failed
**Solution:**
```bash
sudo systemctl restart mysql
mysql -u cricpro -p crickadmin  # Test connection
# Check .env credentials
```

### Issue: Redis connection failed
**Solution:**
```bash
sudo systemctl restart redis-server
redis-cli ping  # Should return PONG
```

### Issue: SSL certificate expired
**Solution:**
```bash
sudo certbot renew
sudo systemctl reload nginx
```

### Issue: Out of disk space
**Solution:**
```bash
# Check usage
df -h

# Clean PM2 logs
pm2 flush

# Clean old backups
find ~/backups -mtime +30 -delete

# Clean apt cache
sudo apt clean
```

---

## 📚 Documentation Links

- **CloudPanel**: https://www.cloudpanel.io/docs/
- **PM2**: https://pm2.keymetrics.io/docs/
- **Nginx**: https://nginx.org/en/docs/
- **Node.js**: https://nodejs.org/docs/
- **Next.js**: https://nextjs.org/docs

---

## ✅ Health Check Checklist

Run this daily:

```bash
# 1. Check all services
pm2 status
sudo systemctl status nginx
sudo systemctl status mysql
sudo systemctl status redis-server

# 2. Check API health
curl https://api.yourdomain.com/health

# 3. Check Admin Panel
curl https://admin.yourdomain.com

# 4. Check disk space
df -h

# 5. Check memory
free -h

# 6. Check for errors
pm2 logs --err --lines 20

# 7. Check SSL expiry
sudo certbot certificates
```

---

**Keep this reference handy for quick troubleshooting and maintenance!** 📋
