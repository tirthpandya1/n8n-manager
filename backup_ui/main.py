"""
N8N Backup Utility - FastAPI Application
A simple web UI for managing N8N backups and restores
"""
from fastapi import FastAPI, Request
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from pathlib import Path

from api import backup_router, config_router, status_router, hosts_router

# Initialize FastAPI app
app = FastAPI(
    title="N8N Backup Utility",
    description="Simple web interface for N8N backup and restore operations",
    version="1.0.0"
)

# Setup paths
BASE_DIR = Path(__file__).resolve().parent
STATIC_DIR = BASE_DIR / "static"
TEMPLATES_DIR = BASE_DIR / "templates"

# Mount static files
app.mount("/static", StaticFiles(directory=str(STATIC_DIR)), name="static")

# Setup templates
templates = Jinja2Templates(directory=str(TEMPLATES_DIR))

# Include API routers
app.include_router(backup_router)
app.include_router(config_router)
app.include_router(status_router)
app.include_router(hosts_router)


# Web UI Routes
@app.get("/", response_class=HTMLResponse)
async def index(request: Request):
    """Dashboard page"""
    return templates.TemplateResponse("index.html", {"request": request})


@app.get("/backup", response_class=HTMLResponse)
async def backup_page(request: Request):
    """Backup management page"""
    return templates.TemplateResponse("backup.html", {"request": request})


@app.get("/restore", response_class=HTMLResponse)
async def restore_page(request: Request):
    """Restore page"""
    return templates.TemplateResponse("restore.html", {"request": request})


@app.get("/config", response_class=HTMLResponse)
async def config_page(request: Request):
    """Configuration page"""
    return templates.TemplateResponse("config.html", {"request": request})


@app.get("/hosts", response_class=HTMLResponse)
async def hosts_page(request: Request):
    """Remote hosts management page"""
    return templates.TemplateResponse("hosts.html", {"request": request})


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8001)
