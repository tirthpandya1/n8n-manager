#!/bin/bash

# Remote N8N Backup Transfer Script
# This script backs up n8n from a source server and restores it to a destination server
# Supports both native and Docker installations
# Usage: ./remote_backup_transfer.sh [options]
# Options:
#   --source-host HOST          Source server (user@host)
#   --dest-host HOST            Destination server (user@host)
#   --password PASSWORD         SSH password for both servers
#   --source-password PASSWORD  SSH password for source server
#   --dest-password PASSWORD    SSH password for destination server

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SOURCE_HOST="${SOURCE_HOST:-}"
DEST_HOST="${DEST_HOST:-}"
SSH_PASSWORD="${SSH_PASSWORD:-}"
SOURCE_PASSWORD="${SOURCE_PASSWORD:-}"
DEST_PASSWORD="${DEST_PASSWORD:-}"
SOURCE_INSTANCE_TYPE=""
DEST_INSTANCE_TYPE=""
SOURCE_CONTAINER=""
DEST_CONTAINER=""
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_NAME="n8n_backup_${TIMESTAMP}"
TEMP_DIR="/tmp/${BACKUP_NAME}"

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
    cat << EOF
Usage: $0 [options]

This script backs up n8n from a source server and restores it to a destination server.
Supports both native and Docker installations.

Options:
  --source-host HOST          Source server (format: user@host or host)
  --dest-host HOST            Destination server (format: user@host or host)
  --password PASSWORD         SSH password for both servers (if same)
  --source-password PASSWORD  SSH password for source server only
  --dest-password PASSWORD    SSH password for destination server only
  -h, --help                  Show this help message

Environment Variables:
  SOURCE_HOST                 Source server address
  DEST_HOST                   Destination server address
  SSH_PASSWORD                Password for both servers
  SOURCE_PASSWORD             Password for source server
  DEST_PASSWORD               Password for destination server

Examples:
  $0 --source-host root@192.168.1.10 --dest-host root@192.168.1.20 --password mypass
  $0 --source-host 192.168.1.10 --dest-host 192.168.1.20 --source-password pass1 --dest-password pass2
  SOURCE_HOST=root@server1 DEST_HOST=root@server2 SSH_PASSWORD=mypass $0

EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --source-host)
                SOURCE_HOST="$2"
                shift 2
                ;;
            --dest-host)
                DEST_HOST="$2"
                shift 2
                ;;
            --password)
                SSH_PASSWORD="$2"
                SOURCE_PASSWORD="$2"
                DEST_PASSWORD="$2"
                shift 2
                ;;
            --source-password)
                SOURCE_PASSWORD="$2"
                shift 2
                ;;
            --dest-password)
                DEST_PASSWORD="$2"
                shift 2
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
    done
}

# Function to prompt for missing configuration
prompt_for_config() {
    echo ""
    print_status "Configuration Setup"
    print_status "==================="
    echo ""

    # Source host
    if [ -z "$SOURCE_HOST" ]; then
        read -p "Enter source server (user@host): " SOURCE_HOST
        if [ -z "$SOURCE_HOST" ]; then
            print_error "Source host is required"
            exit 1
        fi
    fi

    # Destination host
    if [ -z "$DEST_HOST" ]; then
        read -p "Enter destination server (user@host): " DEST_HOST
        if [ -z "$DEST_HOST" ]; then
            print_error "Destination host is required"
            exit 1
        fi
    fi

    # Passwords
    if [ -z "$SOURCE_PASSWORD" ] && [ -z "$SSH_PASSWORD" ]; then
        read -s -p "Enter SSH password for source server: " SOURCE_PASSWORD
        echo ""
        if [ -z "$SOURCE_PASSWORD" ]; then
            print_error "Source password is required"
            exit 1
        fi
    elif [ -z "$SOURCE_PASSWORD" ]; then
        SOURCE_PASSWORD="$SSH_PASSWORD"
    fi

    if [ -z "$DEST_PASSWORD" ] && [ -z "$SSH_PASSWORD" ]; then
        read -s -p "Enter SSH password for destination server: " DEST_PASSWORD
        echo ""
        if [ -z "$DEST_PASSWORD" ]; then
            print_error "Destination password is required"
            exit 1
        fi
    elif [ -z "$DEST_PASSWORD" ]; then
        DEST_PASSWORD="$SSH_PASSWORD"
    fi

    print_success "Configuration complete"
    echo ""
}

# Function to run SSH command with password
ssh_cmd() {
    local host=$1
    local password=""
    shift

    # Determine which password to use
    if [ "$host" = "$SOURCE_HOST" ]; then
        password="$SOURCE_PASSWORD"
    elif [ "$host" = "$DEST_HOST" ]; then
        password="$DEST_PASSWORD"
    else
        password="${SSH_PASSWORD:-$SOURCE_PASSWORD}"
    fi

    sshpass -p "$password" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$host" "$@"
}

