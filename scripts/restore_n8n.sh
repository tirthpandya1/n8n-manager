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
BACKUP_BASE_DIR="${N8N_BACKUP_DIR:-$N8N_DIR/backups}"
NON_INTERACTIVE=false

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
    echo "  --non-interactive   Skip confirmation prompts"
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

# Parse global flags first
while [[ "$1" == --* ]]; do
    case "$1" in
        --non-interactive)
            NON_INTERACTIVE=true
            shift
            ;;
        --help)
            show_usage
            exit 0
            ;;
        *)
            break
            ;;
    esac
done

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
    local backup_key=""
    
    if [ -n "$BACKUP_DIR" ] && [ -f "$BACKUP_DIR/encryption_key.txt" ]; then
        backup_key=$(cat "$BACKUP_DIR/encryption_key.txt" | tr -d '\r\n')
    fi
    
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
    if [ -n "$backup_key" ]; then
        if [ -n "$config_key" ] && [ "$config_key" != "null" ] && [ "$config_key" != "empty" ] && [ "$backup_key" != "$config_key" ]; then
            print_warning "Encryption key in backup differs from config file!"
        fi
        if [ -n "$env_key" ] && [ "$env_key" != "$backup_key" ]; then
            print_warning "Encryption key in backup differs from environment variable!"
        fi
        
        export N8N_ENCRYPTION_KEY="$backup_key"
        print_success "Using encryption key from backup files"
        print_status "Key: ${backup_key:0:8}...${backup_key: -8} (${#backup_key} characters)"
        
    elif [ -n "$config_key" ] && [ "$config_key" != "null" ] && [ "$config_key" != "empty" ]; then
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
        print_warning "No encryption key found. Credentials may not be decrypted correctly."
        print_status "Neither environment variable N8N_ENCRYPTION_KEY nor config file key found"
        if [ ! -f "$config_file" ]; then
            print_status "Config file not found at: $config_file"
        fi
        return 0
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

# Function to detect n8n version and set user ID for v2+
detect_n8n_version_and_user() {
    local n8n_version=""
    local n8n_major_version=""

    # Get n8n version
    if [ "$INSTANCE_TYPE" = "native" ]; then
        n8n_version=$($N8N_CMD --version 2>/dev/null | head -n1)
    else
        n8n_version=$(docker exec "$CONTAINER_NAME" n8n --version 2>/dev/null | head -n1)
    fi

    if [ -z "$n8n_version" ]; then
        print_warning "Could not detect n8n version"
        return 0
    fi

    print_status "Detected n8n version: $n8n_version"

    # Extract major version (first digit before the dot)
    n8n_major_version=$(echo "$n8n_version" | cut -d. -f1)

    # Check if n8n v2 or higher
    if [ "$n8n_major_version" -ge 2 ] 2>/dev/null; then
        print_status "n8n v2+ detected - will use userId parameter for imports"

        local detected_user_id=""
        
        # Strategy 1: Try to pull the first user ID from Postgres if it's a docker setup
        if [ "$INSTANCE_TYPE" = "docker" ]; then
            print_status "Attempting to detect admin user ID from n8n database..."
            # Try to find a postgres container linked to chatwoot/n8n
            local pg_container=$(docker ps --format "{{.Names}}" | grep postgres | head -n 1)
            if [ -n "$pg_container" ]; then
                detected_user_id=$(docker exec "$pg_container" psql -U postgres -d n8n -t -c "SELECT id FROM \"user\" ORDER BY \"createdAt\" ASC LIMIT 1;" 2>/dev/null | tr -d '[:space:]')
            fi
        fi

        if [ -n "$detected_user_id" ] && [[ "$detected_user_id" =~ ^[0-9a-fA-F-] ]]; then
            export N8N_USER_ID="$detected_user_id"
            print_success "Detected active admin user ID: $N8N_USER_ID"
        else
            # Use a default UUID that n8n v2 accepts as a last resort
            export N8N_USER_ID="00000000-0000-0000-0000-000000000000"
            print_warning "Could not detect active user. Using default user ID: $N8N_USER_ID"
            print_status "Note: Import may fail if you haven't created an account in the UI yet."
        fi
    else
        print_status "n8n v1 detected - userId parameter not needed"
    fi
}

