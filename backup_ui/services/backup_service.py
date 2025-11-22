"""
Backup Service
Handles N8N backup and restore operations by wrapping existing shell scripts
"""
import os
import json
import subprocess
import re
from pathlib import Path
from typing import List, Dict, Optional, Generator
from datetime import datetime


class BackupService:
    """Service for N8N backup and restore operations"""

    def __init__(self):
        # Get the scripts directory
        self.scripts_dir = Path(__file__).parent.parent.parent / 'scripts'
        self.backups_dir = Path(__file__).parent.parent.parent / 'backups'
        self.backups_dir.mkdir(exist_ok=True)

    def create_backup(self, backup_type: str = 'docker',
                     container_name: Optional[str] = None,
                     include_volumes: bool = False,
                     include_logs: bool = False) -> Generator[str, None, None]:
        """
        Create a backup and yield progress updates
        backup_type: 'native', 'docker', or 'enhanced'
        """
        script_name = 'backup_n8n.sh' if backup_type != 'enhanced' else 'docker_backup.sh'
        script_path = self.scripts_dir / script_name

        if not script_path.exists():
            yield f"ERROR: Script not found: {script_path}"
            return

        # Build command
        cmd = ['bash', str(script_path)]

        if backup_type == 'enhanced':
            if container_name:
                cmd.append(container_name)
            if include_volumes:
                cmd.append('--include-volumes')
            if include_logs:
                cmd.append('--include-logs')
        else:
            cmd.append(backup_type)
            if container_name and backup_type == 'docker':
                cmd.append(container_name)

        # Execute script and stream output
        try:
            process = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1,
                universal_newlines=True,
                cwd=self.scripts_dir.parent
            )

            for line in process.stdout:
                # Clean ANSI color codes
                clean_line = self._strip_ansi(line.strip())
                if clean_line:
                    yield clean_line

            process.wait()

            if process.returncode == 0:
                yield "SUCCESS: Backup completed successfully!"
            else:
                yield f"ERROR: Backup failed with exit code {process.returncode}"

        except Exception as e:
            yield f"ERROR: Failed to execute backup: {str(e)}"

    def restore_backup(self, backup_name: str,
                      restore_type: str = 'docker',
                      container_name: Optional[str] = None,
                      recreate_container: bool = False) -> Generator[str, None, None]:
        """
        Restore a backup and yield progress updates
        """
        script_name = 'restore_n8n.sh' if restore_type != 'enhanced' else 'docker_restore.sh'
        script_path = self.scripts_dir / script_name

        if not script_path.exists():
            yield f"ERROR: Script not found: {script_path}"
            return

        # Build command
        cmd = ['bash', str(script_path)]

        if restore_type == 'enhanced':
            cmd.append(backup_name)
            if container_name:
                cmd.append(container_name)
            if recreate_container:
                cmd.append('--recreate-container')
        else:
            cmd.extend([restore_type, backup_name])
            if container_name and restore_type == 'docker':
                cmd.append(container_name)

        # Execute script and stream output
        try:
            # For restore, we need to provide 'y' confirmation
            process = subprocess.Popen(
                cmd,
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1,
                universal_newlines=True,
                cwd=self.scripts_dir.parent
            )

            # Send 'y' for confirmation
            process.stdin.write('y\n')
            process.stdin.flush()

            for line in process.stdout:
                clean_line = self._strip_ansi(line.strip())
                if clean_line:
                    yield clean_line

            process.wait()

            if process.returncode == 0:
                yield "SUCCESS: Restore completed successfully!"
            else:
                yield f"ERROR: Restore failed with exit code {process.returncode}"

        except Exception as e:
            yield f"ERROR: Failed to execute restore: {str(e)}"

    def list_backups(self) -> List[Dict[str, any]]:
        """List all available backups with metadata"""
        backups = []

        if not self.backups_dir.exists():
            return backups

        # Find all backup files and directories
        for item in self.backups_dir.iterdir():
            if item.is_file() and (item.suffix == '.gz' or item.suffix == '.zip'):
                backup_info = self._get_backup_info(item)
                if backup_info:
                    backups.append(backup_info)
            elif item.is_dir() and 'backup' in item.name.lower():
                backup_info = self._get_backup_info(item)
                if backup_info:
                    backups.append(backup_info)

        # Sort by created time (newest first)
        backups.sort(key=lambda x: x['created_timestamp'], reverse=True)

        return backups

    def get_backup_details(self, backup_name: str) -> Optional[Dict[str, any]]:
        """Get detailed information about a specific backup"""
        backup_path = self.backups_dir / backup_name

        if not backup_path.exists():
            # Try with common extensions
            for ext in ['.tar.gz', '.zip']:
                test_path = self.backups_dir / f"{backup_name}{ext}"
                if test_path.exists():
                    backup_path = test_path
                    break

        if not backup_path.exists():
            return None

        return self._get_backup_info(backup_path, detailed=True)

    def delete_backup(self, backup_name: str) -> Dict[str, any]:
        """Delete a backup file or directory"""
        backup_path = self.backups_dir / backup_name

        if not backup_path.exists():
            # Try with extensions
            for ext in ['.tar.gz', '.zip']:
                test_path = self.backups_dir / f"{backup_name}{ext}"
                if test_path.exists():
                    backup_path = test_path
                    break

        if not backup_path.exists():
            return {'success': False, 'error': 'Backup not found'}

        try:
            if backup_path.is_file():
                backup_path.unlink()
            else:
                import shutil
                shutil.rmtree(backup_path)

            return {'success': True, 'message': f'Deleted backup: {backup_name}'}
        except Exception as e:
            return {'success': False, 'error': str(e)}

    def _get_backup_info(self, path: Path, detailed: bool = False) -> Optional[Dict[str, any]]:
        """Extract backup information from path"""
        info = {
            'name': path.name,
            'path': str(path),
            'is_compressed': path.is_file(),
            'size_bytes': 0,
            'size_mb': 0,
            'created_timestamp': 0,
            'created_date': '',
            'backup_type': 'unknown',
            'workflows_count': 0,
            'has_credentials': False
        }

        # Get size
        if path.is_file():
            info['size_bytes'] = path.stat().st_size
        else:
            info['size_bytes'] = sum(f.stat().st_size for f in path.rglob('*') if f.is_file())

        info['size_mb'] = round(info['size_bytes'] / (1024 * 1024), 2)

        # Get creation time
        info['created_timestamp'] = path.stat().st_mtime
        info['created_date'] = datetime.fromtimestamp(info['created_timestamp']).strftime('%Y-%m-%d %H:%M:%S')

        # Determine backup type from name
        name_lower = path.name.lower()
        if 'enhanced' in name_lower:
            info['backup_type'] = 'enhanced_docker'
        elif 'docker' in name_lower:
            info['backup_type'] = 'docker'
        elif 'native' in name_lower:
            info['backup_type'] = 'native'

        # Try to read metadata if available
        metadata_path = None
        if path.is_dir():
            metadata_path = path / 'backup_metadata.json'
            if not metadata_path.exists():
                metadata_path = path / 'enhanced_backup_metadata.json'

        if metadata_path and metadata_path.exists():
            try:
                with open(metadata_path, 'r') as f:
                    metadata = json.load(f)
                    info['workflows_count'] = metadata.get('backup_contents', {}).get('workflows_count', 0)
                    info['has_credentials'] = metadata.get('backup_contents', {}).get('credentials_file_exists', False)
                    if detailed:
                        info['metadata'] = metadata
            except (json.JSONDecodeError, IOError):
                pass

        return info

    def get_storage_usage(self) -> Dict[str, any]:
        """Get storage usage statistics for backups"""
        if not self.backups_dir.exists():
            return {
                'total_backups': 0,
                'total_size_bytes': 0,
                'total_size_mb': 0,
                'total_size_gb': 0,
                'backups_dir': str(self.backups_dir)
            }

        backups = self.list_backups()
        total_size = sum(b['size_bytes'] for b in backups)

        return {
            'total_backups': len(backups),
            'total_size_bytes': total_size,
            'total_size_mb': round(total_size / (1024 * 1024), 2),
            'total_size_gb': round(total_size / (1024 * 1024 * 1024), 2),
            'backups_dir': str(self.backups_dir)
        }

    @staticmethod
    def _strip_ansi(text: str) -> str:
        """Remove ANSI color codes from text"""
        ansi_escape = re.compile(r'\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])')
        return ansi_escape.sub('', text)
