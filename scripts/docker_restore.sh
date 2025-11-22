#!/bin/bash

# Docker N8N Restore Helper Script
# This script provides Docker-specific restore functionality with enhanced features
# Usage: ./docker_restore.sh [backup_name] [container_name] [--recreate-container]

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
BACKUP_BASE_DIR="$N8N_DIR/backups"

# Default values
CONTAINER_NAME="n8n"
BACKUP_NAME=""
RECREATE_CONTAINER=false
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

# Function to cleanup on exit
cleanup() {
    if [ -n "$TEMP_EXTRACT_DIR" ] && [ -d "$TEMP_EXTRACT_DIR" ]; then
        print_status "Cleaning up temporary files..."
        rm -rf "$TEMP_EXTRACT_DIR"
    fi
}

# Set trap for cleanup
trap cleanup EXIT

# Function to show usage
show_usage() {
    echo "Usage: $0 [backup_name] [container_name] [--recreate-container]"
    echo ""
    echo "Options:"
    echo "  backup_name         Name of enhanced backup to restore"
    echo "  container_name      Name of Docker container (default: n8n)"
    echo "  --recreate-container Recreate container from backup configuration"
    echo ""
    echo "Examples:"
    echo "  $0 docker_enhanced_backup_20240115_143022"
    echo "  $0 docker_enhanced_backup_20240115_143022 my-n8n"
    echo "  $0 docker_enhanced_backup_20240115_143022 n8n --recreate-container"
    echo ""
    echo "Available enhanced backups:"
    list_available_backups
}

# Function to list available backups
list_available_backups() {
    if [ -d "$BACKUP_BASE_DIR" ]; then
        echo "Enhanced Docker backups:"
        ls -la "$BACKUP_BASE_DIR"/docker_enhanced_backup_*.tar.gz 2>/dev/null | awk '{print "  " $9}' | sed 's|.*/||' | sed 's|\.tar\.gz||' || echo "  No enhanced backups found"
    else
        echo "  No backup directory found"
    fi
}

# Parse command line arguments
if [ $# -lt 1 ]; then
    print_error "Missing required backup name"
    show_usage
    exit 1
fi

BACKUP_NAME="$1"
shift

while [[ $# -gt 0 ]]; do
    case $1 in
        --recreate-container)
            RECREATE_CONTAINER=true
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        -*)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
        *)
            CONTAINER_NAME="$1"
            shift
            ;;
    esac
done

print_status "Docker N8N Restore Helper v1.0.0"
print_status "=================================="
print_status "Backup: $BACKUP_NAME"
print_status "Container: $CONTAINER_NAME"
print_status "Recreate container: $RECREATE_CONTAINER"

# Function to extract enhanced backup
extract_enhanced_backup() {
    local compressed_backup="$BACKUP_BASE_DIR/${BACKUP_NAME}.tar.gz"
    
    if [ ! -f "$compressed_backup" ]; then
        print_error "Enhanced backup not found: $compressed_backup"
        list_available_backups
        exit 1
    fi
    
    print_status "Extracting enhanced backup..."
    TEMP_EXTRACT_DIR="$BACKUP_BASE_DIR/temp_restore_$$"
    mkdir -p "$TEMP_EXTRACT_DIR"
    
    tar -xzf "$compressed_backup" -C "$TEMP_EXTRACT_DIR"
    BACKUP_DIR="$TEMP_EXTRACT_DIR/$BACKUP_NAME"
    
    if [ ! -d "$BACKUP_DIR" ]; then
        print_error "Invalid backup structure"
        exit 1
    fi
    
    print_success "Backup extracted successfully"
}

# Function to show enhanced backup info
show_enhanced_backup_info() {
    local metadata_file="$BACKUP_DIR/enhanced_backup_metadata.json"
    
    if [ -f "$metadata_file" ]; then
        print_status "Enhanced Backup Information:"
        if command -v jq &> /dev/null; then
            echo "  Created: $(jq -r '.enhanced_backup_info.date' "$metadata_file")"
            echo "  Original Container: $(jq -r '.enhanced_backup_info.container_name' "$metadata_file")"
            echo "  Original Image: $(jq -r '.enhanced_backup_info.image' "$metadata_file")"
            echo "  Size: $(jq -r '.backup_contents.backup_size_mb' "$metadata_file") MB"
            echo "  Includes Volumes: $(jq -r '.backup_contents.volumes_backup' "$metadata_file")"
            echo "  Includes Logs: $(jq -r '.backup_contents.container_logs' "$metadata_file")"
        else
            print_status "  (Install jq for detailed backup information)"
        fi
    fi
}

# Function to stop existing container
stop_existing_container() {
    if docker ps --format "table {{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
        print_status "Stopping existing container: $CONTAINER_NAME"
        docker stop "$CONTAINER_NAME"
        print_success "Container stopped"
    fi
}

# Function to remove existing container
remove_existing_container() {
    if docker ps -a --format "table {{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
        print_status "Removing existing container: $CONTAINER_NAME"
        docker rm "$CONTAINER_NAME"
        print_success "Container removed"
    fi
}

