"""
Remote Hosts API Endpoints
"""
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import Optional, List
import sys
from pathlib import Path

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from services import RemoteHostService

router = APIRouter(prefix="/api/hosts", tags=["hosts"])
host_service = RemoteHostService()


class AddHostRequest(BaseModel):
    name: str
    type: str = 'ssh'
    host: str
    port: int = 22
    username: str
    auth_type: str = 'password'  # 'password' or 'key'
    password: Optional[str] = None
    ssh_key_path: Optional[str] = None
    n8n_url: Optional[str] = None
    default_instance: str = 'n8n'
    api_key: Optional[str] = None
    enabled: bool = True


class UpdateHostRequest(BaseModel):
    name: Optional[str] = None
    type: Optional[str] = None
    host: Optional[str] = None
    port: Optional[int] = None
    username: Optional[str] = None
    auth_type: Optional[str] = None
    password: Optional[str] = None
    ssh_key_path: Optional[str] = None
    n8n_url: Optional[str] = None
    default_instance: Optional[str] = None
    api_key: Optional[str] = None
    enabled: Optional[bool] = None


@router.get("/")
async def list_hosts():
    """List all configured remote hosts"""
    try:
        hosts = host_service.list_hosts()
        return {"success": True, "hosts": hosts}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/{host_id}")
async def get_host(host_id: str):
    """Get details of a specific host"""
    try:
        host = host_service.get_host(host_id)
        if host is None:
            raise HTTPException(status_code=404, detail="Host not found")
        return {"success": True, "host": host}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/")
async def add_host(request: AddHostRequest):
    """Add a new remote host"""
    try:
        # Validate required fields based on auth type
        if request.auth_type == 'password' and not request.password:
            raise HTTPException(status_code=400, detail="Password required for password authentication")
        if request.auth_type == 'key' and not request.ssh_key_path:
            raise HTTPException(status_code=400, detail="SSH key path required for key authentication")

        # Convert to dict
        host_data = request.dict(exclude_none=True)

        result = host_service.add_host(host_data)

        if not result.get('success'):
            raise HTTPException(status_code=400, detail=result.get('error', 'Failed to add host'))

        return result
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.put("/{host_id}")
async def update_host(host_id: str, request: UpdateHostRequest):
    """Update an existing host"""
    try:
        # Convert to dict, exclude None values
        host_data = request.dict(exclude_none=True)

        result = host_service.update_host(host_id, host_data)

        if not result.get('success'):
            if 'not found' in result.get('error', '').lower():
                raise HTTPException(status_code=404, detail=result.get('error'))
            raise HTTPException(status_code=400, detail=result.get('error', 'Failed to update host'))

        return result
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.delete("/{host_id}")
async def delete_host(host_id: str):
    """Delete a remote host"""
    try:
        result = host_service.delete_host(host_id)

        if not result.get('success'):
            if 'not found' in result.get('error', '').lower():
                raise HTTPException(status_code=404, detail=result.get('error'))
            raise HTTPException(status_code=400, detail=result.get('error', 'Failed to delete host'))

        return result
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/{host_id}/test")
async def test_connection(host_id: str):
    """Test SSH connection to a remote host"""
    try:
        result = host_service.test_connection(host_id)
        return result
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/{host_id}/instances")
async def get_remote_instances(host_id: str):
    """List n8n instances on remote host"""
    try:
        result = host_service.get_remote_instances(host_id)
        return result
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/{host_id}/command")
async def execute_command(host_id: str, command: str):
    """Execute a command on remote host (admin only - use with caution)"""
    try:
        result = host_service.execute_remote_command(host_id, command)
        return result
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
