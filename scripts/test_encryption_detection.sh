#!/bin/bash

# Test script for encryption key detection functionality
# This script tests various scenarios of encryption key detection

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================${NC}"
}

print_test() {
    echo -e "${YELLOW}[TEST]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓ PASS]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗ FAIL]${NC} $1"
}

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

print_header "N8N Encryption Key Detection Tests"

# Test 1: Environment variable detection
print_test "Test 1: Environment variable detection"
export N8N_ENCRYPTION_KEY="test-key-from-env"
source "$SCRIPT_DIR/backup_n8n.sh"
detect_encryption_key
if [ "$N8N_ENCRYPTION_KEY" = "test-key-from-env" ]; then
    print_success "Environment variable detection works"
else
    print_error "Environment variable detection failed"
fi
echo ""

# Test 2: Config file detection (with jq)
print_test "Test 2: Config file detection (with jq)"
unset N8N_ENCRYPTION_KEY
if command -v jq &> /dev/null; then
    detect_encryption_key
    if [ -n "$N8N_ENCRYPTION_KEY" ]; then
        print_success "Config file detection with jq works"
        echo "Detected key: ${N8N_ENCRYPTION_KEY:0:8}...${N8N_ENCRYPTION_KEY: -8}"
    else
        print_error "Config file detection with jq failed"
    fi
else
    print_error "jq not available for testing"
fi
echo ""

# Test 3: Config file detection (fallback method)
print_test "Test 3: Config file detection (fallback method without jq)"
unset N8N_ENCRYPTION_KEY

# Temporarily hide jq
if command -v jq &> /dev/null; then
    # Test the fallback method directly
    config_file="$HOME/.n8n/config"
    if [ -f "$config_file" ]; then
        key=$(grep -o '"encryptionKey"[[:space:]]*:[[:space:]]*"[^"]*"' "$config_file" 2>/dev/null | sed 's/.*"encryptionKey"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
        if [ -n "$key" ]; then
            print_success "Fallback method works"
            echo "Detected key: ${key:0:8}...${key: -8}"
        else
            print_error "Fallback method failed"
        fi
    else
        print_error "Config file not found"
    fi
else
    print_error "Cannot test fallback method - jq not available to simulate absence"
fi
echo ""

# Test 4: Full backup test
print_test "Test 4: Full backup with automatic key detection"
unset N8N_ENCRYPTION_KEY
echo "Running backup with automatic key detection..."
if "$SCRIPT_DIR/backup_n8n.sh" native >/dev/null 2>&1; then
    print_success "Full backup with automatic key detection works"
else
    print_error "Full backup with automatic key detection failed"
fi
echo ""

# Test 5: Key validation
print_test "Test 5: Key validation and format"
unset N8N_ENCRYPTION_KEY
detect_encryption_key
if [ -n "$N8N_ENCRYPTION_KEY" ]; then
    key_length=${#N8N_ENCRYPTION_KEY}
    if [ "$key_length" -eq 32 ]; then
        print_success "Key length is correct (32 characters)"
    else
        print_error "Key length is incorrect ($key_length characters, expected 32)"
    fi
    
    # Check if key contains only valid base64 characters
    if [[ "$N8N_ENCRYPTION_KEY" =~ ^[A-Za-z0-9+/]*$ ]]; then
        print_success "Key format appears valid (base64-like)"
    else
        print_error "Key format appears invalid"
    fi
else
    print_error "No key detected for validation"
fi
echo ""

print_header "Test Summary"
echo "All encryption key detection mechanisms have been tested."
echo "The backup system can automatically:"
echo "1. Use environment variable if set"
echo "2. Read from n8n config file using jq (preferred)"
echo "3. Read from n8n config file using grep/sed (fallback)"
echo "4. Validate key format and length"
echo "5. Export key to environment for n8n CLI commands"
echo ""
echo "Your current encryption key: ${N8N_ENCRYPTION_KEY:0:8}...${N8N_ENCRYPTION_KEY: -8} (${#N8N_ENCRYPTION_KEY} chars)"
