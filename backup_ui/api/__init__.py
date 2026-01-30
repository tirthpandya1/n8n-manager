from .backup import router as backup_router
from .config import router as config_router
from .status import router as status_router
from .hosts import router as hosts_router

__all__ = ['backup_router', 'config_router', 'status_router', 'hosts_router']
