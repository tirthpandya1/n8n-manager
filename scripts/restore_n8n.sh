#!/bin/bash

# N8N Restore Script
# This script imports workflows and credentials to n8n instances (native or Docker)
# Usage: ./restore_n8n.sh [native|docker] [backup_name] [container_name]

set -e

# Prevent Git Bash path conversion on Windows
export MSYS_NO_PATHCONV=1

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
N8N_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$N8N_DIR/config/n8n_config.json"
BACKUP_BASE_DIR="$N8N_DIR/backups"

# Default values
INSTANCE_TYPE="native"
CONTAINER_NAME="n8n"
BACKUP_NAME=""
TEMP_EXTRACT_DIR=""

# Function to print colored output
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

# Function to show usage
show_usage() {
    echo "Usage: $0 [native|docker] [backup_name] [container_name]"
    echo ""
    echo "Options:"
    echo "  native              Restore to native n8n installation (default)"
    echo "  docker              Restore to Docker n8n container"
    echo "  backup_name         Name of backup to restore (without .tar.gz extension)"
    echo "  container_name      Name of Docker container (default: n8n)"
    echo ""
    echo "Examples:"
    echo "  $0 native native_backup_20240115_143022"
    echo "  $0 docker docker_backup_20240115_143022"
    echo "  $0 docker docker_backup_20240115_143022 my-n8n"
    echo ""
    echo "Available backups:"
    list_available_backups
}

# Function to list available backups
list_available_backups() {
    if [ -d "$BACKUP_BASE_DIR" ]; then
        echo "Compressed backups:"
        ls -la "$BACKUP_BASE_DIR"/*.tar.gz 2>/dev/null | awk '{print "  " $9}' | sed 's|.*/||' | sed 's|\.tar\.gz||' || echo "  No compressed backups found"
        echo "Directory backups:"
        ls -la "$BACKUP_BASE_DIR" 2>/dev/null | grep '^d' | grep backup | awk '{print "  " $9}' || echo "  No directory backups found"
    else
        echo "  No backup directory found"
    fi
}

# Function to cleanup on exit
cleanup() {
    if [ -n "$TEMP_EXTRACT_DIR" ] && [ -d "$TEMP_EXTRACT_DIR" ]; then
        print_status "Cleaning up temporary files..."
        rm -rf "$TEMP_EXTRACT_DIR"
    fi
}

# Set trap for cleanup
trap cleanup EXIT

