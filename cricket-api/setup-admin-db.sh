#!/bin/bash

# ============================================
# CricPro Admin Panel - Database Setup Script
# ============================================

echo "================================================"
echo "CricPro Admin Panel - Database Setup"
echo "================================================"
echo ""

# Load environment variables
if [ -f .env ]; then
    export $(cat .env | grep -v '^#' | xargs)
fi

# Database credentials
DB_HOST=${DB_HOST:-127.0.0.1}
DB_PORT=${DB_PORT:-3306}
DB_USER=${DB_USER:-root}
DB_NAME=${DB_NAME:-crickadmin}

echo "Database Configuration:"
echo "  Host: $DB_HOST"
echo "  Port: $DB_PORT"
echo "  User: $DB_USER"
echo "  Database: $DB_NAME"
echo ""

# Check if MySQL is accessible
echo "Checking MySQL connection..."
mysql -h $DB_HOST -P $DB_PORT -u $DB_USER -p$DB_PASSWORD -e "SELECT 1;" > /dev/null 2>&1

if [ $? -ne 0 ]; then
    echo "❌ Error: Cannot connect to MySQL"
    echo "Please check your database credentials in .env file"
    exit 1
fi

echo "✓ MySQL connection successful"
echo ""

# Check if database exists
echo "Checking if database exists..."
DB_EXISTS=$(mysql -h $DB_HOST -P $DB_PORT -u $DB_USER -p$DB_PASSWORD -e "SHOW DATABASES LIKE '$DB_NAME';" | grep "$DB_NAME")

if [ -z "$DB_EXISTS" ]; then
    echo "Database '$DB_NAME' does not exist. Creating..."
    mysql -h $DB_HOST -P $DB_PORT -u $DB_USER -p$DB_PASSWORD -e "CREATE DATABASE $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    
    if [ $? -eq 0 ]; then
        echo "✓ Database created successfully"
    else
        echo "❌ Error: Failed to create database"
        exit 1
    fi
else
    echo "✓ Database already exists"
fi

echo ""

# Import schema
echo "Importing admin panel schema..."
mysql -h $DB_HOST -P $DB_PORT -u $DB_USER -p$DB_PASSWORD $DB_NAME < migrations/admin-panel-schema.sql

if [ $? -eq 0 ]; then
    echo "✓ Schema imported successfully"
else
    echo "❌ Error: Failed to import schema"
    exit 1
fi

echo ""

# Run seed script
echo "Seeding admin data (roles, permissions, admin user)..."
node src/admin/db/admin-seed.js

if [ $? -eq 0 ]; then
    echo ""
    echo "================================================"
    echo "✓ Admin Panel Database Setup Complete!"
    echo "================================================"
    echo ""
    echo "Next Steps:"
    echo "  1. Note the admin credentials shown above"
    echo "  2. Start the API: node src/server.js"
    echo "  3. Start the admin panel: cd ../admin-panel && npm run dev"
    echo "  4. Login at: http://localhost:3000/login"
    echo ""
else
    echo "❌ Error: Failed to seed data"
    exit 1
fi
