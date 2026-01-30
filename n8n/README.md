# N8N Standalone Instance

This is a standalone N8N workflow automation instance that runs independently on port 5678.

## Quick Start

### Windows
```bash
start.bat
```

### Linux/macOS
```bash
./start.sh
```

## Access

- **URL**: http://localhost:5678
- **Username**: admin
- **Password**: Ivoryt#1

## Key Features

- ✅ **Always Running**: Automatically starts with Docker (restart policy: always)
- 🔄 **Independent**: Runs separately from Voice Agent Platform backend
- 📦 **Persistent Data**: All workflows and credentials are stored in Docker volume
- 🚀 **Port 5678**: Always available on the standard n8n port

## Management

### Start N8N
```bash
# Windows
start.bat

# Linux/macOS
./start.sh
```

### Stop N8N
```bash
# Windows
stop.bat

# Linux/macOS
./stop.sh
```

### View Logs
```bash
docker-compose logs -f n8n
```

### Restart N8N
```bash
docker-compose restart n8n
```

## Data Synchronization

To sync workflows/credentials from Voice Agent Platform backend:

```bash
# Windows
sync-data.bat

# Linux/macOS
./sync-data.sh
```

## Port Information

- **Standalone N8N** (this instance): `http://localhost:5678`
- **Backend N8N** (Voice Agent Platform): `http://localhost:5679`

## Docker Commands

```bash
# Start
docker-compose up -d

# Stop
docker-compose down

# View logs
docker-compose logs -f n8n

# Restart
docker-compose restart n8n

# Access shell
docker exec -it n8n /bin/sh
```

## Notes

- This instance uses **restart: always** policy - it will automatically start when Docker starts
- Data is stored in a Docker volume named `n8n_data`
- To permanently stop auto-start, run: `docker-compose down`
