#!/bin/bash
# N8N Standalone Instance Stop Script

set -e

echo "🛑 Stopping N8N Workflow Automation..."
echo "======================================"

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
cd "$SCRIPT_DIR"

# Check if n8n container is running
if ! docker ps --format '{{.Names}}' | grep -q '^n8n$'; then
    echo "ℹ️  N8N is not running"
    exit 0
fi

# Stop n8n
echo "🛑 Stopping n8n container..."
docker-compose down

echo "✅ N8N stopped successfully!"
