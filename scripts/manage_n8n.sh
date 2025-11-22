#!/bin/bash

# N8N Management Script
# This script provides a unified interface for managing n8n backups and restores
# Usage: ./manage_n8n.sh [command] [options]

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

# Function to print colored output
print_header() {
    echo -e "${CYAN}================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}================================${NC}"
}

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

# Function to show main menu
show_main_menu() {
    print_header "N8N Backup & Restore Manager v1.0.0"
    echo ""
    echo "Available commands:"
    echo ""
    echo "  backup          Create backups"
    echo "  restore         Restore from backups"
    echo "  list            List available backups"
    echo "  status          Check n8n status"
    echo "  config          Configuration management"
    echo "  cleanup         Clean up old backups"
    echo "  help            Show this help message"
    echo ""
    echo "Usage: $0 [command] [options]"
    echo ""
    echo "Examples:"
    echo "  $0 backup                    # Interactive backup menu"
    echo "  $0 restore                   # Interactive restore menu"
    echo "  $0 list                      # List all backups"
    echo "  $0 status                    # Check n8n instances"
    echo ""
}

# Function to show backup menu
show_backup_menu() {
    print_header "N8N Backup Options"
    echo ""
    echo "1) Native n8n backup (Mac/Linux)"
    echo "2) Docker n8n backup (basic)"
    echo "3) Docker n8n backup (enhanced with volumes)"
    echo "4) Back to main menu"
    echo ""
    read -p "Select an option (1-4): " choice
    
    case $choice in
        1)
            print_status "Starting native n8n backup..."
            "$SCRIPT_DIR/backup_n8n.sh" native
            ;;
        2)
            read -p "Enter container name (default: n8n): " container_name
            container_name=${container_name:-n8n}
            print_status "Starting Docker n8n backup for container: $container_name"
            "$SCRIPT_DIR/backup_n8n.sh" docker "$container_name"
            ;;
        3)
            read -p "Enter container name (default: n8n): " container_name
            container_name=${container_name:-n8n}
            print_status "Starting enhanced Docker n8n backup for container: $container_name"
            "$SCRIPT_DIR/docker_backup.sh" "$container_name" --include-volumes --include-logs
            ;;
        4)
            return 0
            ;;
        *)
            print_error "Invalid option"
            show_backup_menu
            ;;
    esac
}

# Function to show restore menu
show_restore_menu() {
    print_header "N8N Restore Options"
    echo ""
    echo "Available backups:"
    list_backups_simple
    echo ""
    echo "1) Restore to native n8n"
    echo "2) Restore to Docker n8n (basic)"
    echo "3) Restore to Docker n8n (enhanced)"
    echo "4) Back to main menu"
    echo ""
    read -p "Select an option (1-4): " choice
    
    case $choice in
        1)
            read -p "Enter backup name: " backup_name
            if [ -n "$backup_name" ]; then
                print_status "Starting native n8n restore..."
                "$SCRIPT_DIR/restore_n8n.sh" native "$backup_name"
            else
                print_error "Backup name required"
            fi
            ;;
        2)
            read -p "Enter backup name: " backup_name
            read -p "Enter container name (default: n8n): " container_name
            container_name=${container_name:-n8n}
            if [ -n "$backup_name" ]; then
                print_status "Starting Docker n8n restore..."
                "$SCRIPT_DIR/restore_n8n.sh" docker "$backup_name" "$container_name"
            else
                print_error "Backup name required"
            fi
            ;;
        3)
            read -p "Enter enhanced backup name: " backup_name
            read -p "Enter container name (default: n8n): " container_name
            container_name=${container_name:-n8n}
            read -p "Recreate container from backup? (y/N): " recreate
            
            if [ -n "$backup_name" ]; then
                print_status "Starting enhanced Docker n8n restore..."
                if [[ $recreate =~ ^[Yy]$ ]]; then
                    "$SCRIPT_DIR/docker_restore.sh" "$backup_name" "$container_name" --recreate-container
                else
                    "$SCRIPT_DIR/docker_restore.sh" "$backup_name" "$container_name"
                fi
            else
                print_error "Backup name required"
            fi
            ;;
        4)
            return 0
            ;;
        *)
            print_error "Invalid option"
            show_restore_menu
            ;;
    esac
}