# Function to select backup interactively
select_backup_interactive() {
    print_status "Looking for available backups..."
    echo ""

    # Get all backup files (compressed and directories)
    local counter=0
    declare -a backups_array

    # Add compressed backups
    if ls "$BACKUP_BASE_DIR"/*.tar.gz >/dev/null 2>&1; then
        for backup in "$BACKUP_BASE_DIR"/*.tar.gz; do
            counter=$((counter + 1))
            local backup_name=$(basename "$backup" .tar.gz)
            backups_array[$counter]="$backup_name"
            echo "[$counter] $backup_name (compressed)"
        done
    fi

    # Add directory backups
    if ls -d "$BACKUP_BASE_DIR"/*_backup_* >/dev/null 2>&1; then
        for backup in "$BACKUP_BASE_DIR"/*_backup_*; do
            if [ -d "$backup" ]; then
                counter=$((counter + 1))
                local backup_name=$(basename "$backup")
                backups_array[$counter]="$backup_name"
                echo "[$counter] $backup_name (directory)"
            fi
        done
    fi

    if [ $counter -eq 0 ]; then
        print_error "No backups found in $BACKUP_BASE_DIR"
        exit 1
    fi

    echo ""
    read -p "Select backup number (1-$counter): " selection

    if [ -z "$selection" ]; then
        print_error "No selection made."
        exit 1
    fi

    if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt "$counter" ]; then
        print_error "Invalid selection."
        exit 1
    fi

    BACKUP_NAME="${backups_array[$selection]}"
    echo ""
    print_status "Selected backup: $BACKUP_NAME"
}

# Parse command line arguments
if [ $# -eq 0 ]; then
    print_error "Missing required arguments"
    show_usage
    exit 1
fi

case $1 in
    native)
        INSTANCE_TYPE="native"
        if [ $# -lt 2 ]; then
            select_backup_interactive
        else
            BACKUP_NAME="$2"
        fi
        ;;
    docker)
        INSTANCE_TYPE="docker"
        if [ $# -ge 2 ]; then
            BACKUP_NAME="$2"
        else
            select_backup_interactive
        fi
        if [ $# -ge 3 ]; then
            CONTAINER_NAME="$3"
        fi
        ;;
    -h|--help)
        show_usage
        exit 0
        ;;
    *)
        print_error "Unknown instance type: $1"
        show_usage
        exit 1
        ;;
esac

if [ -z "$BACKUP_NAME" ]; then
    select_backup_interactive
fi

print_status "Starting n8n restore process..."
print_status "Instance type: $INSTANCE_TYPE"
print_status "Backup name: $BACKUP_NAME"
if [ "$INSTANCE_TYPE" = "docker" ]; then
    print_status "Container name: $CONTAINER_NAME"
fi

# Function to detect and set encryption key
detect_encryption_key() {
    local config_file="$HOME/.n8n/config"
    local config_key=""
    local env_key="$N8N_ENCRYPTION_KEY"
    
    # Always try to read from config file first
    if [ -f "$config_file" ]; then
        print_status "Reading encryption key from n8n config file..."
        
        # Try with jq first (more reliable)
        if command -v jq &> /dev/null; then
            config_key=$(jq -r '.encryptionKey // empty' "$config_file" 2>/dev/null)
        else
            # Fallback: extract key using grep and sed (no jq dependency)
            config_key=$(grep -o '"encryptionKey"[[:space:]]*:[[:space:]]*"[^"]*"' "$config_file" 2>/dev/null | sed 's/.*"encryptionKey"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
        fi
    fi
    
    # Decide which key to use and check for mismatches
    if [ -n "$config_key" ] && [ "$config_key" != "null" ] && [ "$config_key" != "empty" ]; then
        if [ -n "$env_key" ] && [ "$env_key" != "$config_key" ]; then
            print_warning "Encryption key mismatch detected!"
            print_status "Environment key: ${env_key:0:8}...${env_key: -8}"
            print_status "Config file key:  ${config_key:0:8}...${config_key: -8}"
            print_status "Using config file key (authoritative source)"
        fi
        
        export N8N_ENCRYPTION_KEY="$config_key"
        print_success "Using encryption key from config file"
        print_status "Key: ${config_key:0:8}...${config_key: -8} (${#config_key} characters)"
        
    elif [ -n "$env_key" ]; then
        print_warning "No config file key found, using environment variable"
        print_status "Key: ${env_key:0:8}...${env_key: -8} (${#env_key} characters)"
        
    else
        print_error "No encryption key available!"
        print_status "Neither environment variable N8N_ENCRYPTION_KEY nor config file key found"
        if [ ! -f "$config_file" ]; then
            print_status "Config file not found at: $config_file"
            print_status "You may need to run n8n at least once to generate the config"
        fi
        return 1
    fi
}

# Function to detect n8n command
detect_n8n_command() {
    if command -v n8n &> /dev/null; then
        N8N_CMD="n8n"
        print_status "Using globally installed n8n"
    elif command -v npx &> /dev/null && npx n8n --version &> /dev/null 2>&1; then
        N8N_CMD="npx n8n"
        print_status "Using npx n8n"
    else
        print_error "Neither 'n8n' command nor 'npx n8n' is available."
        print_status "Please install n8n globally with: npm install -g n8n"
        print_status "Or ensure you have npx available and n8n package in your project"
        exit 1
    fi
}

# Function to check if n8n is accessible
check_n8n_access() {
    if [ "$INSTANCE_TYPE" = "native" ]; then
        detect_n8n_command
        detect_encryption_key
        print_status "Native n8n installation found: $N8N_CMD"
    else
        # Detect encryption key for Docker instances too
        detect_encryption_key

        # If default container name 'n8n' is used, show selector
        if [ "$CONTAINER_NAME" = "n8n" ]; then
            print_status "Looking for n8n containers..."
            echo ""

            # Get all containers with 'n8n' in the name
            local n8n_containers=$(docker ps -a --format "{{.Names}}" | grep -i n8n)

            if [ -z "$n8n_containers" ]; then
                print_error "No containers with 'n8n' in the name found."
                echo ""
                print_status "All available containers:"
                docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"
                exit 1
            fi

            local container_count=$(echo "$n8n_containers" | wc -l)

            if [ "$container_count" -eq 1 ]; then
                CONTAINER_NAME="$n8n_containers"
                echo ""
                print_status "Only one n8n container found: $CONTAINER_NAME"
                print_status "Using this container..."
            else
                # Display numbered list
                local counter=0
                declare -a containers_array
                while IFS= read -r container; do
                    counter=$((counter + 1))
                    containers_array[$counter]="$container"
                    echo "[$counter] $container"
                done <<< "$n8n_containers"

                echo ""
                read -p "Select container number (1-$counter): " selection

                if [ -z "$selection" ]; then
                    print_error "No selection made."
                    exit 1
                fi

                if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt "$counter" ]; then
                    print_error "Invalid selection."
                    exit 1
                fi

                CONTAINER_NAME="${containers_array[$selection]}"
                echo ""
                print_status "Selected: $CONTAINER_NAME"
            fi
            echo ""
        fi

        # Verify selected container exists
        if ! docker ps -a --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
            print_error "Container '$CONTAINER_NAME' not found."
            print_status "Available containers:"
            docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"
            exit 1
        fi

        # Check if container is running
        if ! docker ps --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
            print_warning "Container '$CONTAINER_NAME' exists but is not running."
            print_status "Starting container..."
            docker start "$CONTAINER_NAME"
            sleep 3
        fi

        print_status "Docker container '$CONTAINER_NAME' is ready"
    fi
}

# Function to find and extract backup
prepare_backup() {
    local backup_dir=""
    local compressed_backup="$BACKUP_BASE_DIR/${BACKUP_NAME}.tar.gz"
    local directory_backup="$BACKUP_BASE_DIR/$BACKUP_NAME"
    
    # Check if compressed backup exists
    if [ -f "$compressed_backup" ]; then
        print_status "Found compressed backup: $compressed_backup"
        TEMP_EXTRACT_DIR="$BACKUP_BASE_DIR/temp_extract_$$"
        mkdir -p "$TEMP_EXTRACT_DIR"
        
        print_status "Extracting backup..."
        tar -xzf "$compressed_backup" -C "$TEMP_EXTRACT_DIR"
        backup_dir="$TEMP_EXTRACT_DIR/$BACKUP_NAME"
        
    # Check if directory backup exists
    elif [ -d "$directory_backup" ]; then
        print_status "Found directory backup: $directory_backup"
        backup_dir="$directory_backup"
        
    else
        print_error "Backup not found: $BACKUP_NAME"
        print_status "Available backups:"
        list_available_backups
        exit 1
    fi
    
    # Verify backup structure
    if [ ! -d "$backup_dir/workflows" ]; then
        print_error "Invalid backup: workflows directory not found"
        exit 1
    fi
    
    BACKUP_DIR="$backup_dir"
    print_success "Backup prepared successfully"
}

# Function to show backup information
show_backup_info() {
    local metadata_file="$BACKUP_DIR/backup_metadata.json"
    
    if [ -f "$metadata_file" ]; then
        print_status "Backup Information:"
        if command -v jq &> /dev/null; then
            echo "  Created: $(jq -r '.backup_info.date' "$metadata_file")"
            echo "  Source: $(jq -r '.backup_info.instance_type' "$metadata_file")"
            echo "  Workflows: $(jq -r '.backup_contents.workflows_count' "$metadata_file")"
            echo "  Size: $(jq -r '.backup_contents.backup_size_mb' "$metadata_file") MB"
        else
            print_status "  (Install jq for detailed backup information)"
        fi
    fi
}

# Function to check encryption key
check_encryption_key() {
    if [ -z "$N8N_ENCRYPTION_KEY" ]; then
        print_warning "N8N_ENCRYPTION_KEY environment variable not set!"
        print_warning "Credentials may not import correctly without the same encryption key."
        print_status "Set the encryption key with: export N8N_ENCRYPTION_KEY='your_key_here'"
        
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_error "Restore cancelled by user"
            exit 1
        fi
    else
        print_success "Encryption key found in environment"
    fi
}

# Function to create confirmation prompt
confirm_restore() {
    print_warning "This will import workflows and credentials to your n8n instance."
    print_warning "Existing workflows with the same names may be overwritten!"
    print_status ""
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_error "Restore cancelled by user"
        exit 1
    fi
}

# Function to restore credentials
restore_credentials() {
    local credentials_file="$BACKUP_DIR/credentials.json"

    if [ ! -f "$credentials_file" ]; then
        print_warning "No credentials file found in backup"
        return 0
    fi

    print_status "Importing credentials..."

    if [ "$INSTANCE_TYPE" = "native" ]; then
        $N8N_CMD import:credentials --input="$credentials_file"
        if [ $? -eq 0 ]; then
            print_success "Credentials imported successfully"
        else
            print_error "Failed to import credentials"
            return 1
        fi
    else
        # Copy credentials to container
        docker cp "$credentials_file" "$CONTAINER_NAME:/tmp/credentials_import.json"
        docker exec -u node "$CONTAINER_NAME" n8n import:credentials --input=/tmp/credentials_import.json
        local import_status=$?

        # Cleanup (ignore errors)
        docker exec -u node "$CONTAINER_NAME" rm -f /tmp/credentials_import.json 2>/dev/null

        if [ $import_status -eq 0 ]; then
            print_success "Credentials imported successfully"
        else
            print_error "Failed to import credentials"
            return 1
        fi
    fi
}

# Function to restore workflows
restore_workflows() {
    local workflows_dir="$BACKUP_DIR/workflows"

    if [ ! -d "$workflows_dir" ] || [ -z "$(ls -A "$workflows_dir")" ]; then
        print_warning "No workflows found in backup"
        return 0
    fi

    local workflow_count=$(find "$workflows_dir" -name "*.json" | wc -l)
    print_status "Importing $workflow_count workflows..."

    if [ "$INSTANCE_TYPE" = "native" ]; then
        $N8N_CMD import:workflow --separate --input="$workflows_dir"
        if [ $? -eq 0 ]; then
            print_success "Workflows imported successfully"
        else
            print_error "Failed to import workflows"
            return 1
        fi
    else
        # Copy workflows to container
        docker exec -u node "$CONTAINER_NAME" mkdir -p /tmp/workflows_import
        docker cp "$workflows_dir/." "$CONTAINER_NAME:/tmp/workflows_import/"
        docker exec -u node "$CONTAINER_NAME" n8n import:workflow --separate --input=/tmp/workflows_import
        local import_status=$?

        # Cleanup (ignore errors)
        docker exec -u node "$CONTAINER_NAME" rm -rf /tmp/workflows_import 2>/dev/null

        if [ $import_status -eq 0 ]; then
            print_success "Workflows imported successfully"
        else
            print_error "Failed to import workflows"
            return 1
        fi
    fi
}

# Function to restart n8n (Docker only)
restart_n8n() {
    if [ "$INSTANCE_TYPE" = "docker" ]; then
        print_status "Restarting n8n container to apply changes..."
        docker restart "$CONTAINER_NAME"
        
        # Wait for container to be ready
        print_status "Waiting for n8n to start..."
        sleep 10
        
        # Check if container is running
        if docker ps --format "table {{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
            print_success "n8n container restarted successfully"
        else
            print_error "Failed to restart n8n container"
            exit 1
        fi
    else
        print_warning "Please restart your native n8n instance to ensure all changes are applied"
    fi
}

# Function to verify restore
verify_restore() {
    print_status "Verifying restore..."
    
    if [ "$INSTANCE_TYPE" = "native" ]; then
        # For native, we can't easily verify without starting n8n
        print_status "Restore completed. Please start n8n and verify your workflows manually."
    else
        # For Docker, we could potentially check the database or API
        print_status "Restore completed. Please check your n8n interface to verify workflows and credentials."
    fi
}

# Main execution
main() {
    print_status "N8N Restore Script v1.0.0"
    print_status "=========================="
    
    # Check prerequisites
    check_n8n_access
    prepare_backup
    show_backup_info
    check_encryption_key
    
    # Confirm restore
    confirm_restore
    
    # Perform restore
    print_status "Starting restore process..."
    restore_credentials
    restore_workflows
    
    # Post-restore actions
    restart_n8n
    verify_restore
    
    print_success "Restore completed successfully!"
    print_status ""
    print_status "Next steps:"
    print_status "1. Open your n8n interface"
    print_status "2. Verify that workflows are present and functional"
    print_status "3. Test credentials by running a workflow"
    print_status "4. Activate workflows as needed"
    
    if [ "$INSTANCE_TYPE" = "native" ]; then
        print_status "5. Start n8n if it's not already running"
    fi
}

# Run main function
main "$@"