# Function to run SCP with password
scp_cmd() {
    local source="$1"
    local dest="$2"
    local password=""

    # Determine which password to use based on which host is in the command
    # Check if source contains SOURCE_HOST or DEST_HOST
    if [[ "$source" == *"${SOURCE_HOST}"* ]] || [[ "$source" == "${SOURCE_HOST}:"* ]]; then
        password="$SOURCE_PASSWORD"
    elif [[ "$source" == *"${DEST_HOST}"* ]] || [[ "$source" == "${DEST_HOST}:"* ]]; then
        password="$DEST_PASSWORD"
    # Check if dest contains SOURCE_HOST or DEST_HOST
    elif [[ "$dest" == *"${SOURCE_HOST}"* ]] || [[ "$dest" == "${SOURCE_HOST}:"* ]]; then
        password="$SOURCE_PASSWORD"
    elif [[ "$dest" == *"${DEST_HOST}"* ]] || [[ "$dest" == "${DEST_HOST}:"* ]]; then
        password="$DEST_PASSWORD"
    else
        # Default to source password
        password="$SOURCE_PASSWORD"
    fi

    sshpass -p "$password" scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$source" "$dest"
}

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."

    if ! command -v sshpass &> /dev/null; then
        print_error "sshpass is not installed"
        print_status "Install it using:"
        print_status "  macOS: brew install hudochenkov/sshpass/sshpass"
        print_status "  Linux: sudo apt-get install sshpass"
        exit 1
    fi

    print_success "Prerequisites check passed"
}

# Function to test SSH connectivity
test_ssh_connectivity() {
    print_status "Testing SSH connectivity to source server ($SOURCE_HOST)..."
    if ssh_cmd "$SOURCE_HOST" "echo 'Connection successful'" &>/dev/null; then
        print_success "Connected to source server"
    else
        print_error "Failed to connect to source server"
        exit 1
    fi

    print_status "Testing SSH connectivity to destination server ($DEST_HOST)..."
    if ssh_cmd "$DEST_HOST" "echo 'Connection successful'" &>/dev/null; then
        print_success "Connected to destination server"
    else
        print_error "Failed to connect to destination server"
        exit 1
    fi
}

# Function to detect n8n containers on remote server
detect_n8n_containers() {
    local host=$1
    local containers=$(ssh_cmd "$host" "docker ps -a --format '{{.Names}}' 2>/dev/null | grep -i n8n" || echo "")
    echo "$containers"
}

# Function to check if n8n is installed natively on remote server
check_native_n8n() {
    local host=$1
    ssh_cmd "$host" "command -v n8n >/dev/null 2>&1" && echo "true" || echo "false"
}

# Function to ask user about source installation
configure_source() {
    print_status "=== Configuring SOURCE Server ($SOURCE_HOST) ==="
    echo ""

    # Check for Docker containers with n8n
    local n8n_containers=$(detect_n8n_containers "$SOURCE_HOST")
    local has_native=$(check_native_n8n "$SOURCE_HOST")

    if [ -n "$n8n_containers" ]; then
        print_status "Found Docker containers with 'n8n' in name:"
        echo "$n8n_containers" | while read -r container; do
            local status=$(ssh_cmd "$SOURCE_HOST" "docker inspect --format='{{.State.Status}}' '$container' 2>/dev/null" || echo "unknown")
            echo "  - $container ($status)"
        done
        echo ""
    fi

    if [ "$has_native" = "true" ]; then
        print_status "Native n8n installation detected"
        echo ""
    fi

    # Ask user for installation type
    echo "Is n8n installed as:"
    echo "  1) Docker container"
    echo "  2) Native installation"
    echo ""
    read -p "Select option (1 or 2): " -n 1 -r source_option
    echo ""

    if [ "$source_option" = "1" ]; then
        SOURCE_INSTANCE_TYPE="docker"

        if [ -n "$n8n_containers" ]; then
            local container_count=$(echo "$n8n_containers" | wc -l | tr -d ' ')

            if [ "$container_count" -eq 1 ]; then
                SOURCE_CONTAINER=$(echo "$n8n_containers" | tr -d '[:space:]')
                print_status "Auto-selected container: $SOURCE_CONTAINER"
                echo ""
                read -p "Use this container? (Y/n): " -n 1 -r confirm
                echo ""

                if [[ $confirm =~ ^[Nn]$ ]]; then
                    read -p "Enter container name: " SOURCE_CONTAINER
                fi
            else
                echo "Multiple n8n containers found. Select one:"
                local i=1
                local -a container_array
                while IFS= read -r container; do
                    container_array[$i]="$container"
                    echo "  $i) $container"
                    ((i++))
                done <<< "$n8n_containers"
                echo "  0) Enter custom name"
                echo ""
                read -p "Select container (0-$((i-1))): " -n 1 -r container_choice
                echo ""

                if [ "$container_choice" -eq 0 ]; then
                    read -p "Enter container name: " SOURCE_CONTAINER
                else
                    SOURCE_CONTAINER="${container_array[$container_choice]}"
                fi
            fi
        else
            read -p "Enter Docker container name: " SOURCE_CONTAINER
        fi

        print_success "Source: Docker container '$SOURCE_CONTAINER'"
    elif [ "$source_option" = "2" ]; then
        SOURCE_INSTANCE_TYPE="native"
        print_success "Source: Native installation"
    else
        print_error "Invalid option"
        exit 1
    fi
    echo ""
}

