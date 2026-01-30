#!/bin/bash

# N8N Backup Script
# This script exports workflows and credentials from n8n instances (native or Docker)
# Usage: ./backup_n8n.sh [native|docker] [container_name]

set -e

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
BACKUP_BASE_DIR="${N8N_BACKUP_DIR:-$N8N_DIR/backups}"

# Default values
INSTANCE_TYPE="native"
CONTAINER_NAME="n8n"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

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
    echo "Usage: $0 [native|docker] [container_name]"
    echo ""
    echo "Options:"
    echo "  native              Backup from native n8n installation (default)"
    echo "  docker              Backup from Docker n8n container"
    echo "  container_name      Name of Docker container (default: n8n)"
    echo ""
    echo "Examples:"
    echo "  $0                  # Backup from native installation"
    echo "  $0 native           # Backup from native installation"
    echo "  $0 docker           # Backup from Docker container named 'n8n'"
    echo "  $0 docker my-n8n    # Backup from Docker container named 'my-n8n'"
}

# Parse command line arguments
if [ $# -gt 0 ]; then
    case $1 in
        native)
            INSTANCE_TYPE="native"
            ;;
        docker)
            INSTANCE_TYPE="docker"
            if [ $# -gt 1 ]; then
                CONTAINER_NAME="$2"
            fi
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
fi

print_status "Starting n8n backup process..."
print_status "Instance type: $INSTANCE_TYPE"
if [ "$INSTANCE_TYPE" = "docker" ]; then
    print_status "Container name: $CONTAINER_NAME"
fi

# Create backup directory structure
BACKUP_DIR="$BACKUP_BASE_DIR/${INSTANCE_TYPE}_backup_$TIMESTAMP"
WORKFLOWS_BACKUP_DIR="$BACKUP_DIR/workflows"
CREDENTIALS_BACKUP_FILE="$BACKUP_DIR/credentials.json"

mkdir -p "$WORKFLOWS_BACKUP_DIR"
mkdir -p "$(dirname "$CREDENTIALS_BACKUP_FILE")"

print_status "Backup directory: $BACKUP_DIR"

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
        print_warning "No encryption key available on host!"
        print_status "Neither environment variable N8N_ENCRYPTION_KEY nor config file key found"
        
        if [ "$INSTANCE_TYPE" = "docker" ]; then
            print_status "Attempting to detect key from Docker container..."
            docker_key=$(docker exec "$CONTAINER_NAME" printenv N8N_ENCRYPTION_KEY 2>/dev/null || true)
            if [ -n "$docker_key" ]; then
                export N8N_ENCRYPTION_KEY="$docker_key"
                print_success "Using encryption key from Docker container"
                return 0
            fi
        fi

        print_warning "Proceeding without N8N_ENCRYPTION_KEY. Backup might fail if credentials are encrypted."
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
        if [ "$CONTAINER_NAME" = "n8n" ] && [ "$#" -eq 1 ]; then
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

# Function to backup workflows
backup_workflows() {
    print_status "Exporting workflows..."
    
    if [ "$INSTANCE_TYPE" = "native" ]; then
        $N8N_CMD export:workflow --all --separate --output="$WORKFLOWS_BACKUP_DIR"
    else
        # Ensure clean state in container
        docker exec -u node "$CONTAINER_NAME" rm -rf /tmp/workflows_export || true
        docker exec -u node "$CONTAINER_NAME" mkdir -p /tmp/workflows_export
        
        # Export to container path
        docker exec -u node "$CONTAINER_NAME" n8n export:workflow --all --separate --output="/tmp/workflows_export"
        
        # Verify export
        FILE_COUNT=$(docker exec -u node "$CONTAINER_NAME" sh -c "ls -1 /tmp/workflows_export | wc -l")
        print_status "Found $FILE_COUNT files in export directory container"

        if [ "$FILE_COUNT" -eq 0 ]; then
             print_warning "No workflows exported! Check n8n logs or database."
        else
             # Copy from container to host
             docker cp "$CONTAINER_NAME:/tmp/workflows_export/." "$WORKFLOWS_BACKUP_DIR/"
        fi
        
        # Cleanup
        docker exec -u node "$CONTAINER_NAME" rm -rf /tmp/workflows_export
    fi
    
    WORKFLOW_COUNT=$(find "$WORKFLOWS_BACKUP_DIR" -name "*.json" | wc -l)
    print_success "Exported $WORKFLOW_COUNT workflows"
}

# Function to backup credentials
backup_credentials() {
    print_status "Exporting credentials..."
    
    if [ "$INSTANCE_TYPE" = "native" ]; then
        $N8N_CMD export:credentials --all --decrypted --output="$CREDENTIALS_BACKUP_FILE" || true
    else
        docker exec -u node "$CONTAINER_NAME" n8n export:credentials --all --decrypted --output="/tmp/credentials_export.json" || true
        docker cp "$CONTAINER_NAME:/tmp/credentials_export.json" "$CREDENTIALS_BACKUP_FILE" || true
        docker exec -u node "$CONTAINER_NAME" rm -f /tmp/credentials_export.json || true
    fi
    
    if [ -f "$CREDENTIALS_BACKUP_FILE" ]; then
        CREDENTIAL_COUNT=$(jq length "$CREDENTIALS_BACKUP_FILE" 2>/dev/null || echo "unknown")
        print_success "Exported $CREDENTIAL_COUNT credentials"
    else
        print_warning "No credentials file created (possibly no credentials to export)"
    fi
}

# Function to create backup metadata
create_backup_metadata() {
    local metadata_file="$BACKUP_DIR/backup_metadata.json"
    
    cat > "$metadata_file" << EOF
{
  "backup_info": {
    "timestamp": "$TIMESTAMP",
    "date": "$(date -Iseconds)",
    "instance_type": "$INSTANCE_TYPE",
    "container_name": "$CONTAINER_NAME",
    "script_version": "1.0.0"
  },
  "backup_contents": {
    "workflows_count": $(find "$WORKFLOWS_BACKUP_DIR" -name "*.json" | wc -l),
    "credentials_file_exists": $([ -f "$CREDENTIALS_BACKUP_FILE" ] && echo "true" || echo "false"),
    "backup_size_mb": "$(du -sm "$BACKUP_DIR" | cut -f1)"
  },
  "restoration_notes": {
    "encryption_key_required": true,
    "compatible_with": ["native", "docker"],
    "restore_command": "./restore_n8n.sh $INSTANCE_TYPE $(basename "$BACKUP_DIR")"
  }
}
EOF
    
    print_status "Created backup metadata"
}

# Function to compress backup (optional)
compress_backup() {
    if command -v tar &> /dev/null; then
        print_status "Compressing backup..."
        cd "$BACKUP_BASE_DIR"
        tar -czf "${INSTANCE_TYPE}_backup_$TIMESTAMP.tar.gz" "$(basename "$BACKUP_DIR")"
        rm -rf "$BACKUP_DIR"
        print_success "Backup compressed to: ${INSTANCE_TYPE}_backup_$TIMESTAMP.tar.gz"
    else
        print_warning "tar command not available, backup left uncompressed"
    fi
}

# Function to cleanup old backups
cleanup_old_backups() {
    print_status "Cleaning up old backups..."
    
    # Keep only the 10 most recent backups
    cd "$BACKUP_BASE_DIR"
    ls -t ${INSTANCE_TYPE}_backup_*.tar.gz 2>/dev/null | tail -n +11 | xargs -r rm -f
    ls -td ${INSTANCE_TYPE}_backup_* 2>/dev/null | tail -n +11 | xargs -r rm -rf
    
    print_status "Cleanup completed"
}

# Main execution
main() {
    print_status "N8N Backup Script v1.0.0"
    print_status "========================="

    # Check prerequisites
    check_n8n_access "$#"

    # Perform backup
    backup_workflows
    backup_credentials
    create_backup_metadata

    # Post-processing
    compress_backup
    cleanup_old_backups

    print_success "Backup completed successfully!"
    print_status "Backup location: $BACKUP_BASE_DIR"

    if [ -f "$BACKUP_BASE_DIR/${INSTANCE_TYPE}_backup_$TIMESTAMP.tar.gz" ]; then
        print_status "Compressed backup: ${INSTANCE_TYPE}_backup_$TIMESTAMP.tar.gz"
    fi

    echo ""
    print_status "To restore this backup on another instance, use:"
    print_status "./restore_n8n.sh [native|docker] ${INSTANCE_TYPE}_backup_$TIMESTAMP"
}

# Trap to handle script interruption
trap 'print_error "Backup interrupted!"; exit 1' INT TERM

# Run main function
main "$@"
