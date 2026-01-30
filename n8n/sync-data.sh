#!/bin/bash
# Sync N8N data from Voice Agent Platform backend to standalone instance
# This script copies workflows, credentials, and configuration

set -e

echo "📦 N8N Data Synchronization Tool"
echo "================================"
echo ""

# Source and destination paths
VOICE_AGENT_BACKEND="/mnt/c/Users/Admin/Code/Projects/Voice-Agent-Platform-Final/voice-agent-platform/backend"
SOURCE_WORKFLOWS="$VOICE_AGENT_BACKEND/n8n-workflows"
SOURCE_CREDENTIALS="$VOICE_AGENT_BACKEND/n8n-credentials"
SOURCE_CERTS="$VOICE_AGENT_BACKEND/security/CloudflareCertificates"

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
cd "$SCRIPT_DIR"

# Check if source directories exist
if [ ! -d "$SOURCE_WORKFLOWS" ]; then
    echo "⚠️  Warning: Source workflows directory not found: $SOURCE_WORKFLOWS"
fi

if [ ! -d "$SOURCE_CREDENTIALS" ]; then
    echo "⚠️  Warning: Source credentials directory not found: $SOURCE_CREDENTIALS"
fi

# Check if n8n container is running
if ! docker ps --format '{{.Names}}' | grep -q '^n8n$'; then
    echo "❌ N8N container is not running. Please start it first with ./start.sh"
    exit 1
fi

echo "Choose sync method:"
echo "1. One-time copy (copy data from backend to standalone)"
echo "2. Enable continuous sync (mount backend directories)"
echo "3. Export current standalone data"
echo ""
read -p "Enter your choice (1-3): " choice

case $choice in
    1)
        echo ""
        echo "📋 One-time copy mode"
        echo "===================="

        # Copy workflows
        if [ -d "$SOURCE_WORKFLOWS" ]; then
            echo "📁 Copying workflows..."
            docker exec n8n mkdir -p /home/node/.n8n/workflows
            docker cp "$SOURCE_WORKFLOWS/." n8n:/home/node/.n8n/workflows/
            echo "✅ Workflows copied"
        fi

        # Copy credentials
        if [ -d "$SOURCE_CREDENTIALS" ]; then
            echo "🔑 Copying credentials..."
            docker exec n8n mkdir -p /home/node/.n8n/credentials
            docker cp "$SOURCE_CREDENTIALS/." n8n:/home/node/.n8n/credentials/
            echo "✅ Credentials copied"
        fi

        # Copy certificates if they exist
        if [ -d "$SOURCE_CERTS" ]; then
            echo "🔒 Copying certificates..."
            docker exec n8n mkdir -p /opt/custom-certificates
            docker cp "$SOURCE_CERTS/." n8n:/opt/custom-certificates/
            echo "✅ Certificates copied"
        fi

        echo ""
        echo "🎉 Data sync complete!"
        echo "♻️  Restarting n8n container to apply changes..."
        docker-compose restart n8n
        echo "✅ Done! Access n8n at http://localhost:5678"
        ;;

    2)
        echo ""
        echo "🔗 Continuous sync mode"
        echo "======================"
        echo ""
        echo "This will modify docker-compose.yaml to mount backend directories."
        echo "Changes will take effect after restarting the container."
        echo ""
        read -p "Continue? (y/n): " confirm

        if [ "$confirm" != "y" ]; then
            echo "❌ Cancelled"
            exit 0
        fi

        # Update docker-compose.yaml to uncomment volume mounts
        if [ -f "docker-compose.yaml" ]; then
            echo "📝 Updating docker-compose.yaml..."

            # Create backup
            cp docker-compose.yaml docker-compose.yaml.backup

            # Uncomment the volume mount lines
            sed -i 's/# - \/mnt\/c\/Users\/Admin/- \/mnt\/c\/Users\/Admin/g' docker-compose.yaml

            echo "✅ Configuration updated"
            echo "♻️  Restarting n8n to apply changes..."

            docker-compose down
            docker-compose up -d

            echo "✅ Continuous sync enabled!"
            echo "📝 Backup saved as: docker-compose.yaml.backup"
        else
            echo "❌ docker-compose.yaml not found"
            exit 1
        fi
        ;;

    3)
        echo ""
        echo "📤 Export standalone data"
        echo "========================"

        # Create export directory
        EXPORT_DIR="$SCRIPT_DIR/n8n-export-$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$EXPORT_DIR"

        echo "📁 Export directory: $EXPORT_DIR"

        # Export workflows
        echo "📁 Exporting workflows..."
        docker cp n8n:/home/node/.n8n/workflows "$EXPORT_DIR/" 2>/dev/null || echo "⚠️  No workflows found"

        # Export credentials
        echo "🔑 Exporting credentials..."
        docker cp n8n:/home/node/.n8n/credentials "$EXPORT_DIR/" 2>/dev/null || echo "⚠️  No credentials found"

        # Export full .n8n directory
        echo "💾 Exporting full n8n data..."
        docker cp n8n:/home/node/.n8n "$EXPORT_DIR/n8n-data" 2>/dev/null || echo "⚠️  Could not export full data"

        echo ""
        echo "✅ Export complete!"
        echo "📁 Data exported to: $EXPORT_DIR"
        ;;

    *)
        echo "❌ Invalid choice"
        exit 1
        ;;
esac