# Function to ask user about destination installation
configure_destination() {
    print_status "=== Configuring DESTINATION Server ($DEST_HOST) ==="
    echo ""

    # Check for Docker containers with n8n
    local n8n_containers=$(detect_n8n_containers "$DEST_HOST")
    local has_native=$(check_native_n8n "$DEST_HOST")

    if [ -n "$n8n_containers" ]; then
        print_status "Found Docker containers with 'n8n' in name:"
        echo "$n8n_containers" | while read -r container; do
            local status=$(ssh_cmd "$DEST_HOST" "docker inspect --format='{{.State.Status}}' '$container' 2>/dev/null" || echo "unknown")
            echo "  - $container ($status)"
        done
        echo ""
    fi

    if [ "$has_native" = "true" ]; then
        print_status "Native n8n installation detected"
        echo ""
    fi

    # Ask user for installation type
    echo "Is n8n installed as:"
    echo "  1) Docker container"
    echo "  2) Native installation"
    echo ""
    read -p "Select option (1 or 2): " -n 1 -r dest_option
    echo ""

    if [ "$dest_option" = "1" ]; then
        DEST_INSTANCE_TYPE="docker"

        if [ -n "$n8n_containers" ]; then
            local container_count=$(echo "$n8n_containers" | wc -l | tr -d ' ')

            if [ "$container_count" -eq 1 ]; then
                DEST_CONTAINER=$(echo "$n8n_containers" | tr -d '[:space:]')
                print_status "Auto-selected container: $DEST_CONTAINER"
                echo ""
                read -p "Use this container? (Y/n): " -n 1 -r confirm
                echo ""

                if [[ $confirm =~ ^[Nn]$ ]]; then
                    read -p "Enter container name: " DEST_CONTAINER
                fi
            else
                echo "Multiple n8n containers found. Select one:"
                local i=1
                local -a container_array
                while IFS= read -r container; do
                    container_array[$i]="$container"
                    echo "  $i) $container"
                    ((i++))
                done <<< "$n8n_containers"
                echo "  0) Enter custom name"
                echo ""
                read -p "Select container (0-$((i-1))): " -n 1 -r container_choice
                echo ""

                if [ "$container_choice" -eq 0 ]; then
                    read -p "Enter container name: " DEST_CONTAINER
                else
                    DEST_CONTAINER="${container_array[$container_choice]}"
                fi
            fi
        else
            read -p "Enter Docker container name: " DEST_CONTAINER
        fi

        print_success "Destination: Docker container '$DEST_CONTAINER'"
    elif [ "$dest_option" = "2" ]; then
        DEST_INSTANCE_TYPE="native"
        print_success "Destination: Native installation"
    else
        print_error "Invalid option"
        exit 1
    fi
    echo ""
}

# Function to verify source n8n installation
verify_source() {
    print_status "Verifying source n8n installation..."

    if [ "$SOURCE_INSTANCE_TYPE" = "docker" ]; then
        if ! ssh_cmd "$SOURCE_HOST" "docker ps -a --format '{{.Names}}' | grep -q '^${SOURCE_CONTAINER}$'"; then
            print_error "Container '$SOURCE_CONTAINER' not found on source server"
            exit 1
        fi

        local status=$(ssh_cmd "$SOURCE_HOST" "docker inspect --format='{{.State.Status}}' '$SOURCE_CONTAINER'")
        print_status "Source container status: $status"

        if [ "$status" != "running" ]; then
            print_warning "Source container is not running. Backup may be incomplete."
            read -p "Continue anyway? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 1
            fi
        fi
    else
        if ! ssh_cmd "$SOURCE_HOST" "command -v n8n >/dev/null 2>&1"; then
            print_error "n8n command not found on source server"
            exit 1
        fi
        print_status "Native n8n installation verified"
    fi
}

# Function to verify destination n8n installation
verify_destination() {
    print_status "Verifying destination n8n installation..."

    if [ "$DEST_INSTANCE_TYPE" = "docker" ]; then
        if ! ssh_cmd "$DEST_HOST" "docker ps -a --format '{{.Names}}' | grep -q '^${DEST_CONTAINER}$'"; then
            print_error "Container '$DEST_CONTAINER' not found on destination server"
            exit 1
        fi

        local status=$(ssh_cmd "$DEST_HOST" "docker inspect --format='{{.State.Status}}' '$DEST_CONTAINER'")
        print_status "Destination container status: $status"
    else
        if ! ssh_cmd "$DEST_HOST" "command -v n8n >/dev/null 2>&1"; then
            print_error "n8n command not found on destination server"
            exit 1
        fi
        print_status "Native n8n installation verified"
    fi
}

