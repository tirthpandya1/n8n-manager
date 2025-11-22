"""
Configuration API Endpoints
"""
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import Optional
import sys
from pathlib import Path

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from services import EncryptionService

router = APIRouter(prefix="/api/config", tags=["config"])
encryption_service = EncryptionService()


class SaveKeyRequest(BaseModel):
    key: str
    location: str = 'custom'  # 'custom' or 'n8n_config'


@router.get("/encryption-key")
async def get_encryption_key():
    """Get current encryption key information (masked)"""
    try:
        key_info = encryption_service.get_encryption_key()
        if key_info is None:
            return {
                "success": False,
                "message": "No encryption key found",
                "key_info": None
            }

        # Remove the actual key from response for security
        response_info = key_info.copy()
        response_info.pop('key', None)

        return {
            "success": True,
            "key_info": response_info
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/encryption-key/generate")
async def generate_encryption_key():
    """Generate a new encryption key"""
    try:
        new_key = encryption_service.generate_new_key()
        return {
            "success": True,
            "key": new_key,
            "masked": encryption_service._mask_key(new_key),
            "length": len(new_key),
            "message": "New key generated. Save it to activate."
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/encryption-key/save")
async def save_encryption_key(request: SaveKeyRequest):
    """Save encryption key to specified location"""
    try:
        # Validate key first
        validation = encryption_service.validate_key(request.key)
        if not validation['valid']:
            return {
                "success": False,
                "error": f"Invalid key: length must be 32 characters, got {validation['length']}"
            }

        result = encryption_service.save_encryption_key(request.key, request.location)
        return result
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/encryption-key/validate")
async def validate_encryption_key(key: str):
    """Validate encryption key format"""
    try:
        validation = encryption_service.validate_key(key)
        return {
            "success": True,
            "validation": validation
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
