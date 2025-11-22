# N8N Backup and Restore System

A comprehensive solution for backing up and restoring n8n workflows and credentials across different environments (native installations and Docker containers).

## 📁 Directory Structure

```
backend/n8n/
├── README.md                    # This documentation
├── scripts/                     # Backup and restore scripts
│   ├── backup_n8n.sh          # Main backup script (native/Docker)
│   ├── restore_n8n.sh         # Main restore script (native/Docker)
│   ├── docker_backup.sh       # Enhanced Docker backup with volumes
│   ├── docker_restore.sh      # Enhanced Docker restore with volumes
│   └── manage_n8n.sh          # Unified management interface
├── config/                      # Configuration files
│   ├── n8n_config.json        # Configuration settings
│   └── encryption_key_example.txt # Encryption key setup guide
└── backups/                     # Backup storage (created automatically)
    ├── native_backup_YYYYMMDD_HHMMSS.tar.gz
    ├── docker_backup_YYYYMMDD_HHMMSS.tar.gz
    └── docker_enhanced_backup_YYYYMMDD_HHMMSS.tar.gz
```

## 🚀 Quick Start

### Option 1: Use the Management Interface (Recommended)

```bash
cd backend/n8n/scripts
./manage_n8n.sh
```

This provides an interactive menu for all backup and restore operations.

### Option 2: Direct Script Usage

#### Create a Backup

**Native n8n (Mac/Linux):**
```bash
./backup_n8n.sh native
```

**Docker n8n:**
```bash
./backup_n8n.sh docker [container_name]
```

**Enhanced Docker backup (with volumes and logs):**
```bash
./docker_backup.sh [container_name] --include-volumes --include-logs
```

#### Restore a Backup

**To Native n8n:**
```bash
./restore_n8n.sh native backup_name
```

**To Docker n8n:**
```bash
./restore_n8n.sh docker backup_name [container_name]
```

**Enhanced Docker restore:**
```bash
./docker_restore.sh backup_name [container_name] [--recreate-container]
```

## 🔑 Prerequisites and Setup

### 1. Encryption Key Setup (CRITICAL)

The same encryption key **MUST** be used on both source and destination instances for credentials to work properly.

#### Set Environment Variable:
```bash
export N8N_ENCRYPTION_KEY="your-32-character-encryption-key-here"
```

#### Generate a New Key:
```bash
# Using OpenSSL
openssl rand -hex 16

# Using Node.js
node -e "console.log(require('crypto').randomBytes(16).toString('hex'))"

# Using the management script
./manage_n8n.sh config
```

### 2. Required Tools

**For Native n8n:**
- n8n CLI installed and accessible in PATH
- tar (for compression)
- jq (optional, for better metadata display)

**For Docker n8n:**
- Docker installed and running
- Target container running (for basic restore)
- docker-compose (for enhanced restore with --recreate-container)

## 📋 Detailed Usage Guide

### Backup Types

#### 1. Standard Backup (`backup_n8n.sh`)
- Exports workflows and credentials using n8n CLI
- Creates compressed archive with metadata
- Works with both native and Docker installations
- Includes automatic cleanup of old backups

#### 2. Enhanced Docker Backup (`docker_backup.sh`)
- Everything from standard backup PLUS:
- Docker volume backups
- Container configuration and metadata
- Container logs (optional)
- Docker Compose template for recreation
- Bind mount information

### Restore Types

#### 1. Standard Restore (`restore_n8n.sh`)
- Imports workflows and credentials to existing n8n instance
- Verifies encryption key compatibility
- Provides confirmation prompts
- Handles both compressed and directory backups

#### 2. Enhanced Docker Restore (`docker_restore.sh`)
- Everything from standard restore PLUS:
- Volume restoration
- Container recreation from backup configuration
- Docker Compose integration
- Comprehensive status checking

### Management Interface (`manage_n8n.sh`)

The management script provides a unified interface with these features:

- **Interactive Menus**: Easy-to-use menu system
- **Status Checking**: View n8n instance status
- **Backup Listing**: See all available backups with details
- **Configuration Management**: Handle encryption keys and settings
- **Cleanup Tools**: Remove old backups automatically

## 🔧 Configuration Options

### Environment Variables

```bash
# Required for credential portability
export N8N_ENCRYPTION_KEY="your-32-character-key"

# Optional: Custom paths
export N8N_USER_FOLDER="/custom/path/.n8n"
export N8N_CONFIG_FILES="/custom/config/path"
```

### Docker Environment

For Docker containers, ensure these environment variables are set:

```yaml
environment:
  - N8N_ENCRYPTION_KEY=your-32-character-key
  - N8N_HOST=localhost
  - N8N_PORT=5678
  - N8N_PROTOCOL=http
  - DB_TYPE=postgresdb  # or sqlite
  - DB_POSTGRESDB_HOST=postgres
  - DB_POSTGRESDB_PORT=5432
  - DB_POSTGRESDB_DATABASE=n8n
  - DB_POSTGRESDB_USER=n8n
  - DB_POSTGRESDB_PASSWORD=n8n
```

## 🔄 Migration Scenarios

### Scenario 1: Mac Native → Windows Docker

1. **On Mac (Source):**
   ```bash
   export N8N_ENCRYPTION_KEY="your-key-here"
   ./backup_n8n.sh native
   ```

2. **Transfer backup file to Windows machine**

3. **On Windows (Destination):**
   ```bash
   # Set the same encryption key
   set N8N_ENCRYPTION_KEY=your-key-here
   
   # Restore to Docker container
   ./restore_n8n.sh docker native_backup_20240115_143022 n8n
   ```

