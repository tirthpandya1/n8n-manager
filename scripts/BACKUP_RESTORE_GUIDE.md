# N8N Backup & Restore Scripts Guide

This guide covers the backup and restore scripts for n8n instances (both native and Docker).

## Features

### Backup Scripts
- **Interactive Container Selector**: Automatically lists all n8n containers and lets you choose
- **Auto-start Containers**: Starts stopped containers automatically before backup
- **Automatic Compression**: Creates compressed archives (tar.gz or zip)
- **Automatic Cleanup**: Keeps only the 10 most recent backups
- **Dual Mode Support**: Works with both native and Docker installations

### Restore Scripts
- **Interactive Backup Selector**: Shows all available backups to choose from
- **Interactive Container Selector**: Lists all n8n containers for easy selection
- **Multiple Archive Formats**: Supports tar.gz, zip, and directory backups
- **Safety Confirmation**: Requires user confirmation before overwriting data
- **Auto-restart**: Automatically restarts Docker containers after restore

---

## Backup Scripts

### Linux/macOS (backup_n8n.sh)

#### Basic Usage

```bash
# Interactive mode - select container from list
./backup_n8n.sh docker

# Specify container directly
./backup_n8n.sh docker backend-n8n-1

# Native installation backup
./backup_n8n.sh native
```

#### What it does:
1. Searches for all containers with 'n8n' in the name
2. If multiple found, shows numbered list for selection
3. If only one found, uses it automatically
4. Starts container if it's stopped
5. Exports workflows and credentials
6. Compresses backup to tar.gz
7. Cleans up old backups (keeps 10 most recent)

---

### Windows (backup_n8n_windows.bat)

#### Basic Usage

```batch
REM Interactive mode - select container from list
backup_n8n_windows.bat docker

REM Specify container directly
backup_n8n_windows.bat docker backend-n8n-1

REM Native installation backup
backup_n8n_windows.bat native
```

#### What it does:
1. Same features as Linux version
2. Uses tar.gz if tar is available (Git Bash/WSL)
3. Falls back to zip if tar not available
4. Supports both compressed and directory backups

---

## Restore Scripts

### Linux/macOS (restore_n8n.sh)

#### Basic Usage

```bash
# Interactive mode - select both backup and container
./restore_n8n.sh docker

# Specify backup, select container
./restore_n8n.sh docker docker_backup_20251016_143022

# Specify both backup and container
./restore_n8n.sh docker docker_backup_20251016_143022 backend-n8n-1

# Native installation restore
./restore_n8n.sh native native_backup_20251016_143022
```

#### Interactive Selectors:

**Backup Selector** (when backup not specified):
```
Looking for available backups...

[1] docker_backup_20251016_143022 (compressed)
[2] docker_backup_20251015_120000 (compressed)
[3] native_backup_20251014_090000 (directory)

Select backup number (1-3): _
```

**Container Selector** (when container not specified):
```
Looking for n8n containers...

[1] backend-n8n-1
[2] n8n-test
[3] my-n8n-instance

Select container number (1-3): _
```

#### What it does:
1. Shows available backups if not specified
2. Shows available containers if not specified
3. Extracts compressed backups automatically
4. Shows backup information (date, size, workflow count)
5. Asks for confirmation before restoring
6. Imports credentials and workflows
7. Restarts Docker container (if applicable)
8. Cleans up temporary files

---

### Windows (restore_n8n_windows.bat)

#### Basic Usage

```batch
REM Interactive mode - select both backup and container
restore_n8n_windows.bat docker

REM Specify backup, select container
restore_n8n_windows.bat docker docker_backup_20251016_143022

REM Specify both backup and container
restore_n8n_windows.bat docker docker_backup_20251016_143022 backend-n8n-1

REM Native installation restore
restore_n8n_windows.bat native native_backup_20251016_143022
```

#### What it does:
- Same features as Linux version
- Supports tar.gz, zip, and directory backups
- Uses PowerShell for zip extraction if tar not available
- Automatically cleans up temporary extraction folders

---

## Backup Structure

Each backup contains:

```
docker_backup_20251016_143022/
├── workflows/
│   ├── workflow_1.json
│   ├── workflow_2.json
│   └── ...
├── credentials.json
└── backup_metadata.json
```

### Metadata Example

```json
{
  "backup_info": {
    "timestamp": "20251016_143022",
    "date": "2025-10-16T14:30:22",
    "instance_type": "docker",
    "container_name": "backend-n8n-1",
    "script_version": "1.0.0"
  },
  "backup_contents": {
    "workflows_count": 15,
    "credentials_file_exists": true,
    "backup_size_mb": "5"
  },
  "restoration_notes": {
    "encryption_key_required": true,
    "compatible_with": ["native", "docker"],
    "restore_command": "./restore_n8n.sh docker docker_backup_20251016_143022"
  }
}
```

---

## Common Scenarios

### Scenario 1: Quick Backup (Interactive)

