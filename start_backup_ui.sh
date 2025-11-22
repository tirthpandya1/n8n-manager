#!/bin/bash

###############################################################################
# N8N Backup Utility - Startup Script (Linux/macOS)
# Starts the FastAPI backup utility web interface
###############################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_UI_DIR="${SCRIPT_DIR}/backup_ui"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}N8N Backup Utility - Starting Server${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if Python 3 is available (try python3 first, then python)
PYTHON_CMD=""
if command -v python3 &> /dev/null; then
    PYTHON_CMD="python3"
elif command -v python &> /dev/null; then
    # Check if python is Python 3
    PYTHON_VERSION=$(python --version 2>&1 | grep -oP 'Python 3\.\d+')
    if [ -n "$PYTHON_VERSION" ]; then
        PYTHON_CMD="python"
    fi
fi

if [ -z "$PYTHON_CMD" ]; then
    echo -e "${RED}[ERROR] Python 3 is not installed or not in PATH${NC}"
    echo "Please install Python 3.8 or higher"
    exit 1
fi

PYTHON_VERSION=$($PYTHON_CMD --version | cut -d' ' -f2)
echo -e "${GREEN}[INFO] Using $PYTHON_CMD (version: ${PYTHON_VERSION})${NC}"

# Change to backup_ui directory
cd "${BACKUP_UI_DIR}"

# Check if virtual environment exists
if [ ! -d "venv" ]; then
    echo -e "${YELLOW}[INFO] Virtual environment not found. Creating...${NC}"
    $PYTHON_CMD -m venv venv
    echo -e "${GREEN}[SUCCESS] Virtual environment created${NC}"
fi

# Activate virtual environment
echo -e "${BLUE}[INFO] Activating virtual environment...${NC}"
source venv/bin/activate

# Install/upgrade dependencies
echo -e "${BLUE}[INFO] Installing dependencies...${NC}"
pip install -q --upgrade pip
pip install -q -r requirements.txt
echo -e "${GREEN}[SUCCESS] Dependencies installed${NC}"

# Check if port 8001 is already in use
if lsof -Pi :8001 -sTCP:LISTEN -t >/dev/null 2>&1; then
    echo -e "${YELLOW}[WARNING] Port 8001 is already in use${NC}"
    echo "The backup utility may already be running or another service is using this port"
    read -p "Do you want to continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Start the server
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Starting N8N Backup Utility Server${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${BLUE}Server will be available at:${NC}"
echo -e "  ${GREEN}http://localhost:8001${NC}"
echo -e "  ${GREEN}http://127.0.0.1:8001${NC}"
echo ""
echo -e "${YELLOW}Press CTRL+C to stop the server${NC}"
echo ""

# Start FastAPI with uvicorn
$PYTHON_CMD -m uvicorn main:app --host 0.0.0.0 --port 8001 --reload

# Cleanup on exit
deactivate