# Function to recreate container from backup
recreate_container_from_backup() {
    local compose_file="$BACKUP_DIR/docker-compose.yml"
    local container_info="$BACKUP_DIR/container_info.json"
    
    if [ ! -f "$compose_file" ]; then
        print_error "Docker Compose file not found in backup"
        return 1
    fi
    
    print_status "Recreating container from backup configuration..."
    
    # Stop and remove existing container
    stop_existing_container
    remove_existing_container
    
    # Use docker-compose to recreate the container
    cd "$BACKUP_DIR"
    if command -v docker-compose &> /dev/null; then
        docker-compose up -d
    elif docker compose version &> /dev/null; then
        docker compose up -d
    else
        print_error "Neither docker-compose nor 'docker compose' command found"
        print_status "Please install Docker Compose or recreate the container manually"
        print_status "See docker-compose.yml in the backup for configuration"
        return 1
    fi
    
    print_success "Container recreated successfully"
    
    # Wait for container to be ready
    print_status "Waiting for n8n to start..."
    sleep 15
}

# Function to restore volumes
restore_volumes() {
    local volumes_dir="$BACKUP_DIR/volumes"
    
    if [ ! -d "$volumes_dir" ]; then
        print_status "No volume backups found"
        return 0
    fi
    
    print_status "Restoring Docker volumes..."
    
    for volume_backup in "$volumes_dir"/*_backup.tar; do
        if [ -f "$volume_backup" ]; then
            local volume_name=$(basename "$volume_backup" | sed 's/_backup.tar$//')
            print_status "Restoring volume: $volume_name"
            
            # Create volume if it doesn't exist
            docker volume create "$volume_name" >/dev/null 2>&1 || true
            
            # Restore volume data
            docker run --rm -v "$volume_name":/volume -v "$volumes_dir":/backup alpine tar -xf "/backup/${volume_name}_backup.tar" -C /volume
            
            print_success "Volume $volume_name restored"
        fi
    done
}

# Function to run standard n8n restore
run_standard_restore() {
    print_status "Running standard n8n restore..."
    
    # Find the standard backup within the enhanced backup
    local standard_backup=$(find "$BACKUP_DIR" -name "docker_backup_*.tar.gz" | head -n1)
    
    if [ -n "$standard_backup" ]; then
        # Extract the standard backup temporarily
        local temp_standard_dir="$TEMP_EXTRACT_DIR/standard_backup"
        mkdir -p "$temp_standard_dir"
        tar -xzf "$standard_backup" -C "$temp_standard_dir"
        
        # Find the extracted directory
        local standard_backup_dir=$(find "$temp_standard_dir" -type d -name "docker_backup_*" | head -n1)
        
        if [ -n "$standard_backup_dir" ]; then
            # Use the standard restore script
            "$SCRIPT_DIR/restore_n8n.sh" docker "$(basename "$standard_backup_dir")" "$CONTAINER_NAME"
        else
            print_error "Could not find standard backup directory"
        fi
    else
        print_error "No standard n8n backup found in enhanced backup"
    fi
}

# Function to show restoration summary
show_restoration_summary() {
    print_success "Enhanced Docker restore completed!"
    print_status ""
    print_status "What was restored:"
    print_status "- n8n workflows and credentials"
    print_status "- Container configuration"
    
    if [ -d "$BACKUP_DIR/volumes" ]; then
        print_status "- Docker volumes"
    fi
    
    if [ "$RECREATE_CONTAINER" = true ]; then
        print_status "- Container recreated from backup"
    fi
    
    print_status ""
    print_status "Next steps:"
    print_status "1. Check that the container is running: docker ps"
    print_status "2. Check container logs: docker logs $CONTAINER_NAME"
    print_status "3. Open n8n interface and verify workflows"
    print_status "4. Test credentials and activate workflows as needed"
    
    if [ -f "$BACKUP_DIR/bind_mounts.txt" ]; then
        print_warning "Note: Check bind_mounts.txt for any manual bind mount restoration needed"
    fi
}

# Function to check container status
check_final_status() {
    print_status "Checking final container status..."
    
    if docker ps --format "table {{.Names}}\t{{.Status}}" | grep -q "^${CONTAINER_NAME}"; then
        local status=$(docker ps --format "table {{.Names}}\t{{.Status}}" | grep "^${CONTAINER_NAME}" | awk '{print $2" "$3}')
        print_success "Container $CONTAINER_NAME is running: $status"
        
        # Try to get n8n version if possible
        if docker exec "$CONTAINER_NAME" n8n --version &>/dev/null; then
            local version=$(docker exec "$CONTAINER_NAME" n8n --version 2>/dev/null | head -n1)
            print_status "n8n version: $version"
        fi
    else
        print_error "Container $CONTAINER_NAME is not running"
        print_status "Check logs with: docker logs $CONTAINER_NAME"
    fi
}

# Function to confirm restore
confirm_restore() {
    print_warning "This will restore an enhanced Docker backup to container '$CONTAINER_NAME'"
    
    if [ "$RECREATE_CONTAINER" = true ]; then
        print_warning "The existing container will be STOPPED and REMOVED!"
    fi
    
    print_warning "Existing data may be overwritten!"
    print_status ""
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_error "Restore cancelled by user"
        exit 1
    fi
}

# Main execution
main() {
    extract_enhanced_backup
    show_enhanced_backup_info
    confirm_restore
    
    if [ "$RECREATE_CONTAINER" = true ]; then
        recreate_container_from_backup
        restore_volumes
    else
        # Check if container exists and is running
        if ! docker ps --format "table {{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
            print_error "Container '$CONTAINER_NAME' not found or not running"
            print_status "Use --recreate-container to recreate from backup, or start the container first"
            exit 1
        fi
        restore_volumes
    fi
    
    run_standard_restore
    check_final_status
    show_restoration_summary
}

# Run main function
main "$@"