### Scenario 2: Docker → Docker (Different Machines)

1. **Source Docker:**
   ```bash
   ./docker_backup.sh n8n --include-volumes
   ```

2. **Transfer backup to destination**

3. **Destination Docker:**
   ```bash
   # Option 1: Restore to existing container
   ./docker_restore.sh docker_enhanced_backup_20240115_143022 n8n
   
   # Option 2: Recreate container from backup
   ./docker_restore.sh docker_enhanced_backup_20240115_143022 n8n --recreate-container
   ```

### Scenario 3: Complete Environment Migration

For migrating entire n8n setups including custom configurations:

1. **Create enhanced backup:**
   ```bash
   ./docker_backup.sh n8n --include-volumes --include-logs
   ```

2. **On destination:**
   ```bash
   # This will recreate the entire container with same configuration
   ./docker_restore.sh enhanced_backup_name new_container_name --recreate-container
   ```

## 🛠️ Troubleshooting

### Common Issues

#### 1. "n8n command not found"
**Solution:** Ensure n8n is installed and in PATH
```bash
npm install -g n8n
# or
which n8n
```

#### 2. "Container not found or not running"
**Solution:** Check container status and name
```bash
docker ps -a
./manage_n8n.sh status
```

#### 3. "Credentials not working after restore"
**Solution:** Verify encryption key matches
```bash
echo $N8N_ENCRYPTION_KEY
./manage_n8n.sh config
```

#### 4. "Permission denied" errors
**Solution:** Ensure scripts are executable
```bash
chmod +x scripts/*.sh
```

#### 5. "Backup not found"
**Solution:** List available backups
```bash
./manage_n8n.sh list
```

### Database Compatibility

- **Same database type recommended**: PostgreSQL → PostgreSQL, SQLite → SQLite
- **Cross-database migration**: May create new IDs, potentially breaking workflow links
- **Best practice**: Use the same database type on source and destination

### Volume Permissions

For Docker volumes, ensure proper permissions:
```bash
# Check volume permissions
docker exec -u root container_name ls -la /home/node/.n8n

# Fix permissions if needed
docker exec -u root container_name chown -R node:node /home/node/.n8n
```

## 📊 Backup Metadata

Each backup includes metadata for tracking and verification:

```json
{
  "backup_info": {
    "timestamp": "20240115_143022",
    "date": "2024-01-15T14:30:22-05:00",
    "instance_type": "docker",
    "container_name": "n8n",
    "script_version": "1.0.0"
  },
  "backup_contents": {
    "workflows_count": 15,
    "credentials_file_exists": true,
    "backup_size_mb": "12"
  },
  "restoration_notes": {
    "encryption_key_required": true,
    "compatible_with": ["native", "docker"],
    "restore_command": "./restore_n8n.sh docker backup_name"
  }
}
```

## 🔒 Security Best Practices

1. **Encryption Key Management:**
   - Store keys securely and separately from backups
   - Use the same key across all related instances
   - Back up the key separately from n8n data

2. **Backup Security:**
   - Credentials are exported in decrypted format during backup
   - Secure backup storage location
   - Regular backup rotation and cleanup

3. **Access Control:**
   - Limit access to backup directories
   - Use proper file permissions (600 for key files)
   - Secure transfer methods for backup files

## 🔄 Automation Examples

### Automated Daily Backup (Cron)

```bash
# Add to crontab (crontab -e)
0 2 * * * /path/to/voice-agent-platform/backend/n8n/scripts/backup_n8n.sh docker n8n
```

### Backup Before Updates

```bash
#!/bin/bash
# pre-update-backup.sh
echo "Creating backup before n8n update..."
./backup_n8n.sh docker n8n
echo "Backup complete. Proceeding with update..."
docker pull n8nio/n8n:latest
docker-compose up -d
```

### Monitoring Script

```bash
#!/bin/bash
# monitor-backups.sh
BACKUP_DIR="/path/to/backups"
MAX_AGE_DAYS=7

if [ ! -f "$BACKUP_DIR/$(ls -t $BACKUP_DIR/*.tar.gz | head -1)" ]; then
    echo "WARNING: No recent backups found!"
    # Send alert notification
fi
```

## 📞 Support and Maintenance

### Regular Maintenance Tasks

1. **Weekly:**
   - Check backup integrity
   - Verify encryption key setup
   - Test restore process on staging

2. **Monthly:**
   - Clean up old backups
   - Review backup storage usage
   - Update scripts if needed

3. **Before Major Changes:**
   - Create full enhanced backup
   - Document current configuration
   - Test restore procedure

### Getting Help

1. **Check Status:**
   ```bash
   ./manage_n8n.sh status
   ```

2. **Review Logs:**
   ```bash
   # For Docker containers
   docker logs n8n
   
   # For native installations
   tail -f ~/.n8n/logs/n8n.log
   ```

3. **Validate Configuration:**
   ```bash
   ./manage_n8n.sh config
   ```

## 📈 Version History

- **v1.0.0**: Initial release with full backup/restore functionality
  - Native and Docker support
  - Enhanced Docker backups with volumes
  - Unified management interface
  - Comprehensive error handling and validation

---

## 🤝 Contributing

When modifying these scripts:

1. Test with both native and Docker installations
2. Maintain backward compatibility
3. Update documentation
4. Follow the existing error handling patterns
5. Add appropriate logging and user feedback

---

**Created for Voice Agent Platform** | Last Updated: $(date +"%Y-%m-%d")
