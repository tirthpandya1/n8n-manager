#!/bin/bash

# N8N Setup Verification Script
# This script verifies that the n8n backup/restore system is properly configured
# Usage: ./verify_setup.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
N8N_DIR="$(dirname "$SCRIPT_DIR")"

# Counters
CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_WARNING=0

# Function to print colored output
print_header() {
    echo -e "${CYAN}================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}================================${NC}"
}

print_check() {
    echo -e "${BLUE}[CHECK]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓ PASS]${NC} $1"
    ((CHECKS_PASSED++))
}

print_warning() {
    echo -e "${YELLOW}[⚠ WARN]${NC} $1"
    ((CHECKS_WARNING++))
}

print_error() {
    echo -e "${RED}[✗ FAIL]${NC} $1"
    ((CHECKS_FAILED++))
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Function to check file existence and permissions
check_file() {
    local file="$1"
    local description="$2"
    local should_be_executable="$3"
    
    print_check "Checking $description"
    
    if [ -f "$file" ]; then
        if [ "$should_be_executable" = "true" ]; then
            if [ -x "$file" ]; then
                print_success "$description exists and is executable"
            else
                print_error "$description exists but is not executable"
                print_info "Fix with: chmod +x $file"
            fi
        else
            print_success "$description exists"
        fi
    else
        print_error "$description not found: $file"
    fi
}

# Function to check directory
check_directory() {
    local dir="$1"
    local description="$2"
    
    print_check "Checking $description"
    
    if [ -d "$dir" ]; then
        print_success "$description exists"
    else
        print_error "$description not found: $dir"
    fi
}

# Function to check command availability
check_command() {
    local cmd="$1"
    local description="$2"
    local required="$3"
    
    print_check "Checking $description"
    
    if command -v "$cmd" &> /dev/null; then
        local version=$($cmd --version 2>/dev/null | head -n1 || echo "unknown version")
        print_success "$description available: $version"
    else
        if [ "$required" = "true" ]; then
            print_error "$description not found (required)"
        else
            print_warning "$description not found (optional)"
        fi
    fi
}

# Function to check n8n installations
check_n8n_installations() {
    print_header "N8N Installation Check"
    
    # Check native n8n
    check_command "n8n" "Native n8n CLI" "false"
    
    # Check Docker
    check_command "docker" "Docker" "false"
    
    if command -v docker &> /dev/null; then
        print_check "Checking for n8n Docker containers"
        local containers=$(docker ps -a --filter "ancestor=n8nio/n8n" --format "{{.Names}}" 2>/dev/null)
        if [ -n "$containers" ]; then
            print_success "Found n8n containers: $containers"
        else
            print_warning "No n8n Docker containers found"
        fi
        
        # Check for containers with n8n in name
        local n8n_containers=$(docker ps -a --filter "name=n8n" --format "{{.Names}}" 2>/dev/null)
        if [ -n "$n8n_containers" ]; then
            print_info "Containers with 'n8n' in name: $n8n_containers"
        fi
    fi
    
    echo ""
}

# Function to check script files
check_script_files() {
    print_header "Script Files Check"
    
    check_file "$SCRIPT_DIR/backup_n8n.sh" "Main backup script" "true"
    check_file "$SCRIPT_DIR/restore_n8n.sh" "Main restore script" "true"
    check_file "$SCRIPT_DIR/docker_backup.sh" "Docker backup script" "true"
    check_file "$SCRIPT_DIR/docker_restore.sh" "Docker restore script" "true"
    check_file "$SCRIPT_DIR/manage_n8n.sh" "Management script" "true"
    check_file "$SCRIPT_DIR/verify_setup.sh" "This verification script" "true"
    
    echo ""
}

# Function to check configuration files
check_config_files() {
    print_header "Configuration Files Check"
    
    check_directory "$N8N_DIR/config" "Config directory"
    check_file "$N8N_DIR/config/n8n_config.json" "N8N configuration file" "false"
    check_file "$N8N_DIR/config/encryption_key_example.txt" "Encryption key example" "false"
    
    echo ""
}

# Function to check backup directory
check_backup_directory() {
    print_header "Backup Directory Check"
    
    check_directory "$N8N_DIR/backups" "Backup directory"
    
    if [ -d "$N8N_DIR/backups" ]; then
        local backup_count=$(ls -1 "$N8N_DIR/backups"/*.tar.gz 2>/dev/null | wc -l)
        if [ "$backup_count" -gt 0 ]; then
            print_info "Found $backup_count existing backup files"
        else
            print_info "No existing backup files (this is normal for new setup)"
        fi
        
        # Check permissions
        if [ -w "$N8N_DIR/backups" ]; then
            print_success "Backup directory is writable"
        else
            print_error "Backup directory is not writable"
        fi
    fi
    
    echo ""
}

# Function to check required tools
check_required_tools() {
    print_header "Required Tools Check"
    
    check_command "tar" "tar (compression)" "true"
    check_command "jq" "jq (JSON processing)" "false"
    check_command "openssl" "OpenSSL (key generation)" "false"
    check_command "node" "Node.js (alternative key generation)" "false"
    
    echo ""
}

# Function to check encryption key setup
check_encryption_setup() {
    print_header "Encryption Key Check"
    
    print_check "Checking N8N_ENCRYPTION_KEY environment variable"
    
    if [ -n "$N8N_ENCRYPTION_KEY" ]; then
        print_success "N8N_ENCRYPTION_KEY is set"
        print_info "Key length: ${#N8N_ENCRYPTION_KEY} characters"
        
        if [ ${#N8N_ENCRYPTION_KEY} -eq 32 ]; then
            print_success "Key length is optimal (32 characters)"
        elif [ ${#N8N_ENCRYPTION_KEY} -lt 16 ]; then
            print_error "Key is too short (minimum 16 characters recommended)"
        else
            print_warning "Key length is acceptable but 32 characters is recommended"
        fi
    else
        print_warning "N8N_ENCRYPTION_KEY not set (required for credential portability)"
        print_info "Set with: export N8N_ENCRYPTION_KEY='your-32-character-key'"
    fi
    
    echo ""
}

# Function to check documentation
check_documentation() {
    print_header "Documentation Check"
    
    check_file "$N8N_DIR/README.md" "Main README file" "false"
    
    echo ""
}

# Function to run basic functionality test
run_basic_test() {
    print_header "Basic Functionality Test"
    
    print_check "Testing script syntax"
    
    # Test each script for syntax errors
    local scripts=("backup_n8n.sh" "restore_n8n.sh" "docker_backup.sh" "docker_restore.sh" "manage_n8n.sh")
    
    for script in "${scripts[@]}"; do
        if bash -n "$SCRIPT_DIR/$script" 2>/dev/null; then
            print_success "$script syntax is valid"
        else
            print_error "$script has syntax errors"
        fi
    done
    
    # Test help output
    print_check "Testing help output"
    if "$SCRIPT_DIR/manage_n8n.sh" help >/dev/null 2>&1; then
        print_success "Management script help works"
    else
        print_error "Management script help failed"
    fi
    
    echo ""
}

# Function to show setup recommendations
show_recommendations() {
    print_header "Setup Recommendations"
    
    echo "Based on the verification results, here are some recommendations:"
    echo ""
    
    if [ -z "$N8N_ENCRYPTION_KEY" ]; then
        print_info "1. Set up encryption key for credential portability:"
        echo "   export N8N_ENCRYPTION_KEY=\$(openssl rand -hex 16)"
        echo ""
    fi
    
    if ! command -v jq &> /dev/null; then
        print_info "2. Install jq for better backup metadata display:"
        echo "   # On macOS: brew install jq"
        echo "   # On Ubuntu: sudo apt install jq"
        echo ""
    fi
    
    if [ ! -d "$N8N_DIR/backups" ]; then
        print_info "3. Create backup directory:"
        echo "   mkdir -p $N8N_DIR/backups"
        echo ""
    fi
    
    print_info "4. Test the system with a backup:"
    echo "   cd $SCRIPT_DIR"
    echo "   ./manage_n8n.sh backup"
    echo ""
    
    print_info "5. Add to your shell profile for permanent encryption key:"
    echo "   echo 'export N8N_ENCRYPTION_KEY=\"your-key-here\"' >> ~/.bashrc"
    echo "   # or ~/.zshrc for zsh"
    echo ""
}

# Function to show summary
show_summary() {
    print_header "Verification Summary"
    
    echo "Checks completed:"
    print_success "Passed: $CHECKS_PASSED"
    
    if [ $CHECKS_WARNING -gt 0 ]; then
        print_warning "Warnings: $CHECKS_WARNING"
    fi
    
    if [ $CHECKS_FAILED -gt 0 ]; then
        print_error "Failed: $CHECKS_FAILED"
    fi
    
    echo ""
    
    if [ $CHECKS_FAILED -eq 0 ]; then
        if [ $CHECKS_WARNING -eq 0 ]; then
            print_success "✅ Setup verification completed successfully!"
            print_info "Your n8n backup/restore system is ready to use."
        else
            print_warning "⚠️  Setup verification completed with warnings."
            print_info "The system should work, but consider addressing the warnings above."
        fi
    else
        print_error "❌ Setup verification found issues that need to be addressed."
        print_info "Please fix the failed checks before using the system."
    fi
    
    echo ""
    print_info "To get started, run: ./manage_n8n.sh"
}

# Main execution
main() {
    print_header "N8N Backup/Restore System Verification"
    echo "This script will verify that your n8n backup/restore system is properly set up."
    echo ""
    
    check_n8n_installations
    check_script_files
    check_config_files
    check_backup_directory
    check_required_tools
    check_encryption_setup
    check_documentation
    run_basic_test
    show_recommendations
    show_summary
}

# Run main function
main "$@"