# Function to create backup on source server
create_backup_on_source() {
    print_status "Creating backup on source server..."

    # Create temporary directory on source host
    ssh_cmd "$SOURCE_HOST" "mkdir -p $TEMP_DIR"

    if [ "$SOURCE_INSTANCE_TYPE" = "docker" ]; then
        # Export workflows from Docker container
        print_status "Exporting workflows from Docker container..."

        # Export to /tmp inside container (which always exists)
        ssh_cmd "$SOURCE_HOST" "docker exec -u node '$SOURCE_CONTAINER' n8n export:workflow --all --separate --output=/tmp/workflows_export" || {
            print_error "Failed to export workflows"
            ssh_cmd "$SOURCE_HOST" "rm -rf $TEMP_DIR"
            exit 1
        }

        # Copy workflows from container to host
        ssh_cmd "$SOURCE_HOST" "docker cp '$SOURCE_CONTAINER:/tmp/workflows_export' '$TEMP_DIR/workflows'"

        # Clean up inside container
        ssh_cmd "$SOURCE_HOST" "docker exec -u node '$SOURCE_CONTAINER' rm -rf /tmp/workflows_export"

        # Export credentials from Docker container
        print_status "Exporting credentials from Docker container..."
        ssh_cmd "$SOURCE_HOST" "docker exec -u node '$SOURCE_CONTAINER' n8n export:credentials --all --decrypted --output=/tmp/credentials_export.json" 2>/dev/null || {
            print_warning "Failed to export credentials (this may be normal if there are no credentials)"
        }

        # Copy credentials from container to host
        ssh_cmd "$SOURCE_HOST" "docker cp '$SOURCE_CONTAINER:/tmp/credentials_export.json' '$TEMP_DIR/credentials.json' 2>/dev/null || true"

        # Clean up inside container
        ssh_cmd "$SOURCE_HOST" "docker exec -u node '$SOURCE_CONTAINER' rm -f /tmp/credentials_export.json 2>/dev/null || true"
    else
        # Export workflows from native installation
        print_status "Exporting workflows from native installation..."
        ssh_cmd "$SOURCE_HOST" "n8n export:workflow --all --separate --output=$TEMP_DIR/workflows" || {
            print_error "Failed to export workflows"
            ssh_cmd "$SOURCE_HOST" "rm -rf $TEMP_DIR"
            exit 1
        }

        # Export credentials from native installation
        print_status "Exporting credentials from native installation..."
        ssh_cmd "$SOURCE_HOST" "n8n export:credentials --all --decrypted --output=$TEMP_DIR/credentials.json" || {
            print_warning "Failed to export credentials (this may be normal if there are no credentials)"
        }
    fi

    # Count workflows
    local workflow_count=$(ssh_cmd "$SOURCE_HOST" "find $TEMP_DIR/workflows -name '*.json' 2>/dev/null | wc -l" || echo "0")
    print_success "Exported $workflow_count workflows"

    # Create metadata file
    print_status "Creating backup metadata..."
    ssh_cmd "$SOURCE_HOST" "cat > $TEMP_DIR/backup_metadata.json << 'EOFMETA'
{
  \"backup_info\": {
    \"timestamp\": \"$TIMESTAMP\",
    \"date\": \"$(date -Iseconds)\",
    \"source_host\": \"$SOURCE_HOST\",
    \"source_instance_type\": \"$SOURCE_INSTANCE_TYPE\",
    \"source_container\": \"$SOURCE_CONTAINER\",
    \"backup_name\": \"$BACKUP_NAME\",
    \"workflows_count\": $workflow_count
  }
}
EOFMETA"

    # Compress the backup
    print_status "Compressing backup..."
    ssh_cmd "$SOURCE_HOST" "cd /tmp && tar -czf ${BACKUP_NAME}.tar.gz ${BACKUP_NAME}/"

    print_success "Backup created on source server: /tmp/${BACKUP_NAME}.tar.gz"
}

# Function to transfer backup to destination
transfer_backup() {
    print_status "Transferring backup from source to destination server..."

    # Verify source file exists
    if ! ssh_cmd "$SOURCE_HOST" "test -f /tmp/${BACKUP_NAME}.tar.gz"; then
        print_error "Backup file not found on source server: /tmp/${BACKUP_NAME}.tar.gz"
        exit 1
    fi

    # First, download to local machine
    local local_backup="/tmp/${BACKUP_NAME}.tar.gz"
    print_status "Downloading backup to local machine..."

    # Use direct sshpass with full debugging
    if ! sshpass -p "$SOURCE_PASSWORD" scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${SOURCE_HOST}:/tmp/${BACKUP_NAME}.tar.gz" "$local_backup"; then
        print_error "Failed to download backup from source server"
        print_status "Trying alternative method with rsync..."

        # Try rsync as fallback
        if command -v rsync &> /dev/null; then
            sshpass -p "$SOURCE_PASSWORD" rsync -avz -e "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null" "${SOURCE_HOST}:/tmp/${BACKUP_NAME}.tar.gz" "$local_backup" || {
                print_error "Rsync also failed. Cannot transfer backup."
                exit 1
            }
        else
            exit 1
        fi
    fi

    # Verify local file was created
    if [ ! -f "$local_backup" ]; then
        print_error "Failed to download backup to local machine"
        exit 1
    fi

    print_success "Downloaded backup ($(du -h "$local_backup" | cut -f1))"

    # Then upload to destination
    print_status "Uploading backup to destination server..."
    if ! sshpass -p "$DEST_PASSWORD" scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$local_backup" "${DEST_HOST}:/tmp/${BACKUP_NAME}.tar.gz"; then
        print_error "Failed to upload backup to destination server"

        # Try rsync as fallback
        if command -v rsync &> /dev/null; then
            sshpass -p "$DEST_PASSWORD" rsync -avz -e "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null" "$local_backup" "${DEST_HOST}:/tmp/${BACKUP_NAME}.tar.gz" || {
                print_error "Rsync also failed. Cannot transfer backup."
                rm -f "$local_backup"
                exit 1
            }
        else
            rm -f "$local_backup"
            exit 1
        fi
    fi

    # Clean up local copy
    rm -f "$local_backup"

    print_success "Backup transferred to destination server"
}

