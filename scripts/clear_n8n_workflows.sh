#!/bin/bash

# Clear N8N Workflows Script
# This script clears all workflows from an n8n database
# Use with caution - this is DESTRUCTIVE!

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running in Docker container
if [ -f /.dockerenv ]; then
    print_status "Running inside Docker container"
    IN_DOCKER=true
else
    print_status "Running on host system"
    IN_DOCKER=false
fi

# Warning
echo ""
print_warning "=========================================="
print_warning "   N8N WORKFLOW DATABASE CLEANER"
print_warning "=========================================="
echo ""
print_error "WARNING: This will DELETE ALL workflows from the n8n database!"
print_error "This action is IRREVERSIBLE!"
echo ""
print_status "This script will:"
print_status "  1. Stop n8n (if running)"
print_status "  2. Clear all workflow-related tables"
print_status "  3. Clear all credentials"
print_status "  4. Clear all executions"
print_status "  5. Start n8n again"
echo ""
read -p "Are you ABSOLUTELY SURE you want to continue? Type 'DELETE ALL' to confirm: " confirm

if [ "$confirm" != "DELETE ALL" ]; then
    print_error "Confirmation not matched. Aborting."
    exit 1
fi

echo ""
read -p "Enter the n8n database file path [default: /home/node/.n8n/database.sqlite]: " db_path
db_path=${db_path:-/home/node/.n8n/database.sqlite}

if [ ! -f "$db_path" ]; then
    print_error "Database file not found at: $db_path"
    exit 1
fi

# Backup the database first
backup_file="${db_path}.backup_$(date +%Y%m%d_%H%M%S)"
print_status "Creating backup of database..."
cp "$db_path" "$backup_file"
print_success "Database backed up to: $backup_file"

# Clear the database
print_status "Clearing workflows and related data from database..."

sqlite3 "$db_path" << 'EOF'
-- Disable foreign key constraints temporarily
PRAGMA foreign_keys = OFF;

-- Clear workflow-related tables
DELETE FROM workflow_statistics;
DELETE FROM workflow_tag_mapping;
DELETE FROM execution_data;
DELETE FROM execution_metadata;
DELETE FROM execution_annotation;
DELETE FROM workflow_history;
DELETE FROM workflow_version;
DELETE FROM execution_entity;
DELETE FROM workflow_entity;
DELETE FROM credentials_entity;

-- Re-enable foreign key constraints
PRAGMA foreign_keys = ON;

-- Vacuum to reclaim space
VACUUM;
EOF

if [ $? -eq 0 ]; then
    print_success "Database cleared successfully!"
    print_status "Backup available at: $backup_file"
    echo ""
    print_status "You can now import your workflows."
    print_warning "Remember to restart n8n for changes to take effect."
else
    print_error "Failed to clear database!"
    print_status "Restoring from backup..."
    cp "$backup_file" "$db_path"
    exit 1
fi
