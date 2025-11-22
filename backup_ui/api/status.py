"""
Status API Endpoints
"""
from fastapi import APIRouter, HTTPException
from typing import Optional
import sys
from pathlib import Path

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from services import DockerService

router = APIRouter(prefix="/api/status", tags=["status"])
docker_service = DockerService()


@router.get("/docker")
async def get_docker_status():
    """Check if Docker is available and list N8N containers"""
    try:
        is_available = docker_service.is_docker_available()
        containers = []

        if is_available:
            containers = docker_service.list_n8n_containers()

        return {
            "success": True,
            "docker_available": is_available,
            "containers": containers,
            "container_count": len(containers)
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/container/{container_name}")
async def get_container_status(container_name: str):
    """Get status of a specific container"""
    try:
        status = docker_service.get_container_status(container_name)
        if status is None:
            raise HTTPException(status_code=404, detail="Container not found")

        return {
            "success": True,
            "container": status
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/container/{container_name}/start")
async def start_container(container_name: str):
    """Start a stopped container"""
    try:
        success = docker_service.start_container(container_name)
        if not success:
            raise HTTPException(status_code=500, detail="Failed to start container")

        return {
            "success": True,
            "message": f"Container {container_name} started successfully"
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/container/{container_name}/stop")
async def stop_container(container_name: str):
    """Stop a running container"""
    try:
        success = docker_service.stop_container(container_name)
        if not success:
            raise HTTPException(status_code=500, detail="Failed to stop container")

        return {
            "success": True,
            "message": f"Container {container_name} stopped successfully"
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/container/{container_name}/restart")
async def restart_container(container_name: str):
    """Restart a container"""
    try:
        success = docker_service.restart_container(container_name)
        if not success:
            raise HTTPException(status_code=500, detail="Failed to restart container")

        return {
            "success": True,
            "message": f"Container {container_name} restarted successfully"
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/health")
async def health_check():
    """Health check endpoint"""
    return {
        "success": True,
        "status": "healthy",
        "service": "N8N Backup Utility"
    }