# Function to restore backup on destination
restore_backup_on_dest() {
    print_status "Restoring backup on destination server..."

    # Ask if user wants to clear existing workflows
    echo ""
    print_warning "Import Mode Selection"
    echo "How do you want to handle existing workflows on the destination?"
    echo "  1) Merge - Keep existing workflows and add new ones (may skip duplicates)"
    echo "  2) Replace - Clear all existing workflows before importing (DESTRUCTIVE)"
    echo ""
    read -p "Select option (1 or 2) [default: 1]: " -n 1 -r import_mode
    echo ""

    if [ -z "$import_mode" ]; then
        import_mode="1"
    fi

    local clear_existing=false
    if [ "$import_mode" = "2" ]; then
        clear_existing=true
        print_warning "This will DELETE all existing workflows on the destination!"
        read -p "Are you absolutely sure? (yes/no): " -r confirm_clear
        if [ "$confirm_clear" != "yes" ]; then
            print_status "Skipping workflow clearing. Will merge instead."
            clear_existing=false
        fi
    fi

    # Extract backup on destination
    print_status "Extracting backup..."
    ssh_cmd "$DEST_HOST" "cd /tmp && tar -xzf ${BACKUP_NAME}.tar.gz"

    if [ "$DEST_INSTANCE_TYPE" = "docker" ]; then
        # Restore to Docker container
        # Check if container is running
        local status=$(ssh_cmd "$DEST_HOST" "docker inspect --format='{{.State.Status}}' '$DEST_CONTAINER' 2>/dev/null || echo 'not-found'")

        if [ "$status" = "not-found" ]; then
            print_error "Destination container not found. Please create the container first."
            exit 1
        fi

        if [ "$status" != "running" ]; then
            print_status "Starting destination container..."
            ssh_cmd "$DEST_HOST" "docker start $DEST_CONTAINER"
            sleep 5
        fi

        # Clear existing workflows if requested
        if [ "$clear_existing" = true ]; then
            print_status "Clearing existing workflows from destination..."

            # Detect database type
            local db_type=$(ssh_cmd "$DEST_HOST" "docker exec '$DEST_CONTAINER' env | grep -i '^DB_TYPE=' | cut -d'=' -f2" || echo "sqlite")
            print_status "Detected database type: $db_type"

            if [[ "$db_type" == *"postgres"* ]]; then
                # PostgreSQL database
                print_status "Using PostgreSQL database clearing method..."

                # Get PostgreSQL connection details
                local pg_host=$(ssh_cmd "$DEST_HOST" "docker exec '$DEST_CONTAINER' env | grep '^DB_POSTGRESDB_HOST=' | cut -d'=' -f2")
                local pg_port=$(ssh_cmd "$DEST_HOST" "docker exec '$DEST_CONTAINER' env | grep '^DB_POSTGRESDB_PORT=' | cut -d'=' -f2")
                local pg_db=$(ssh_cmd "$DEST_HOST" "docker exec '$DEST_CONTAINER' env | grep '^DB_POSTGRESDB_DATABASE=' | cut -d'=' -f2")
                local pg_user=$(ssh_cmd "$DEST_HOST" "docker exec '$DEST_CONTAINER' env | grep '^DB_POSTGRESDB_USER=' | cut -d'=' -f2")
                local pg_pass=$(ssh_cmd "$DEST_HOST" "docker exec '$DEST_CONTAINER' env | grep '^DB_POSTGRESDB_PASSWORD=' | cut -d'=' -f2")

                print_status "PostgreSQL: $pg_user@$pg_host:$pg_port/$pg_db"

                # Find PostgreSQL container
                local pg_container=$(ssh_cmd "$DEST_HOST" "docker ps --format '{{.Names}}' | grep -i postgres | head -n1")
                print_status "PostgreSQL container: $pg_container"

                if [ -n "$pg_container" ]; then
                    # Clear database using PostgreSQL with correct table names
                    print_status "Clearing workflows from PostgreSQL database..."

                    # First, get list of all tables to clear
                    ssh_cmd "$DEST_HOST" "docker exec '$pg_container' psql -U '$pg_user' -d '$pg_db' -c \"
                        -- Disable triggers and constraints
                        SET session_replication_role = 'replica';

                        -- Clear execution-related tables
                        TRUNCATE TABLE execution_entity CASCADE;
                        TRUNCATE TABLE execution_annotation CASCADE;
                        TRUNCATE TABLE execution_data CASCADE;
                        TRUNCATE TABLE execution_metadata CASCADE;

                        -- Clear workflow-related tables
                        DELETE FROM workflow_publish_history;
                        DELETE FROM workflow_dependency;
                        DELETE FROM workflows_tags;
                        DELETE FROM workflow_statistics;
                        DELETE FROM workflow_history;
                        DELETE FROM shared_workflow;
                        DELETE FROM workflow_entity;

                        -- Clear credentials
                        DELETE FROM credentials_entity;

                        -- Re-enable constraints
                        SET session_replication_role = 'origin';
                    \"" && {
                        print_success "PostgreSQL database cleared successfully"
                    } || {
                        print_warning "Some tables may not exist or failed to clear"
                        print_status "Attempting individual table clearing..."

                        # Try to clear main tables individually
                        ssh_cmd "$DEST_HOST" "docker exec '$pg_container' psql -U '$pg_user' -d '$pg_db' -c \"DELETE FROM workflow_entity;\"" 2>/dev/null || true
                        ssh_cmd "$DEST_HOST" "docker exec '$pg_container' psql -U '$pg_user' -d '$pg_db' -c \"DELETE FROM credentials_entity;\"" 2>/dev/null || true
                        ssh_cmd "$DEST_HOST" "docker exec '$pg_container' psql -U '$pg_user' -d '$pg_db' -c \"DELETE FROM execution_entity;\"" 2>/dev/null || true

                        print_status "Main tables cleared"
                    }

                    # Verify clearing
                    local workflow_count=$(ssh_cmd "$DEST_HOST" "docker exec '$pg_container' psql -U '$pg_user' -d '$pg_db' -t -c 'SELECT COUNT(*) FROM workflow_entity;'" | tr -d ' ')
                    local cred_count=$(ssh_cmd "$DEST_HOST" "docker exec '$pg_container' psql -U '$pg_user' -d '$pg_db' -t -c 'SELECT COUNT(*) FROM credentials_entity;'" | tr -d ' ')

                    print_status "Verification: $workflow_count workflows, $cred_count credentials remaining"

                    # Restart n8n container to reload
                    print_status "Restarting n8n container to apply changes..."
                    ssh_cmd "$DEST_HOST" "docker restart '$DEST_CONTAINER'"

                    print_status "Waiting for n8n to fully initialize..."
                    sleep 10

                    # Wait for n8n to be fully ready (check logs for startup completion)
                    local max_wait=60
                    local waited=0
                    while [ $waited -lt $max_wait ]; do
                        if ssh_cmd "$DEST_HOST" "docker logs --tail 50 '$DEST_CONTAINER' 2>&1 | grep -q 'Editor is now accessible'"; then
                            print_status "n8n is ready!"
                            break
                        fi
                        sleep 2
                        waited=$((waited + 2))
                        print_status "Still waiting... ($waited/$max_wait seconds)"
                    done

                    # Additional buffer to ensure full initialization
                    sleep 5

                    print_success "Database cleared and container restarted"
                else
                    print_error "Could not find PostgreSQL container"
                    print_warning "Skipping database clearing"
                fi
            else
                # SQLite database
                print_status "Using SQLite database clearing method..."

                local db_path="/home/node/.n8n/database.sqlite"
                local backup_timestamp=$(date +%Y%m%d_%H%M%S)

                # Create backup while container is running
                print_status "Creating database backup..."
                ssh_cmd "$DEST_HOST" "docker exec '$DEST_CONTAINER' cp '$db_path' '${db_path}.backup_${backup_timestamp}'" || {
                    print_warning "Failed to create backup"
                }

                # Clear database while container is running
                print_status "Clearing workflows from database..."
                ssh_cmd "$DEST_HOST" "docker exec '$DEST_CONTAINER' sqlite3 '$db_path' \"PRAGMA foreign_keys = OFF; DELETE FROM workflow_statistics; DELETE FROM workflow_tag_mapping; DELETE FROM execution_data; DELETE FROM execution_metadata; DELETE FROM execution_annotation; DELETE FROM workflow_history; DELETE FROM workflow_version; DELETE FROM execution_entity; DELETE FROM workflow_entity; DELETE FROM credentials_entity; PRAGMA foreign_keys = ON; VACUUM;\"" || {
                    print_error "Failed to clear database"
                    print_warning "Continuing with import anyway..."
                }

                # Restart n8n container to reload
                print_status "Restarting n8n container to apply changes..."
                ssh_cmd "$DEST_HOST" "docker restart '$DEST_CONTAINER'"
                sleep 10  # Give n8n time to start

                print_success "Database cleared and container restarted"
            fi
        fi

        # Import workflows (same method as restore_n8n.sh)
        print_status "Importing workflows into destination container..."

        # Create directory inside container
        ssh_cmd "$DEST_HOST" "docker exec -u node '$DEST_CONTAINER' mkdir -p /tmp/workflows_import"

        # Copy workflows to host first for ID stripping
        ssh_cmd "$DEST_HOST" "mkdir -p /tmp/${BACKUP_NAME}/workflows_clean"

        # Strip workflow IDs to force creating new workflows instead of updating
        if [ "$clear_existing" = true ]; then
            print_status "Stripping workflow IDs to force fresh import..."

            # Process each workflow file to remove ID fields using jq or Python
            local workflow_files=$(ssh_cmd "$DEST_HOST" "find /tmp/${BACKUP_NAME}/workflows -name '*.json' -type f")

            while IFS= read -r wf_file; do
                if [ -n "$wf_file" ]; then
                    local filename=$(ssh_cmd "$DEST_HOST" "basename '$wf_file'")

                    # Try jq first (most reliable), then Python as fallback
                    if ssh_cmd "$DEST_HOST" "command -v jq >/dev/null 2>&1"; then
                        # Use jq to remove the 'id' field
                        ssh_cmd "$DEST_HOST" "jq 'del(.id)' '$wf_file' > /tmp/${BACKUP_NAME}/workflows_clean/${filename}"
                    elif ssh_cmd "$DEST_HOST" "command -v python3 >/dev/null 2>&1"; then
                        # Use Python to remove the 'id' field
                        ssh_cmd "$DEST_HOST" "python3 -c \"import json; f=open('$wf_file'); d=json.load(f); f.close(); d.pop('id', None); open('/tmp/${BACKUP_NAME}/workflows_clean/${filename}', 'w').write(json.dumps(d))\""
                    else
                        # Fallback: Use perl (usually available)
                        ssh_cmd "$DEST_HOST" "perl -pe 's/\"id\"\s*:\s*\"[^\"]+\",?//g' '$wf_file' | perl -pe 's/,(\s*\})/\$1/g' > /tmp/${BACKUP_NAME}/workflows_clean/${filename}"
                    fi
                fi
            done <<< "$workflow_files"

            # Copy cleaned workflows into container
            ssh_cmd "$DEST_HOST" "docker cp /tmp/${BACKUP_NAME}/workflows_clean/. ${DEST_CONTAINER}:/tmp/workflows_import/"
        else
            # Copy workflows as-is for merge mode
            ssh_cmd "$DEST_HOST" "docker cp /tmp/${BACKUP_NAME}/workflows/. ${DEST_CONTAINER}:/tmp/workflows_import/"
        fi

        # Import workflows - try CLI first, if it fails in Replace mode, use fallback
        local import_output=$(ssh_cmd "$DEST_HOST" "docker exec -u node '$DEST_CONTAINER' n8n import:workflow --separate --input=/tmp/workflows_import 2>&1" || echo "")

        # Check import result
        if echo "$import_output" | grep -q "Successfully imported"; then
            # Extract workflow count using sed (macOS compatible)
            local workflow_count=$(echo "$import_output" | sed -n 's/.*Successfully imported \([0-9]*\) workflows.*/\1/p')
            if [ -z "$workflow_count" ]; then
                workflow_count=$(echo "$import_output" | grep -o '[0-9]* workflows' | grep -o '[0-9]*' | head -1)
            fi
            if [ -n "$workflow_count" ]; then
                print_success "Successfully imported $workflow_count workflows"
            else
                print_success "Workflows imported successfully"
            fi
        elif echo "$import_output" | grep -q "Could not find workflow" && [ "$clear_existing" = true ]; then
            # n8n CLI import failed due to webhook cleanup bug after database clear
            # Use workaround: import in Merge mode by temporarily NOT stripping IDs
            print_warning "n8n import command has webhook cleanup bug after database clear"
            print_status "Using workaround: importing without stripping IDs..."

            # Re-copy workflows WITH IDs (original files)
            ssh_cmd "$DEST_HOST" "docker exec -u node '$DEST_CONTAINER' rm -rf /tmp/workflows_import"
            ssh_cmd "$DEST_HOST" "docker exec -u node '$DEST_CONTAINER' mkdir -p /tmp/workflows_import"
            ssh_cmd "$DEST_HOST" "docker cp /tmp/${BACKUP_NAME}/workflows/. ${DEST_CONTAINER}:/tmp/workflows_import/"

            # Try import again with original IDs
            local import_output2=$(ssh_cmd "$DEST_HOST" "docker exec -u node '$DEST_CONTAINER' n8n import:workflow --separate --input=/tmp/workflows_import 2>&1" || echo "")

            if echo "$import_output2" | grep -q "Successfully imported"; then
                local workflow_count=$(echo "$import_output2" | sed -n 's/.*Successfully imported \([0-9]*\) workflows.*/\1/p')
                print_success "Successfully imported $workflow_count workflows (with original IDs)"
                print_status "Note: Workflows imported with their original IDs from source"
            else
                print_error "Import failed even with workaround"
                echo "$import_output2"
            fi
        else
            print_error "Failed to import workflows"
            echo "$import_output"
        fi

        # Clean up
        ssh_cmd "$DEST_HOST" "docker exec -u node '$DEST_CONTAINER' rm -rf /tmp/workflows_import 2>/dev/null" || true
        ssh_cmd "$DEST_HOST" "rm -rf /tmp/${BACKUP_NAME}/workflows_clean 2>/dev/null" || true

        # Copy and import credentials
        local cred_file_exists=$(ssh_cmd "$DEST_HOST" "test -f /tmp/${BACKUP_NAME}/credentials.json && echo 'yes' || echo 'no'")

        if [ "$cred_file_exists" = "yes" ]; then
            print_status "Importing credentials into destination container..."
            ssh_cmd "$DEST_HOST" "docker cp /tmp/${BACKUP_NAME}/credentials.json ${DEST_CONTAINER}:/tmp/credentials_restore.json"

            # Import credentials with error handling
            local cred_output=$(ssh_cmd "$DEST_HOST" "docker exec -u node '$DEST_CONTAINER' n8n import:credentials --input=/tmp/credentials_restore.json 2>&1" || echo "")

            if echo "$cred_output" | grep -q "Successfully imported"; then
                # Extract number using sed (macOS compatible)
                local cred_count=$(echo "$cred_output" | sed -n 's/.*Successfully imported \([0-9]*\) credentials.*/\1/p')
                if [ -z "$cred_count" ]; then
                    cred_count="some"
                fi
                print_success "Successfully imported $cred_count credentials"
            else
                print_warning "Some credentials may not have been imported (they might already exist)"
                echo "$cred_output"
            fi

            # Clean up inside container (run as root to avoid permission issues)
            ssh_cmd "$DEST_HOST" "docker exec '$DEST_CONTAINER' rm -f /tmp/credentials_restore.json 2>/dev/null" || true
        else
            print_status "No credentials file to import"
        fi
    else
        # Restore to native installation (same method as restore_n8n.sh)
        print_status "Importing workflows into native n8n installation..."

        # Import all workflows at once using --separate flag
        local import_output=$(ssh_cmd "$DEST_HOST" "n8n import:workflow --separate --input=/tmp/${BACKUP_NAME}/workflows 2>&1" || echo "")

        # Check import result
        if echo "$import_output" | grep -q "Successfully imported"; then
            local workflow_count=$(echo "$import_output" | sed -n 's/.*Successfully imported \([0-9]*\) workflows.*/\1/p')
            if [ -z "$workflow_count" ]; then
                workflow_count=$(echo "$import_output" | grep -o '[0-9]* workflows' | grep -o '[0-9]*' | head -1)
            fi
            if [ -n "$workflow_count" ]; then
                print_success "Successfully imported $workflow_count workflows"
            else
                print_success "Workflows imported successfully"
            fi
        else
            print_error "Failed to import workflows"
            echo "$import_output"
        fi

        # Import credentials
        local cred_file_exists=$(ssh_cmd "$DEST_HOST" "test -f /tmp/${BACKUP_NAME}/credentials.json && echo 'yes' || echo 'no'")

        if [ "$cred_file_exists" = "yes" ]; then
            print_status "Importing credentials into native n8n installation..."
            local cred_output=$(ssh_cmd "$DEST_HOST" "n8n import:credentials --input=/tmp/${BACKUP_NAME}/credentials.json 2>&1" || echo "")

            if echo "$cred_output" | grep -q "Successfully imported"; then
                local cred_count=$(echo "$cred_output" | sed -n 's/.*Successfully imported \([0-9]*\) credentials.*/\1/p')
                if [ -z "$cred_count" ]; then
                    cred_count="some"
                fi
                print_success "Successfully imported $cred_count credentials"
            else
                print_warning "Failed to import credentials"
                echo "$cred_output"
            fi
        else
            print_status "No credentials file to import"
        fi
    fi

    print_success "Backup restored on destination server"
}