# Function to list backups (simple format)
list_backups_simple() {
    local backup_dir="$N8N_DIR/backups"
    if [ -d "$backup_dir" ]; then
        echo "Standard backups:"
        ls -1 "$backup_dir"/*backup_*.tar.gz 2>/dev/null | sed 's|.*/||' | sed 's|\.tar\.gz||' | head -5 || echo "  None found"
        echo ""
        echo "Enhanced backups:"
        ls -1 "$backup_dir"/docker_enhanced_backup_*.tar.gz 2>/dev/null | sed 's|.*/||' | sed 's|\.tar\.gz||' | head -5 || echo "  None found"
    else
        echo "  No backup directory found"
    fi
}

# Function to list all backups with details
list_all_backups() {
    print_header "Available N8N Backups"
    local backup_dir="$N8N_DIR/backups"
    
    if [ ! -d "$backup_dir" ]; then
        print_warning "No backup directory found at: $backup_dir"
        return 1
    fi
    
    echo ""
    print_status "Standard Backups:"
    if ls "$backup_dir"/*backup_*.tar.gz >/dev/null 2>&1; then
        ls -lah "$backup_dir"/*backup_*.tar.gz | awk '{print "  " $9 " (" $5 ", " $6 " " $7 " " $8 ")"}' | sed 's|.*/||'
    else
        echo "  No standard backups found"
    fi
    
    echo ""
    print_status "Enhanced Docker Backups:"
    if ls "$backup_dir"/docker_enhanced_backup_*.tar.gz >/dev/null 2>&1; then
        ls -lah "$backup_dir"/docker_enhanced_backup_*.tar.gz | awk '{print "  " $9 " (" $5 ", " $6 " " $7 " " $8 ")"}' | sed 's|.*/||'
    else
        echo "  No enhanced backups found"
    fi
    
    echo ""
    print_status "Directory Backups (Uncompressed):"
    if ls -d "$backup_dir"/*backup_* >/dev/null 2>&1; then
        ls -lah "$backup_dir" | grep '^d' | grep backup | awk '{print "  " $9 " (directory, " $6 " " $7 " " $8 ")"}'
    else
        echo "  No directory backups found"
    fi
    
    echo ""
    local total_size=$(du -sh "$backup_dir" 2>/dev/null | cut -f1)
    print_status "Total backup storage used: $total_size"
}

# Function to check n8n status
check_n8n_status() {
    print_header "N8N Status Check"
    echo ""
    
    # Check native n8n
    print_status "Native n8n:"
    if command -v n8n &> /dev/null; then
        local version=$(n8n --version 2>/dev/null | head -n1)
        print_success "  Globally installed: $version"
        
        if pgrep -f "n8n" > /dev/null; then
            print_success "  Status: Running"
        else
            print_warning "  Status: Not running"
        fi
    elif command -v npx &> /dev/null && npx n8n --version &> /dev/null 2>&1; then
        local version=$(npx n8n --version 2>/dev/null | head -n1)
        print_success "  Available via npx: $version"
        
        if pgrep -f "npx n8n\|n8n" > /dev/null; then
            print_success "  Status: Running"
        else
            print_warning "  Status: Not running"
        fi
    else
        print_warning "  Not available (neither 'n8n' command nor 'npx n8n')"
        print_status "  Install with: npm install -g n8n"
        print_status "  Or ensure npx and n8n package are available"
    fi
    
    echo ""
    print_status "Docker n8n containers:"
    if command -v docker &> /dev/null; then
        # Check for containers with n8n in the name (more flexible)
        local n8n_containers=$(docker ps -a --format "{{.Names}}\t{{.Status}}\t{{.Image}}" | grep -i n8n 2>/dev/null)
        if [ -n "$n8n_containers" ]; then
            echo "  NAMES               STATUS              IMAGE"
            echo "$n8n_containers" | while IFS= read -r line; do
                echo "  $line"
            done
        else
            print_warning "  No containers with 'n8n' in name found"
        fi
        
        # Also check by n8n image
        echo ""
        print_status "Containers using n8n image:"
        local n8n_image_containers=$(docker ps -a --filter "ancestor=n8nio/n8n" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null)
        if [ -n "$n8n_image_containers" ]; then
            echo "$n8n_image_containers" | while IFS= read -r line; do
                echo "  $line"
            done
        else
            print_warning "  No containers using n8nio/n8n image found"
        fi
    else
        print_warning "  Docker not available"
    fi
}

# Function to show configuration menu
show_config_menu() {
    print_header "N8N Configuration Management"
    echo ""
    echo "1) Show current configuration"
    echo "2) Check encryption key setup"
    echo "3) Generate new encryption key"
    echo "4) Show configuration examples"
    echo "5) Back to main menu"
    echo ""
    read -p "Select an option (1-5): " choice
    
    case $choice in
        1)
            show_current_config
            ;;
        2)
            check_encryption_setup
            ;;
        3)
            generate_encryption_key
            ;;
        4)
            show_config_examples
            ;;
        5)
            return 0
            ;;
        *)
            print_error "Invalid option"
            show_config_menu
            ;;
    esac
}

# Function to show current configuration
show_current_config() {
    print_status "Current Configuration:"
    echo ""
    
    if [ -n "$N8N_ENCRYPTION_KEY" ]; then
        print_success "Encryption key: Set (${#N8N_ENCRYPTION_KEY} characters)"
    else
        print_warning "Encryption key: Not set"
    fi
    
    echo ""
    print_status "Configuration files:"
    ls -la "$N8N_DIR/config/" 2>/dev/null || print_warning "No config directory found"
}

# Function to check encryption setup
check_encryption_setup() {
    print_status "Checking encryption key setup..."
    echo ""
    
    if [ -n "$N8N_ENCRYPTION_KEY" ]; then
        print_success "Environment variable N8N_ENCRYPTION_KEY is set"
        print_status "Key length: ${#N8N_ENCRYPTION_KEY} characters"
        
        if [ ${#N8N_ENCRYPTION_KEY} -eq 32 ]; then
            print_success "Key length is correct (32 characters)"
        else
            print_warning "Key length should be 32 characters for optimal security"
        fi
    else
        print_error "N8N_ENCRYPTION_KEY environment variable is not set"
        echo ""
        print_status "To set the encryption key:"
        echo "  export N8N_ENCRYPTION_KEY='your-32-character-key-here'"
        echo ""
        print_status "Or generate a new one with option 3"
    fi
}

# Function to generate encryption key
generate_encryption_key() {
    print_status "Generating new encryption key..."
    echo ""
    
    if command -v openssl &> /dev/null; then
        local new_key=$(openssl rand -hex 16)
        print_success "Generated encryption key: $new_key"
        echo ""
        print_status "To use this key, run:"
        echo "  export N8N_ENCRYPTION_KEY='$new_key'"
        echo ""
        print_warning "IMPORTANT: Save this key securely! You'll need it for all n8n instances."
    elif command -v node &> /dev/null; then
        local new_key=$(node -e "console.log(require('crypto').randomBytes(16).toString('hex'))")
        print_success "Generated encryption key: $new_key"
        echo ""
        print_status "To use this key, run:"
        echo "  export N8N_ENCRYPTION_KEY='$new_key'"
        echo ""
        print_warning "IMPORTANT: Save this key securely! You'll need it for all n8n instances."
    else
        print_error "Neither openssl nor node.js available for key generation"
        print_status "Please install one of these tools or generate a key manually"
    fi
}

# Function to show configuration examples
show_config_examples() {
    print_status "Configuration examples:"
    echo ""
    cat "$N8N_DIR/config/encryption_key_example.txt" 2>/dev/null || print_error "Example file not found"
}

# Function to cleanup old backups
cleanup_old_backups() {
    print_header "Cleanup Old Backups"
    echo ""
    
    local backup_dir="$N8N_DIR/backups"
    if [ ! -d "$backup_dir" ]; then
        print_warning "No backup directory found"
        return 1
    fi
    
    print_status "Current backup storage:"
    du -sh "$backup_dir"
    echo ""
    
    print_status "Backup files older than 30 days:"
    find "$backup_dir" -name "*.tar.gz" -mtime +30 -ls 2>/dev/null || print_status "None found"
    
    echo ""
    read -p "Delete backups older than 30 days? (y/N): " confirm
    
    if [[ $confirm =~ ^[Yy]$ ]]; then
        local deleted_count=$(find "$backup_dir" -name "*.tar.gz" -mtime +30 -delete -print | wc -l)
        print_success "Deleted $deleted_count old backup files"
        
        # Also clean up old directories
        find "$backup_dir" -type d -name "*backup_*" -mtime +30 -exec rm -rf {} + 2>/dev/null || true
        
        echo ""
        print_status "Storage after cleanup:"
        du -sh "$backup_dir"
    else
        print_status "Cleanup cancelled"
    fi
}

# Main function
main() {
    case "${1:-}" in
        backup)
            show_backup_menu
            ;;
        restore)
            show_restore_menu
            ;;
        list)
            list_all_backups
            ;;
        status)
            check_n8n_status
            ;;
        config)
            show_config_menu
            ;;
        cleanup)
            cleanup_old_backups
            ;;
        help|--help|-h)
            show_main_menu
            ;;
        "")
            show_main_menu
            ;;
        *)
            print_error "Unknown command: $1"
            echo ""
            show_main_menu
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"
