# N8N Backup Utility - Quick Start Guide

## 🚀 Launch the Backup UI

### Windows
```cmd
cd backend\n8n
start_backup_ui.bat
```

### Linux/macOS
```bash
cd backend/n8n
./start_backup_ui.sh
```

### Access the UI
Open your browser and navigate to:
- **http://localhost:8001**

## 📋 What You'll See

### Dashboard (Home Page)
- System status overview
- Docker container information
- Total backups and storage usage
- Encryption key status
- Recent backups table
- Quick action buttons

### Backups Page
- Create new backups
- View all backups
- Download backups
- Delete old backups
- Monitor backup progress in real-time

### Restore Page
- Select backup to restore
- Choose restore type
- Configure restore options
- Monitor restore progress
- Confirmation dialog for safety

### Configuration Page
- View current encryption key status
- Generate new encryption key
- Save key to config files
- Manage Docker containers
- Restart containers

## 🎯 Common Tasks

### Create Your First Backup

1. Click **Backups** in the navigation
2. Click **Create Backup** button
3. Select backup type (Docker recommended if using Docker)
4. Choose container if multiple available
5. Click **Create Backup**
6. Watch the progress logs
7. Done! Your backup is saved

### Restore from Backup

1. Click **Restore** in the navigation
2. Select a backup from the dropdown
3. Review the backup information
4. Choose restore type
5. Click **Restore Backup**
6. Confirm the action (⚠️ this will overwrite data!)
7. Watch the progress logs
8. Done! Your N8N instance is restored

### Configure Encryption Key

1. Click **Configuration** in the navigation
2. Check current key status
3. Click **Generate Key** if needed
4. Copy the generated key (use the copy button)
5. Choose save location:
   - **Custom**: Saves to project config
   - **N8N Config**: Saves to ~/.n8n/config
6. Click **Save Key**
7. Done! Your encryption key is configured

## 🔧 Prerequisites

✅ Python 3.8 or higher installed
✅ N8N instance (native or Docker)
✅ Docker installed (optional, for Docker backups)

## 📦 What Gets Installed

The startup script automatically:
- Creates a Python virtual environment
- Installs FastAPI and dependencies
- Starts the web server on port 8001

## 🛑 Stopping the Server

Press **CTRL+C** in the terminal where the server is running.

## ⚠️ Important Notes

1. **Encryption Key**: Make sure you have an N8N encryption key configured before creating backups
2. **Confirmation**: Restore operations require confirmation to prevent accidental data loss
3. **Docker Access**: If Docker containers aren't showing, ensure Docker is running and accessible
4. **Port Conflict**: If port 8001 is in use, the script will warn you

## 🆘 Troubleshooting

### "Port 8001 already in use"
Another instance is running or the port is taken. Either:
- Stop the other service
- Kill the existing process
- Choose a different port when starting

### "Docker not available"
- Make sure Docker Desktop is running (Windows/Mac)
- Check Docker service is running (Linux)
- Verify you have Docker permissions

### "Python not found"
- Install Python 3.8+ from python.org
- Make sure Python is in your system PATH
- Try `python3` instead of `python`

### Backup/Restore fails
- Check the progress logs for error messages
- Ensure N8N encryption key is configured
- Verify script permissions (Linux/Mac)
- Check N8N instance is accessible

## 📚 Full Documentation

See `backend/n8n/backup_ui/README.md` for complete documentation including:
- Detailed feature descriptions
- API endpoint reference
- Architecture overview
- Development guide
- Security considerations
- Production deployment

## 🎉 That's It!

You now have a simple, powerful web interface for managing your N8N backups. No more command-line hassle!

---

**Need Help?** Check the full README or review the existing N8N backup scripts documentation.
