#!/bin/bash

# Cricket API Production Deployment Script with Critical Fixes
# This script deploys the fixes for points table, squads, scorecard, and overs endpoints

echo "========================================="
echo "Cricket API Critical Fixes Deployment"
echo "========================================="
echo ""

# Configuration
SERVER_USER="root"
SERVER_HOST="api.webcrichd.co"
APP_DIR="/home/webcrichd.co/htdocs/cricket-api"
PM2_APP_NAME="cricket-api"

echo "Step 1: Connecting to production server..."
ssh ${SERVER_USER}@${SERVER_HOST} << 'REMOTE_SCRIPT'

echo "Step 2: Stopping PM2 application..."
cd /home/webcrichd.co/htdocs/cricket-api
pm2 stop cricket-api

echo ""
echo "Step 3: Clearing Redis cache for all problematic endpoints..."

# Clear matches cache
redis-cli KEYS "matches:*" | xargs -r redis-cli DEL

# Clear points table cache
redis-cli KEYS "points-table:*" | xargs -r redis-cli DEL
redis-cli DEL "points-table:9241"

# Clear match-specific caches for test matches
redis-cli KEYS "match:152241:*" | xargs -r redis-cli DEL
redis-cli KEYS "match:152252:*" | xargs -r redis-cli DEL
redis-cli KEYS "match:152241:squads" | xargs -r redis-cli DEL
redis-cli KEYS "match:152241:scorecard" | xargs -r redis-cli DEL
redis-cli KEYS "match:152241:overs" | xargs -r redis-cli DEL
redis-cli KEYS "match:152252:live-line" | xargs -r redis-cli DEL

# Clear series cache
redis-cli KEYS "series:9241:*" | xargs -r redis-cli DEL

# Clear scorecard cache
redis-cli KEYS "scorecard:*" | xargs -r redis-cli DEL

echo "Redis cache cleared!"
echo ""

echo "Step 4: Restarting PM2 application..."
pm2 start cricket-api

echo ""
echo "Step 5: Waiting for application to start..."
sleep 5

echo ""
echo "Step 6: Checking application health..."
curl -s http://localhost:3000/health | jq .

echo ""
echo "Step 7: Testing critical endpoints..."
echo "Testing /points-table/9241..."
curl -s http://localhost:3000/points-table/9241 | jq '.data | length'

echo ""
echo "Testing /match/152241/squads..."
curl -s http://localhost:3000/match/152241/squads | jq '.data.team1.team_name'

echo ""
echo "Testing /match/152241/scorecard..."
curl -s http://localhost:3000/match/152241/scorecard | jq '.data.innings | length'

echo ""
echo "Testing /match/152252/live-line..."
curl -s http://localhost:3000/match/152252/live-line | jq '.success'

echo ""
echo "========================================="
echo "Deployment Complete!"
echo "========================================="

REMOTE_SCRIPT

echo ""
echo "Local deployment complete!"
echo ""
echo "Next steps:"
echo "1. Check server logs: ssh ${SERVER_USER}@${SERVER_HOST} 'pm2 logs cricket-api'"
echo "2. Test production endpoints:"
echo "   - https://api.webcrichd.co/points-table/9241"
echo "   - https://api.webcrichd.co/match/152241/squads"
echo "   - https://api.webcrichd.co/match/152241/scorecard"
echo "   - https://api.webcrichd.co/match/152252/live-line"
echo ""
