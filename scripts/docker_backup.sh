#!/bin/bash

# Docker N8N Backup Helper Script
# This script provides Docker-specific backup functionality with enhanced features
# Usage: ./docker_backup.sh [container_name] [--include-volumes] [--include-logs]

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
BACKUP_BASE_DIR="${N8N_BACKUP_DIR:-$N8N_DIR/backups}"

# Default values
CONTAINER_NAME="n8n"
INCLUDE_VOLUMES=false
INCLUDE_LOGS=false
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
    echo "Usage: $0 [container_name] [--include-volumes] [--include-logs]"
    echo ""
    echo "Options:"
    echo "  container_name      Name of Docker container (default: n8n)"
    echo "  --include-volumes   Include Docker volume backup"
    echo "  --include-logs      Include container logs in backup"
    echo ""
    echo "Examples:"
    echo "  $0                           # Basic backup of 'n8n' container"
    echo "  $0 my-n8n                   # Backup specific container"
    echo "  $0 n8n --include-volumes    # Include volume backup"
    echo "  $0 n8n --include-logs       # Include container logs"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --include-volumes)
            INCLUDE_VOLUMES=true
            shift
            ;;
        --include-logs)
            INCLUDE_LOGS=true
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

print_status "Docker N8N Backup Helper v1.0.0"
print_status "================================="
print_status "Container: $CONTAINER_NAME"
print_status "Include volumes: $INCLUDE_VOLUMES"
print_status "Include logs: $INCLUDE_LOGS"

# Create backup directory
BACKUP_DIR="$BACKUP_BASE_DIR/docker_enhanced_backup_$TIMESTAMP"
mkdir -p "$BACKUP_DIR"

# Function to check Docker container
check_container() {
    if ! docker ps -a --format "table {{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
        print_error "Docker container '$CONTAINER_NAME' not found."
        print_status "Available containers:"
        docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"
        exit 1
    fi
    
    local status=$(docker inspect --format='{{.State.Status}}' "$CONTAINER_NAME")
    print_status "Container status: $status"
    
    if [ "$status" != "running" ]; then
        print_warning "Container is not running. Some operations may fail."
    fi
}

# Function to get container information
get_container_info() {
    print_status "Gathering container information..."
    
    local info_file="$BACKUP_DIR/container_info.json"
    docker inspect "$CONTAINER_NAME" > "$info_file"
    
    local image=$(docker inspect --format='{{.Config.Image}}' "$CONTAINER_NAME")
    local created=$(docker inspect --format='{{.Created}}' "$CONTAINER_NAME")
    local mounts=$(docker inspect --format='{{range .Mounts}}{{.Type}}:{{.Source}}->{{.Destination}} {{end}}' "$CONTAINER_NAME")
    
    print_status "Image: $image"
    print_status "Created: $created"
    print_status "Mounts: $mounts"
}

# Function to backup container logs
backup_logs() {
    if [ "$INCLUDE_LOGS" = true ]; then
        print_status "Backing up container logs..."
        local logs_file="$BACKUP_DIR/container_logs.txt"
        docker logs "$CONTAINER_NAME" > "$logs_file" 2>&1 || true
        print_success "Container logs backed up"
    fi
}

# Function to backup Docker volumes
backup_volumes() {
    if [ "$INCLUDE_VOLUMES" = true ]; then
        print_status "Backing up Docker volumes..."
        
        local volumes_dir="$BACKUP_DIR/volumes"
        mkdir -p "$volumes_dir"
        
        # Get all volumes used by the container
        local volumes=$(docker inspect --format='{{range .Mounts}}{{if eq .Type "volume"}}{{.Name}} {{end}}{{end}}' "$CONTAINER_NAME")
        
        if [ -n "$volumes" ]; then
            for volume in $volumes; do
                print_status "Backing up volume: $volume"
                local volume_backup="$volumes_dir/${volume}_backup.tar"
                
                # Create a temporary container to access the volume
                docker run --rm -v "$volume":/volume -v "$volumes_dir":/backup alpine tar -cf "/backup/${volume}_backup.tar" -C /volume .
                
                print_success "Volume $volume backed up"
            done
        else
            print_status "No volumes found for container"
        fi
    fi
}

# Function to backup bind mounts
backup_bind_mounts() {
    print_status "Checking for bind mounts..."
    
    local bind_mounts=$(docker inspect --format='{{range .Mounts}}{{if eq .Type "bind"}}{{.Source}}->{{.Destination}} {{end}}{{end}}' "$CONTAINER_NAME")
    
    if [ -n "$bind_mounts" ]; then
        print_status "Found bind mounts: $bind_mounts"
        
        local mounts_info="$BACKUP_DIR/bind_mounts.txt"
        echo "Bind mounts for container $CONTAINER_NAME:" > "$mounts_info"
        echo "$bind_mounts" >> "$mounts_info"
        echo "" >> "$mounts_info"
        echo "Note: Bind mounts are not automatically backed up." >> "$mounts_info"
        echo "Please manually backup the source directories if needed:" >> "$mounts_info"
        
        docker inspect --format='{{range .Mounts}}{{if eq .Type "bind"}}{{.Source}}{{"\n"}}{{end}}{{end}}' "$CONTAINER_NAME" >> "$mounts_info"
        
        print_warning "Bind mounts found but not backed up automatically"
        print_status "See bind_mounts.txt for details"
    fi
}