# Function to find and extract backup
prepare_backup() {
    local backup_dir=""
    
    # Strip extensions from BACKUP_NAME if present
    CLEAN_BACKUP_NAME=$(echo "$BACKUP_NAME" | sed 's/\.tar\.gz$//' | sed 's/\.zip$//')
    
    local compressed_backup="$BACKUP_BASE_DIR/${CLEAN_BACKUP_NAME}.tar.gz"
    local directory_backup="$BACKUP_BASE_DIR/$CLEAN_BACKUP_NAME"
    # Check if compressed backup exists
    if [ -f "$compressed_backup" ]; then
        print_status "Found compressed backup: $compressed_backup"
        TEMP_EXTRACT_DIR="$BACKUP_BASE_DIR/temp_extract_$$"
        mkdir -p "$TEMP_EXTRACT_DIR"
        
        print_status "Extracting backup..."
        if ! tar -xzf "$compressed_backup" -C "$TEMP_EXTRACT_DIR"; then
            print_error "Extraction failed - check if tar is installed and has permissions"
            exit 1
        fi
        print_success "Extraction complete"
        
        # Check if the backup is in a subdirectory (Linux style) or root (Windows style)
        if [ -d "$TEMP_EXTRACT_DIR/$CLEAN_BACKUP_NAME/workflows" ]; then
            backup_dir="$TEMP_EXTRACT_DIR/$CLEAN_BACKUP_NAME"
        elif [ -d "$TEMP_EXTRACT_DIR/workflows" ]; then
            backup_dir="$TEMP_EXTRACT_DIR"
        else
            print_error "Invalid backup: workflows directory not found in extraction"
            exit 1
        fi
        
    # Check if zip backup exists
    elif [ -f "$BACKUP_BASE_DIR/${CLEAN_BACKUP_NAME}.zip" ]; then
        local zip_backup="$BACKUP_BASE_DIR/${CLEAN_BACKUP_NAME}.zip"
        print_status "Found zip backup: $zip_backup"
        TEMP_EXTRACT_DIR="$BACKUP_BASE_DIR/temp_extract_$$"
        mkdir -p "$TEMP_EXTRACT_DIR"
        
        print_status "Extracting zip backup..."
        if command -v unzip &> /dev/null; then
            unzip -q "$zip_backup" -d "$TEMP_EXTRACT_DIR"
        else
            print_error "unzip command not found. Please install unzip."
            exit 1
        fi
        
        # Check structure
        if [ -d "$TEMP_EXTRACT_DIR/$CLEAN_BACKUP_NAME/workflows" ]; then
            backup_dir="$TEMP_EXTRACT_DIR/$CLEAN_BACKUP_NAME"
        elif [ -d "$TEMP_EXTRACT_DIR/workflows" ]; then
            backup_dir="$TEMP_EXTRACT_DIR"
        else
            print_error "Invalid backup: workflows directory not found in extraction"
            exit 1
        fi
        
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
        
        if [ "$NON_INTERACTIVE" = true ]; then
            print_warning "Proceeding in non-interactive mode without encryption key."
            return 0
        fi
        
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
    if [ "$NON_INTERACTIVE" = true ]; then
        return 0
    fi
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
        set +e
        $N8N_CMD import:credentials --input="$credentials_file"
        import_status=$?
        set -e
        
        if [ $import_status -eq 0 ]; then
            print_success "Credentials imported successfully"
        else
            print_error "Failed to import credentials (exit code: $import_status)"
            echo ""
            print_warning "🚨 RESTORE INCOMPLETE: Credentials failed to import 🚨"
            print_status "If you are migrating to n8n v2+, credentials CANNOT be imported until an owner account is set up."
            print_status "1. Open your n8n interface in the browser"
            print_status "2. Create your initial owner account (this creates the required 'Personal' project)"
            print_status "3. Run this restore script AGAIN to successfully import your credentials."
            echo ""
        fi
    else
        # Copy credentials to container
        docker cp "$credentials_file" "$CONTAINER_NAME:/tmp/credentials_import.json"
        
        # Build import command
        local cmd="n8n import:credentials --input=/tmp/credentials_import.json"
        if [ -n "$N8N_USER_ID" ]; then
            cmd="$cmd --userId=$N8N_USER_ID"
        fi
        
        # Run import and capture status (avoid set -e crash)
        set +e
        docker exec -u node "$CONTAINER_NAME" $cmd
        local import_status=$?
        
        # Cleanup (ignore errors)
        docker exec -u node "$CONTAINER_NAME" rm -f /tmp/credentials_import.json 2>/dev/null || true
        set -e
        
        if [ $import_status -eq 0 ]; then
            print_success "Credentials imported successfully"
        else
            print_error "Failed to import credentials (exit code: $import_status)"
            echo ""
            print_warning "🚨 RESTORE INCOMPLETE: Credentials failed to import 🚨"
            print_status "If you are migrating to n8n v2+, credentials CANNOT be imported until an owner account is set up."
            print_status "1. Open your n8n interface in the browser"
            print_status "2. Create your initial owner account (this creates the required 'Personal' project)"
            print_status "3. Run this restore script AGAIN to successfully import your credentials."
            echo ""
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
        # Build import command
        if [ -n "$N8N_USER_ID" ]; then
            print_status "Importing workflows for n8n v2 with User ID: $N8N_USER_ID"
            local success_count=0
            local fail_count=0
            for wf_file in "$workflows_dir"/*.json; do
                [ -e "$wf_file" ] || continue
                print_status "  Importing $(basename "$wf_file")..."
                set +e
                $N8N_CMD import:workflow --input="$wf_file" --userId="$N8N_USER_ID" > /dev/null 2>&1
                if [ $? -eq 0 ]; then
                    success_count=$((success_count + 1))
                else
                    print_warning "  Failed to import $(basename "$wf_file")"
                    fail_count=$((fail_count + 1))
                fi
                set -e
            done
            print_status "Import summary: $success_count succeeded, $fail_count failed"
            if [ $fail_count -eq 0 ]; then
                print_success "All workflows imported successfully"
            else
                print_warning "Some workflows failed to import. You may need to check node versions."
            fi
        else
            $N8N_CMD import:workflow --separate --input="$workflows_dir"
            if [ $? -eq 0 ]; then
                print_success "Workflows imported successfully"
            else
                print_error "Failed to import workflows"
                return 1
            fi
        fi
    else
        # Copy workflows to container
        docker exec -u node "$CONTAINER_NAME" mkdir -p /tmp/workflows_import
        docker cp "$workflows_dir/." "$CONTAINER_NAME:/tmp/workflows_import/"

        if [ "$n8n_major_version" -ge 2 ] 2>/dev/null && [ -n "$N8N_USER_ID" ]; then
            print_status "Importing workflows for n8n v2 with User ID: $N8N_USER_ID"
            local success_count=0
            local fail_count=0
            
            # Get list of files in the container to loop over
            local container_files=$(docker exec -u node "$CONTAINER_NAME" ls /tmp/workflows_import)
            
            for wf_file in $container_files; do
                [[ "$wf_file" == *.json ]] || continue
                print_status "  Importing $wf_file..."
                set +e
                docker exec -u node "$CONTAINER_NAME" n8n import:workflow --input="/tmp/workflows_import/$wf_file" --userId="$N8N_USER_ID" > /dev/null 2>&1
                if [ $? -eq 0 ]; then
                    success_count=$((success_count + 1))
                else
                    print_warning "  Failed to import $wf_file"
                    fail_count=$((fail_count + 1))
                fi
                set -e
            done
            
            print_status "Import summary: $success_count succeeded, $fail_count failed"
            import_status=$([ $fail_count -eq 0 ] && echo 0 || echo 1)
        else
            # Standard import for v1 or v2 without specific User ID requirements for multiple files
            if [ "$n8n_major_version" -ge 2 ] 2>/dev/null; then
                print_status "Importing workflows for n8n v2..."
            fi
            
            set +e
            docker exec -u node "$CONTAINER_NAME" n8n import:workflow --separate --input=/tmp/workflows_import
            import_status=$?
            set -e
        fi

        # Cleanup (ignore errors)
        docker exec -u node "$CONTAINER_NAME" rm -rf /tmp/workflows_import 2>/dev/null || true
        set -e

        if [ $import_status -eq 0 ]; then
            print_success "Workflows imported successfully"
        else
            if [ "$n8n_major_version" -ge 2 ] 2>/dev/null; then
                print_error "n8n v2 import failed (exit code: $import_status)."
                echo ""
                print_warning "SOLUTION: Import via n8n UI instead:"
                print_status "1. Open your n8n interface"
                print_status "2. Go to Workflows -> Import from File"
                print_status "3. Import from: $workflows_dir"
                echo ""
                print_status "The UI will automatically assign workflows to your user."
            else
                print_error "Failed to import workflows"
            fi
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

    # Migration Tips
    if [ "$n8n_major_version" -ge 2 ] 2>/dev/null; then
        echo ""
        print_status "--- Migration Tips for n8n v2 ---"
        print_status "* Code Nodes: Env vars are BLOCKED by default in v2. Set N8N_BLOCK_ENV_VARS_IN_CODE_NODES=false if needed."
        print_status "* Sub-workflows: Behavior has changed. Test your Execute Workflow nodes."
        print_status "* Ownership: Workflows were assigned to User ID: ${N8N_USER_ID:-[default owner]}"
        print_status "--------------------------------"
    fi
}

# Main execution
main() {
    print_status "N8N Restore Script v1.0.0"
    print_status "=========================="
    
    # Check prerequisites
    prepare_backup
    check_n8n_access
    detect_n8n_version_and_user
    show_backup_info
    check_encryption_key
    
    # Confirm restore
    confirm_restore
    
    # Perform restore
    print_status "Starting restore process..."
    restore_credentials
    print_status "Credentials restore step finished"
    restore_workflows
    print_status "Workflows restore step finished"
    
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
