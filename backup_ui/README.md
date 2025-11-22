# N8N Backup Utility

A simple, lightweight web interface for managing N8N backups and restores. Built with FastAPI and Tailwind CSS, this utility provides an easy-to-use UI for the existing N8N backup scripts.

## Features

- 📊 **Dashboard**: View system status, backup statistics, and recent backups at a glance
- 💾 **Backup Management**: Create, list, download, and delete backups
- 🔄 **Restore Operations**: Restore from any backup with real-time progress tracking
- 🔐 **Encryption Key Management**: Generate, view, and configure N8N encryption keys
- 🐳 **Docker Integration**: Detect and manage N8N Docker containers
- 📡 **Real-time Progress**: Stream backup/restore progress with Server-Sent Events
- 🎨 **Modern UI**: Clean, responsive interface built with Tailwind CSS

## Requirements

- Python 3.8 or higher
- N8N instance (native or Docker)
- Docker (optional, for Docker-based N8N instances)

## Quick Start

### Linux/macOS

```bash
cd backend/n8n
./start_backup_ui.sh
```

### Windows

```cmd
cd backend\n8n
start_backup_ui.bat
```

The web interface will be available at **http://localhost:8001**

## Installation

### Automatic (Recommended)

The startup scripts will automatically:
1. Create a virtual environment
2. Install all dependencies
3. Start the FastAPI server

### Manual Installation

```bash
cd backend/n8n/backup_ui

# Create virtual environment
python3 -m venv venv

# Activate virtual environment
# Linux/macOS:
source venv/bin/activate
# Windows:
venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Start server
python -m uvicorn main:app --host 0.0.0.0 --port 8001
```

## Usage Guide

### Dashboard

The dashboard provides an overview of your backup system:

- **Docker Status**: Shows if Docker is available and lists N8N containers
- **Total Backups**: Number of available backups
- **Storage Used**: Total space used by backups
- **Encryption Key**: Status of your N8N encryption key
- **Recent Backups**: Table showing the 5 most recent backups
- **Quick Actions**: Direct links to create backup, restore, and configure

### Creating Backups

1. Navigate to the **Backups** page
2. Click **Create Backup**
3. Choose backup type:
   - **Native N8N**: For native N8N installations
   - **Docker (Standard)**: Standard Docker backup
   - **Docker (Enhanced)**: Includes volumes and logs
4. Select Docker container (if applicable)
5. Configure options (for Enhanced backups):
   - Include Docker volumes
   - Include container logs
6. Click **Create Backup**
7. Monitor progress in real-time

### Restoring Backups

1. Navigate to the **Restore** page
2. Select a backup from the dropdown
3. Review backup information
4. Choose restore type (Native/Docker/Enhanced)
5. Select target container (if applicable)
6. Configure options (for Enhanced restores):
   - Recreate container from backup
7. Click **Restore Backup**
8. Confirm the action
9. Monitor progress in real-time

### Managing Encryption Keys

1. Navigate to the **Configuration** page
2. View current key status:
   - Key source (environment/config file)
   - Masked key value
   - Key length and validation
3. Generate new key:
   - Click **Generate Key**
   - Copy the generated key
   - Choose save location:
     - Custom location: `backend/n8n/config/.n8n_encryption_key`
     - N8N config: `~/.n8n/config`
   - Click **Save Key**

### Managing Docker Containers

The Configuration page also shows all N8N Docker containers:

- View container status (running/stopped)
- View container image
- Restart containers directly from the UI

## Architecture

### Directory Structure

```
backup_ui/
├── main.py                 # FastAPI application entry point
├── requirements.txt        # Python dependencies
├── api/                    # API endpoints
│   ├── backup.py          # Backup/restore operations
│   ├── config.py          # Encryption key management
│   └── status.py          # System status & Docker info
├── services/              # Business logic layer
│   ├── backup_service.py  # Backup operations (wraps scripts)
│   ├── docker_service.py  # Docker container operations
│   └── encryption_service.py # Encryption key management
├── templates/             # HTML templates (Jinja2)
│   ├── base.html         # Base template with navigation
│   ├── index.html        # Dashboard
│   ├── backup.html       # Backup management
│   ├── restore.html      # Restore interface
│   └── config.html       # Configuration
└── static/               # Static assets
    ├── css/
    │   └── styles.css    # Custom styles
    └── js/
        └── app.js        # Frontend utilities
```

### Technology Stack

**Backend:**
- **FastAPI**: Modern Python web framework
- **Uvicorn**: ASGI server
- **Python subprocess**: Execute bash scripts
- **Server-Sent Events**: Real-time progress streaming

**Frontend:**
- **Tailwind CSS**: Utility-first CSS framework (via CDN)
- **Alpine.js**: Lightweight JavaScript framework (via CDN)
- **HTMX**: HTML-over-the-wire (via CDN)
- **Vanilla JavaScript**: Toast notifications and utilities

**Integration:**
- Wraps existing bash scripts (`backup_n8n.sh`, `restore_n8n.sh`, etc.)
- Reads backup metadata JSON files
- Interacts with Docker CLI for container management

## API Endpoints

### Backup Operations

- `GET /api/backup/list` - List all backups
- `GET /api/backup/details/{name}` - Get backup details
- `POST /api/backup/create` - Create new backup (SSE stream)
- `POST /api/backup/restore` - Restore backup (SSE stream)
- `DELETE /api/backup/delete/{name}` - Delete backup
- `GET /api/backup/download/{name}` - Download backup file
- `GET /api/backup/storage` - Get storage usage

### Configuration