# Function to create Docker Compose template
create_compose_template() {
    print_status "Creating Docker Compose template..."
    
    local compose_file="$BACKUP_DIR/docker-compose.yml"
    local image=$(docker inspect --format='{{.Config.Image}}' "$CONTAINER_NAME")
    local env_vars=$(docker inspect --format='{{range .Config.Env}}{{.}}{{"\n"}}{{end}}' "$CONTAINER_NAME" | grep -E '^N8N_|^DB_|^REDIS_' || true)
    local ports=$(docker inspect --format='{{range $p, $conf := .NetworkSettings.Ports}}{{if $conf}}{{$p}} -> {{(index $conf 0).HostPort}}{{"\n"}}{{end}}{{end}}' "$CONTAINER_NAME")
    
    cat > "$compose_file" << EOF
version: '3.8'

services:
  n8n:
    image: $image
    container_name: $CONTAINER_NAME
    restart: unless-stopped
    ports:
EOF

    # Add port mappings
    if [ -n "$ports" ]; then
        echo "$ports" | while IFS= read -r port_mapping; do
            if [ -n "$port_mapping" ]; then
                local container_port=$(echo "$port_mapping" | cut -d' ' -f1 | sed 's|/tcp||')
                local host_port=$(echo "$port_mapping" | cut -d' ' -f3)
                echo "      - \"$host_port:$container_port\"" >> "$compose_file"
            fi
        done
    else
        echo "      - \"5678:5678\"" >> "$compose_file"
    fi
    
    # Add environment variables
    if [ -n "$env_vars" ]; then
        echo "    environment:" >> "$compose_file"
        echo "$env_vars" | while IFS= read -r env_var; do
            if [ -n "$env_var" ]; then
                echo "      - $env_var" >> "$compose_file"
            fi
        done
    fi
    
    # Add volume mappings
    local volumes=$(docker inspect --format='{{range .Mounts}}{{.Type}}:{{if eq .Type "volume"}}{{.Name}}{{else}}{{.Source}}{{end}}->{{.Destination}}{{"\n"}}{{end}}' "$CONTAINER_NAME")
    if [ -n "$volumes" ]; then
        echo "    volumes:" >> "$compose_file"
        echo "$volumes" | while IFS= read -r volume_mapping; do
            if [ -n "$volume_mapping" ]; then
                local source=$(echo "$volume_mapping" | cut -d':' -f2 | cut -d'-' -f1)
                local dest=$(echo "$volume_mapping" | cut -d'>' -f2)
                echo "      - $source:$dest" >> "$compose_file"
            fi
        done
    fi
    
    print_success "Docker Compose template created"
}

# Function to run standard n8n backup
run_standard_backup() {
    print_status "Running standard n8n backup..."
    "$SCRIPT_DIR/backup_n8n.sh" docker "$CONTAINER_NAME"
    
    # Move the standard backup into our enhanced backup directory
    local latest_backup=$(ls -t "$BACKUP_BASE_DIR"/docker_backup_*.tar.gz 2>/dev/null | head -n1)
    if [ -n "$latest_backup" ]; then
        mv "$latest_backup" "$BACKUP_DIR/"
        print_success "Standard backup included"
    fi
}

# Function to create enhanced metadata
create_enhanced_metadata() {
    local metadata_file="$BACKUP_DIR/enhanced_backup_metadata.json"
    local image=$(docker inspect --format='{{.Config.Image}}' "$CONTAINER_NAME")
    local created=$(docker inspect --format='{{.Created}}' "$CONTAINER_NAME")
    
    cat > "$metadata_file" << EOF
{
  "enhanced_backup_info": {
    "timestamp": "$TIMESTAMP",
    "date": "$(date -Iseconds)",
    "container_name": "$CONTAINER_NAME",
    "image": "$image",
    "created": "$created",
    "include_volumes": $INCLUDE_VOLUMES,
    "include_logs": $INCLUDE_LOGS,
    "script_version": "1.0.0"
  },
  "backup_contents": {
    "standard_n8n_backup": true,
    "container_info": true,
    "docker_compose_template": true,
    "volumes_backup": $INCLUDE_VOLUMES,
    "container_logs": $INCLUDE_LOGS,
    "backup_size_mb": "$(du -sm "$BACKUP_DIR" | cut -f1)"
  },
  "restoration_info": {
    "restore_command": "./docker_restore.sh $(basename "$BACKUP_DIR")",
    "manual_steps_required": true,
    "compose_file_included": true
  }
}
EOF
    
    print_status "Enhanced metadata created"
}

# Function to compress enhanced backup
compress_enhanced_backup() {
    print_status "Compressing enhanced backup..."
    cd "$BACKUP_BASE_DIR"
    tar -czf "docker_enhanced_backup_$TIMESTAMP.tar.gz" "$(basename "$BACKUP_DIR")"
    rm -rf "$BACKUP_DIR"
    print_success "Enhanced backup compressed to: docker_enhanced_backup_$TIMESTAMP.tar.gz"
}

# Main execution
main() {
    check_container
    get_container_info
    backup_logs
    backup_volumes
    backup_bind_mounts
    create_compose_template
    run_standard_backup
    create_enhanced_metadata
    compress_enhanced_backup
    
    print_success "Enhanced Docker backup completed!"
    print_status "Backup location: $BACKUP_BASE_DIR/docker_enhanced_backup_$TIMESTAMP.tar.gz"
    print_status ""
    print_status "This backup includes:"
    print_status "- Standard n8n workflows and credentials"
    print_status "- Container configuration and metadata"
    print_status "- Docker Compose template for recreation"
    if [ "$INCLUDE_VOLUMES" = true ]; then
        print_status "- Docker volume backups"
    fi
    if [ "$INCLUDE_LOGS" = true ]; then
        print_status "- Container logs"
    fi
}

# Run main function
main "$@"
