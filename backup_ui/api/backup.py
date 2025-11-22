"""
Backup API Endpoints
"""
from fastapi import APIRouter, HTTPException
from fastapi.responses import StreamingResponse, FileResponse
from pydantic import BaseModel
from typing import Optional, List
import json
import sys
from pathlib import Path

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from services import BackupService

router = APIRouter(prefix="/api/backup", tags=["backup"])
backup_service = BackupService()


class CreateBackupRequest(BaseModel):
    backup_type: str = 'docker'  # 'native', 'docker', 'enhanced'
    container_name: Optional[str] = None
    include_volumes: bool = False
    include_logs: bool = False


class RestoreBackupRequest(BaseModel):
    backup_name: str
    restore_type: str = 'docker'  # 'native', 'docker', 'enhanced'
    container_name: Optional[str] = None
    recreate_container: bool = False


@router.get("/list")
async def list_backups():
    """List all available backups"""
    try:
        backups = backup_service.list_backups()
        return {"success": True, "backups": backups}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/details/{backup_name}")
async def get_backup_details(backup_name: str):
    """Get detailed information about a specific backup"""
    try:
        details = backup_service.get_backup_details(backup_name)
        if details is None:
            raise HTTPException(status_code=404, detail="Backup not found")
        return {"success": True, "backup": details}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/create")
async def create_backup(request: CreateBackupRequest):
    """Create a new backup with streaming progress"""
    async def generate():
        try:
            for line in backup_service.create_backup(
                backup_type=request.backup_type,
                container_name=request.container_name,
                include_volumes=request.include_volumes,
                include_logs=request.include_logs
            ):
                yield f"data: {json.dumps({'message': line})}\n\n"
        except Exception as e:
            yield f"data: {json.dumps({'error': str(e)})}\n\n"

    return StreamingResponse(generate(), media_type="text/event-stream")


@router.post("/restore")
async def restore_backup(request: RestoreBackupRequest):
    """Restore a backup with streaming progress"""
    async def generate():
        try:
            for line in backup_service.restore_backup(
                backup_name=request.backup_name,
                restore_type=request.restore_type,
                container_name=request.container_name,
                recreate_container=request.recreate_container
            ):
                yield f"data: {json.dumps({'message': line})}\n\n"
        except Exception as e:
            yield f"data: {json.dumps({'error': str(e)})}\n\n"

    return StreamingResponse(generate(), media_type="text/event-stream")


@router.delete("/delete/{backup_name}")
async def delete_backup(backup_name: str):
    """Delete a backup"""
    try:
        result = backup_service.delete_backup(backup_name)
        if not result['success']:
            raise HTTPException(status_code=404, detail=result.get('error', 'Failed to delete backup'))
        return result
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/download/{backup_name}")
async def download_backup(backup_name: str):
    """Download a backup file"""
    try:
        backup_path = backup_service.backups_dir / backup_name

        if not backup_path.exists():
            # Try with extensions
            for ext in ['.tar.gz', '.zip']:
                test_path = backup_service.backups_dir / f"{backup_name}{ext}"
                if test_path.exists():
                    backup_path = test_path
                    break

        if not backup_path.exists() or not backup_path.is_file():
            raise HTTPException(status_code=404, detail="Backup file not found or is a directory")

        return FileResponse(
            path=backup_path,
            filename=backup_path.name,
            media_type='application/gzip'
        )
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/storage")
async def get_storage_usage():
    """Get storage usage statistics"""
    try:
        usage = backup_service.get_storage_usage()
        return {"success": True, "storage": usage}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