- `GET /api/config/encryption-key` - Get key info (masked)
- `POST /api/config/encryption-key/generate` - Generate new key
- `POST /api/config/encryption-key/save` - Save key to config
- `POST /api/config/encryption-key/validate` - Validate key format

### Status

- `GET /api/status/docker` - Docker status and containers
- `GET /api/status/container/{name}` - Container details
- `POST /api/status/container/{name}/start` - Start container
- `POST /api/status/container/{name}/stop` - Stop container
- `POST /api/status/container/{name}/restart` - Restart container
- `GET /api/status/health` - Health check

### Web Pages

- `GET /` - Dashboard
- `GET /backup` - Backup management
- `GET /restore` - Restore interface
- `GET /config` - Configuration

## Configuration

The utility uses the existing N8N backup scripts and configuration:

- **Backup directory**: `backend/n8n/backups/`
- **Scripts directory**: `backend/n8n/scripts/`
- **Config directory**: `backend/n8n/config/`
- **Encryption key sources**:
  1. Environment variable: `N8N_ENCRYPTION_KEY`
  2. N8N config: `~/.n8n/config`
  3. Custom config: `backend/n8n/config/.n8n_encryption_key`

## Security Considerations

1. **Encryption Key Protection**:
   - Keys are masked in the UI (show only first/last 8 chars)
   - Keys are never logged or exposed in API responses
   - Config files have restrictive permissions (0600)

2. **Access Control**:
   - Currently no authentication (standalone service)
   - Intended for local use only (localhost:8001)
   - For production, add authentication middleware

3. **File Operations**:
   - All file paths are validated
   - Directory traversal is prevented
   - Only backup-related operations allowed

## Troubleshooting

### Port Already in Use

If port 8001 is already in use:

```bash
# Find process using port 8001
# Linux/macOS:
lsof -i :8001
# Windows:
netstat -ano | findstr :8001

# Kill the process or use a different port
python -m uvicorn main:app --host 0.0.0.0 --port 8002
```

### Docker Not Available

If Docker containers aren't showing:

1. Ensure Docker is installed and running
2. Check Docker permissions (user should be in `docker` group)
3. Try running: `docker ps` to verify access

### Backup Script Errors

If backups fail:

1. Check script permissions: `ls -l ../scripts/`
2. Ensure scripts are executable: `chmod +x ../scripts/*.sh`
3. Review script output in the progress log
4. Check N8N encryption key is configured

### Python Module Errors

If dependencies fail to install:

```bash
# Upgrade pip
python -m pip install --upgrade pip

# Install dependencies with verbose output
pip install -r requirements.txt -v

# Try individual packages
pip install fastapi uvicorn jinja2 python-multipart aiofiles
```

## Development

### Running in Development Mode

```bash
# Auto-reload on code changes
python -m uvicorn main:app --reload --host 0.0.0.0 --port 8001

# With debug logging
python -m uvicorn main:app --reload --log-level debug
```

### Adding New Features

1. **New API endpoint**: Add to `api/` directory
2. **New service**: Add to `services/` directory
3. **New page**: Add template to `templates/`
4. **Register routes**: Import and include router in `main.py`

### Testing

```bash
# Test backup service
python -c "from services.backup_service import BackupService; s = BackupService(); print(s.list_backups())"

# Test Docker service
python -c "from services.docker_service import DockerService; s = DockerService(); print(s.list_n8n_containers())"

# Test encryption service
python -c "from services.encryption_service import EncryptionService; s = EncryptionService(); print(s.get_encryption_key())"
```

## Production Deployment

For production use:

1. **Add Authentication**:
   ```python
   # Add to main.py
   from fastapi.security import HTTPBasic, HTTPBasicCredentials
   security = HTTPBasic()
   ```

2. **Use Production Server**:
   ```bash
   # Use Gunicorn with Uvicorn workers
   pip install gunicorn
   gunicorn main:app -w 4 -k uvicorn.workers.UvicornWorker --bind 0.0.0.0:8001
   ```

3. **Add HTTPS**:
   - Use reverse proxy (Nginx/Apache)
   - Or use Uvicorn with SSL: `--ssl-keyfile=key.pem --ssl-certfile=cert.pem`

4. **Environment Variables**:
   ```bash
   export N8N_BACKUP_UI_HOST=0.0.0.0
   export N8N_BACKUP_UI_PORT=8001
   export N8N_ENCRYPTION_KEY=your_32_char_key
   ```

## Contributing

This utility is part of the Voice Agent Platform. To contribute:

1. Test changes thoroughly
2. Follow existing code style
3. Update documentation
4. Add comments for complex logic

## License

Part of the Voice Agent Platform project.

## Support

For issues or questions:

1. Check the troubleshooting section
2. Review existing N8N backup documentation in `backend/n8n/`
3. Check script logs in backup progress output

## Changelog

### Version 1.0.0 (Initial Release)

- Dashboard with system overview
- Backup creation with real-time progress
- Restore operations with confirmation
- Encryption key management
- Docker container management
- Backup file management (list, download, delete)
- Storage usage statistics
- Responsive UI with Tailwind CSS
- Toast notifications
- Server-Sent Events for streaming progress

## Future Enhancements

Potential improvements:

- [ ] Scheduled backups (cron integration)
- [ ] Backup retention policies
- [ ] Email notifications
- [ ] Backup verification/integrity checks
- [ ] Multi-user authentication
- [ ] Backup comparison/diff tool
- [ ] Export/import configuration
- [ ] API documentation (OpenAPI/Swagger)
- [ ] Dark mode toggle
- [ ] Backup compression options
- [ ] Remote backup storage (S3, etc.)