# Function to cleanup temporary files
cleanup() {
    print_status "Cleaning up temporary files..."

    # Clean up source
    ssh_cmd "$SOURCE_HOST" "rm -rf $TEMP_DIR /tmp/${BACKUP_NAME}.tar.gz" 2>/dev/null || true

    # Clean up destination
    ssh_cmd "$DEST_HOST" "rm -rf $TEMP_DIR /tmp/${BACKUP_NAME}.tar.gz" 2>/dev/null || true

    # Clean up local
    rm -f "/tmp/${BACKUP_NAME}.tar.gz" 2>/dev/null || true

    print_success "Cleanup completed"
}

# Function to verify restoration
verify_restoration() {
    print_status "Verifying restoration..."

    if [ "$DEST_INSTANCE_TYPE" = "docker" ]; then
        local dest_status=$(ssh_cmd "$DEST_HOST" "docker inspect --format='{{.State.Status}}' '$DEST_CONTAINER'")

        if [ "$dest_status" = "running" ]; then
            print_success "Destination container is running"

            # Try to get n8n version
            local version=$(ssh_cmd "$DEST_HOST" "docker exec $DEST_CONTAINER n8n --version 2>/dev/null | head -n1" || echo "unknown")
            print_status "n8n version: $version"

            # Get container info
            local port=$(ssh_cmd "$DEST_HOST" "docker port $DEST_CONTAINER 5678 2>/dev/null || echo 'not exposed'")
            if [ "$port" != "not exposed" ]; then
                print_status "n8n is accessible on: http://${DEST_HOST#*@}:${port%->*}"
            fi
        else
            print_error "Destination container is not running"
            print_status "Check logs with: ssh $DEST_HOST 'docker logs $DEST_CONTAINER'"
        fi
    else
        # Verify native installation
        if ssh_cmd "$DEST_HOST" "command -v n8n >/dev/null 2>&1"; then
            print_success "Native n8n installation is accessible"

            # Try to get n8n version
            local version=$(ssh_cmd "$DEST_HOST" "n8n --version 2>/dev/null | head -n1" || echo "unknown")
            print_status "n8n version: $version"
        else
            print_error "n8n command not found on destination server"
        fi
    fi
}

