# N8N Backup & Restore - Quick Start Guide

## 🎯 Your Setup

Based on the system scan, you have:
- **Native n8n**: Available via `npx n8n` (version 1.97.1)
- **Docker n8n container**: `voice-agent-n8n-1` (n8nio/n8n:latest) - Currently created but not running
- **Backup system**: ✅ Working! Already created a backup with 14 workflows and 5 credentials

## 🚀 Getting Started in 3 Steps

### Step 1: Encryption Key Setup ✅ FULLY AUTOMATED!

**✅ Your encryption key is automatically handled!**

The backup system now **automatically detects and exports** your encryption key using this priority order:

1. **Environment Variable** (`N8N_ENCRYPTION_KEY`) - if already set
2. **N8N Config File** (`~/.n8n/config`) - reads `encryptionKey` field automatically
3. **Fallback Method** - works even without `jq` installed

**Your current key**: `32j1CFVDrUQoQJ6O8o1fUP3tXvT/u66h` (32 characters)

**✅ What's been automated:**
- ✅ **Automatic key detection** from config file
- ✅ **Export to environment** before backup/restore
- ✅ **No manual setup required** - just run the scripts
- ✅ **Works with or without jq** (has fallback method)
- ✅ **Validates key format** and length
- ✅ **Secure key display** (shows only first/last 8 chars)

**⚠️ IMPORTANT**: This exact key (`32j1CFVDrUQoQJ6O8o1fUP3tXvT/u66h`) must be used on any machine where you want to restore the backup!

### Step 2: Create Your First Backup

```bash
cd /Users/T/CursorProjects/voice-agent-platform-final/voice-agent-platform/backend/n8n/scripts

# ✅ ALREADY DONE! You have a working backup: native_backup_20250905_143143.tar.gz
# But here are your options for future backups:

# Option A: Native n8n backup (your current setup with npx)
./backup_n8n.sh native

# Option B: Docker backup (if you switch to using the Docker container)
./backup_n8n.sh docker voice-agent-n8n-1

# Option C: Enhanced Docker backup with volumes and logs
./docker_backup.sh voice-agent-n8n-1 --include-volumes --include-logs

# Option D: Interactive menu (recommended)
./manage_n8n.sh backup
```

### Step 3: Test the System

```bash
# List your backups
./manage_n8n.sh list

# Check system status
./manage_n8n.sh status
```

## 🔄 Migrating to Windows Docker

When you're ready to move to Windows Docker:

### On Mac (Export):
```bash
# Create enhanced backup
./docker_backup.sh voice-agent-n8n-1 --include-volumes --include-logs

# The backup will be saved as: 
# backups/docker_enhanced_backup_YYYYMMDD_HHMMSS.tar.gz
```

### On Windows (Import):
```bash
# 1. Transfer the .tar.gz file to Windows
# 2. Set the same encryption key:
set N8N_ENCRYPTION_KEY=your-exact-same-key-from-mac

# 3. Restore (this will recreate the entire container):
./docker_restore.sh docker_enhanced_backup_YYYYMMDD_HHMMSS n8n --recreate-container
```

## 📋 Common Commands

```bash
# Interactive management (recommended)
./manage_n8n.sh

# Quick backup of your current native setup
./backup_n8n.sh native

# List all backups with details (you already have some!)
./manage_n8n.sh list

# Check what n8n instances are available
./manage_n8n.sh status

# Configuration and encryption key management
./manage_n8n.sh config

# Clean up old backups
./manage_n8n.sh cleanup
```

## 🔧 Your Container Details

- **Container Name**: `voice-agent-n8n-1`
- **Image**: `n8nio/n8n:latest`
- **Status**: Created (you may need to start it)

To start your container:
```bash
docker start voice-agent-n8n-1
```

## ⚡ Pro Tips

1. **Always set the encryption key first** - without it, credentials won't work after restore
2. **Use enhanced backups for complete migrations** - includes volumes and configuration
3. **Test your backups** - try restoring to a test container occasionally
4. **Keep backups secure** - they contain your workflows and credentials in decrypted form
5. **Use the interactive menu** - `./manage_n8n.sh` is the easiest way to get started

## 🆘 Need Help?

- Run `./manage_n8n.sh help` for command overview
- Check `README.md` for detailed documentation
- Run `./verify_setup.sh` to check your system configuration
- Look at the examples in the README for specific migration scenarios

## 📁 File Locations

- **Scripts**: `/Users/T/CursorProjects/voice-agent-platform-final/voice-agent-platform/backend/n8n/scripts/`
- **Backups**: `/Users/T/CursorProjects/voice-agent-platform-final/voice-agent-platform/backend/n8n/backups/`
- **Config**: `/Users/T/CursorProjects/voice-agent-platform-final/voice-agent-platform/backend/n8n/config/`

---

**You're all set!** Start with setting up your encryption key, then create your first backup. 🎉