**Linux:**
```bash
cd /path/to/n8n/scripts
./backup_n8n.sh docker
# Select container from list
```

**Windows:**
```batch
cd C:\path\to\n8n\scripts
backup_n8n_windows.bat docker
REM Select container from list
```

---

### Scenario 2: Scheduled Backup (Automated)

**Linux (cron job):**
```bash
# Add to crontab
0 2 * * * /path/to/n8n/scripts/backup_n8n.sh docker backend-n8n-1
```

**Windows (Task Scheduler):**
```batch
C:\path\to\n8n\scripts\backup_n8n_windows.bat docker backend-n8n-1
```

---

### Scenario 3: Restore After System Failure

**Linux:**
```bash
cd /path/to/n8n/scripts
./restore_n8n.sh docker
# 1. Select backup from list
# 2. Select container from list
# 3. Confirm restoration
```

**Windows:**
```batch
cd C:\path\to\n8n\scripts
restore_n8n_windows.bat docker
REM 1. Select backup from list
REM 2. Select container from list
REM 3. Confirm restoration
```

---

### Scenario 4: Migration to New Server

**On old server:**
```bash
./backup_n8n.sh docker my-n8n-container
# Copy the .tar.gz file to new server
```

**On new server:**
```bash
# Copy backup to backups directory
cp docker_backup_20251016_143022.tar.gz /path/to/n8n/backups/

# Restore
./restore_n8n.sh docker docker_backup_20251016_143022 new-n8n-container
```

---

## Encryption Keys

**Important:** The same encryption key must be used for backup and restore!

### Setting Encryption Key

**Linux/macOS:**
```bash
export N8N_ENCRYPTION_KEY="your-encryption-key-here"
```

**Windows:**
```batch
set N8N_ENCRYPTION_KEY=your-encryption-key-here
```

The scripts will automatically detect the encryption key from:
1. n8n config file (`~/.n8n/config` or `%USERPROFILE%\.n8n\config`)
2. Environment variable `N8N_ENCRYPTION_KEY`

---

## Troubleshooting

### Container Not Found

**Problem:** "ERROR: Container 'backend-n8n-1' not found"

**Solution:**
```bash
# List all containers
docker ps -a

# Use interactive mode to see available n8n containers
./backup_n8n.sh docker
```

---

### No Backups Found

**Problem:** "ERROR: No backups found"

**Solution:** Check backup directory:
```bash
ls -la /path/to/n8n/backups/
```

If empty, create a backup first:
```bash
./backup_n8n.sh docker
```

---

### Extraction Failed

**Problem:** "ERROR: tar command not found"

**Solution (Windows):**
- Install Git for Windows (includes tar)
- Or use WSL
- Script will fall back to zip format

---

### Container Not Running

**Problem:** "WARNING: Container exists but is not running"

**Solution:** Scripts automatically start the container:
```bash
# Container will be started automatically
# Wait 3 seconds for container to initialize
```

---

## Advanced Options

### Manual Cleanup

To manually clean up old backups:

```bash
cd /path/to/n8n/backups
# Keep only 5 most recent
ls -t docker_backup_*.tar.gz | tail -n +6 | xargs rm -f
```

### Verify Backup Contents

```bash
# Extract and view
tar -xzf docker_backup_20251016_143022.tar.gz
cd docker_backup_20251016_143022
cat backup_metadata.json
ls -la workflows/
```

### Custom Backup Location

Edit the scripts to change `BACKUP_BASE_DIR`:

```bash
# In backup_n8n.sh or restore_n8n.sh
BACKUP_BASE_DIR="/custom/backup/path"
```

---

## Best Practices

1. **Regular Backups**: Schedule daily backups using cron (Linux) or Task Scheduler (Windows)
2. **Off-site Storage**: Copy backups to external storage or cloud
3. **Test Restores**: Periodically test restore process on test environment
4. **Keep Encryption Key Safe**: Store encryption key securely (password manager, secrets vault)
5. **Monitor Backup Size**: Check backup directory size regularly
6. **Version Control**: Keep at least 10 recent backups (automatic)
7. **Document Changes**: Note any major workflow changes in backup metadata

---

## Security Notes

- **Credentials are decrypted** during backup (require encryption key)
- **Backups contain sensitive data** (workflows, credentials, API keys)
- **Secure backup storage** (encrypt backup files or store on encrypted volumes)
- **Access control** (restrict access to backup directory)
- **Encryption key protection** (never commit to version control)

---

## Script Locations

```
backend/n8n/scripts/
├── backup_n8n.sh              # Linux/macOS backup script
├── backup_n8n_windows.bat     # Windows backup script
├── restore_n8n.sh             # Linux/macOS restore script
└── restore_n8n_windows.bat    # Windows restore script
```

---

## Support

For issues or questions:
1. Check troubleshooting section above
2. Review script output for error messages
3. Verify Docker/n8n installation
4. Check file permissions (Linux/macOS)
5. Ensure encryption key is set correctly