# Function to show summary
show_summary() {
    print_success "Backup and restore completed!"
    echo ""
    print_status "Summary:"
    if [ "$SOURCE_INSTANCE_TYPE" = "docker" ]; then
        print_status "  Source: $SOURCE_HOST (Docker container: $SOURCE_CONTAINER)"
    else
        print_status "  Source: $SOURCE_HOST (Native installation)"
    fi

    if [ "$DEST_INSTANCE_TYPE" = "docker" ]; then
        print_status "  Destination: $DEST_HOST (Docker container: $DEST_CONTAINER)"
    else
        print_status "  Destination: $DEST_HOST (Native installation)"
    fi

    print_status "  Backup name: $BACKUP_NAME"
    echo ""
    print_status "Next steps:"
    print_status "  1. Access n8n on destination server"
    print_status "  2. Verify workflows are present"
    print_status "  3. Check and update credentials as needed"
    print_status "  4. Activate workflows"
    echo ""
    print_warning "Important: Credentials may need to be reconfigured on the destination server"
}

# Main execution
main() {
    print_status "N8N Remote Backup Transfer Tool"
    print_status "================================"
    echo ""

    # Parse command line arguments
    parse_arguments "$@"

    # Prompt for any missing configuration
    prompt_for_config

    check_prerequisites
    test_ssh_connectivity
    echo ""

    configure_source
    configure_destination

    verify_source
    verify_destination

    echo ""
    print_warning "This will backup n8n from $SOURCE_HOST and restore to $DEST_HOST"
    read -p "Continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_error "Operation cancelled"
        exit 1
    fi

    create_backup_on_source
    transfer_backup
    restore_backup_on_dest
    verify_restoration
    cleanup
    show_summary
}

# Run main function
main "$@"
