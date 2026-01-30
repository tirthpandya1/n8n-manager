#!/bin/bash
# N8N Standalone Instance Startup Script
# This script starts the standalone n8n instance on port 5678

set -e

echo "🚀 Starting N8N Workflow Automation..."
echo "======================================"

# Check if Docker is running
if ! docker info >/dev/null 2>&1; then
    echo "❌ Docker is not running. Please start Docker first."
    exit 1
fi

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
cd "$SCRIPT_DIR"

echo "📁 Working directory: $SCRIPT_DIR"

# Check if n8n container is already running
if docker ps --format '{{.Names}}' | grep -q '^n8n$'; then
    echo "✅ N8N is already running"
    echo "📍 Access at: http://localhost:5678"
    echo "👤 Username: admin"
    echo "🔑 Password: Ivoryt#1"
    exit 0
fi

# Stop any existing n8n container
if docker ps -a --format '{{.Names}}' | grep -q '^n8n$'; then
    echo "🧹 Removing existing n8n container..."
    docker-compose down
fi

# Start n8n
echo "🚀 Starting n8n container..."
docker-compose up -d

# Wait for n8n to be ready
echo "⏳ Waiting for n8n to be ready..."
max_attempts=30
attempt=1

while [ $attempt -le $max_attempts ]; do
    if docker exec n8n wget --no-verbose --tries=1 --spider http://localhost:5678/healthz >/dev/null 2>&1; then
        echo "✅ N8N is ready!"
        break
    fi

    echo "   Attempt $attempt/$max_attempts - waiting..."
    sleep 2
    attempt=$((attempt + 1))
done

if [ $attempt -gt $max_attempts ]; then
    echo "❌ N8N failed to start within timeout"
    echo "📋 Check logs with: docker-compose logs n8n"
    exit 1
fi

echo ""
echo "🎉 N8N Started Successfully!"
echo "============================"
echo "📍 Access URL:  http://localhost:5678"
echo "👤 Username:    admin"
echo "🔑 Password:    Ivoryt#1"
echo ""
echo "📋 Useful Commands:"
echo "   View logs:     docker-compose logs -f n8n"
echo "   Stop n8n:      docker-compose down"
echo "   Restart n8n:   docker-compose restart n8n"
echo "   Shell access:  docker exec -it n8n /bin/sh"
echo ""
