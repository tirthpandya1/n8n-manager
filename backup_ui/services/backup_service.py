"""
Backup Service
Handles N8N backup and restore operations with cross-platform support and n8n v2 API integration
"""
import os
import json
import subprocess
import re
import platform
from services.remote_host_service import RemoteHostService
import requests
from pathlib import Path
from typing import List, Dict, Optional, Generator
from datetime import datetime
import tempfile


class BackupService:
    """Service for N8N backup and restore operations"""

    def __init__(self):
        # Get the scripts directory
        self.scripts_dir = Path(__file__).parent.parent.parent / 'scripts'
        self.backups_dir = Path(__file__).parent.parent.parent / 'backups'
        self.backups_dir.mkdir(exist_ok=True)
        self.is_windows = platform.system() == 'Windows'
        self.remote_host_service = RemoteHostService()

    def detect_n8n_version(self, container_name: str = 'n8n') -> Dict[str, any]:
        """Detect n8n version and determine if it's v2+"""
        try:
            if self.is_windows:
                cmd = ['cmd.exe', '/c', f'docker exec {container_name} n8n --version']
            else:
                cmd = ['docker', 'exec', container_name, 'n8n', '--version']

            result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
            if result.returncode == 0:
                version = result.stdout.strip()
                major_version = int(version.split('.')[0])
                return {
                    'version': version,
                    'major_version': major_version,
                    'is_v2_plus': major_version >= 2,
                    'success': True
                }
        except Exception as e:
            return {
                'success': False,
                'error': str(e)
            }

        return {'success': False, 'error': 'Could not detect n8n version'}

    def create_backup(self, backup_type: str = 'docker',
                     container_name: Optional[str] = None,
                     include_volumes: bool = False,
                     include_logs: bool = False,
                     host_id: Optional[str] = None) -> Generator[str, None, None]:
        """
        Create a backup and yield progress updates
        backup_type: 'native', 'docker', or 'enhanced'
        """
        if host_id:
            yield from self._backup_remote(host_id, backup_type, container_name, include_volumes, include_logs)
            return
        # Select appropriate script based on OS
        if backup_type == 'enhanced':
            script_name = 'docker_backup.sh' if not self.is_windows else 'docker_backup.bat'
        else:
            script_name = 'backup_n8n.sh' if not self.is_windows else 'backup_n8n_windows.bat'

        script_path = self.scripts_dir / script_name

        if not script_path.exists():
            yield f"ERROR: Script not found: {script_path}"
            return

        # Build command based on OS
        if self.is_windows:
            cmd = ['cmd.exe', '/c', str(script_path)]
        else:
            cmd = ['bash', str(script_path)]

        if backup_type == 'enhanced':
            if container_name:
                cmd.append(container_name)
            if include_volumes:
                cmd.append('--include-volumes')
            if include_logs:
                cmd.append('--include-logs')
            if self.is_windows:
                cmd.append('--non-interactive')
        else:
            if self.is_windows:
                cmd.append('--non-interactive')
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
                       recreate_container: bool = False,
                       api_key: Optional[str] = None,
                       n8n_url: str = 'http://localhost:5678',
                       host_id: Optional[str] = None) -> Generator[str, None, None]:
        """
        Restore a backup and yield progress updates
        Supports both local and remote restore, CLI and API-based (for n8n v2+)
        """
        if host_id:
            yield from self._restore_remote(backup_name, restore_type, container_name, recreate_container, api_key, n8n_url, host_id)
            return

        # Detect n8n version if container name provided
        use_api = False
        if container_name:
            yield "Detecting n8n version..."
            version_info = self.detect_n8n_version(container_name)

            if version_info.get('success') and version_info.get('is_v2_plus'):
                yield f"Detected n8n v{version_info['version']} (v2+)"

                if api_key:
                    yield "Using API-based restore for v2..."
                    use_api = True
                    for line in self._restore_via_api(backup_name, api_key, n8n_url):
                        yield line
                    return
                else:
                    yield "WARNING: n8n v2 detected but no API key provided"
                    yield "API-based restore is recommended for v2. Please provide an API key."
                    yield "Attempting CLI restore (may have issues with v2)..."

        # CLI-based restore (fallback or v1)
        if restore_type == 'enhanced':
            script_name = 'docker_restore.sh' if not self.is_windows else 'docker_restore.bat'
        else:
            script_name = 'restore_n8n.sh' if not self.is_windows else 'restore_n8n_windows.bat'
            
        script_path = self.scripts_dir / script_name

        if not script_path.exists():
            yield f"ERROR: Script not found: {script_path}"
            return

        # Build command
        if self.is_windows:
            cmd = ['cmd.exe', '/c', str(script_path)]
            cmd.append('--non-interactive')
        else:
            cmd = ['bash', str(script_path)]

        # Strip extension from backup_name for scripts
        clean_backup_name = backup_name
        if clean_backup_name.endswith('.tar.gz'):
            clean_backup_name = clean_backup_name[:-7]
        elif clean_backup_name.endswith('.zip'):
            clean_backup_name = clean_backup_name[:-4]

        if restore_type == 'enhanced':
            cmd.append(clean_backup_name)
            if container_name:
                cmd.append(container_name)
            if recreate_container:
                cmd.append('--recreate-container')
        else:
            cmd.extend([restore_type, clean_backup_name])
            if container_name and restore_type == 'docker':
                cmd.append(container_name)

        # Execute script and stream output
        try:
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

    def _restore_via_api(self, backup_name: str, api_key: str, n8n_url: str) -> Generator[str, None, None]:
        """Restore workflows via n8n API (for v2+)"""
        try:
            # Find the workflows directory in the backup
            backup_path = self.backups_dir / backup_name

            if not backup_path.exists():
                # Try with extensions
                for ext in ['.tar.gz', '.zip']:
                    test_path = self.backups_dir / f"{backup_name}{ext}"
                    if test_path.exists():
                        backup_path = test_path
                        break

            if not backup_path.exists():
                yield f"ERROR: Backup not found: {backup_name}"
                return

            # Extract if compressed
            workflows_dir = None
            if backup_path.is_file():
                yield f"Extracting backup..."
                import tempfile
                import zipfile
                import tarfile

                temp_dir = Path(tempfile.mkdtemp())
                if backup_path.suffix == '.zip':
                    with zipfile.ZipFile(backup_path, 'r') as zip_ref:
                        zip_ref.extractall(temp_dir)
                else:
                    with tarfile.open(backup_path, 'r:gz') as tar:
                        tar.extractall(temp_dir)

                # Find workflows directory
                for item in temp_dir.rglob('workflows'):
                    if item.is_dir():
                        workflows_dir = item
                        break
            else:
                workflows_dir = backup_path / 'workflows'

            if not workflows_dir or not workflows_dir.exists():
                yield "ERROR: Workflows directory not found in backup"
                return

            # Import workflows via API
            yield f"Found workflows directory: {workflows_dir}"

            workflow_files = list(workflows_dir.glob('*.json'))
            total = len(workflow_files)
            success = 0
            failed = 0

            yield f"Importing {total} workflows via API..."

            for i, workflow_file in enumerate(workflow_files, 1):
                yield f"[{i}/{total}] Importing: {workflow_file.name}..."

                try:
                    with open(workflow_file, 'r', encoding='utf-8') as f:
                        workflow_data = json.load(f)

                    # Clean workflow data for API
                    clean_workflow = self._prepare_workflow_for_api(workflow_data)

                    # Send to API
                    response = requests.post(
                        f"{n8n_url}/api/v1/workflows",
                        headers={
                            'X-N8N-API-KEY': api_key,
                            'Content-Type': 'application/json'
                        },
                        json=clean_workflow,
                        timeout=30
                    )

                    if response.status_code in [200, 201]:
                        yield f"  ✓ {workflow_file.name} imported successfully"
                        success += 1
                    else:
                        yield f"  ✗ {workflow_file.name} failed: HTTP {response.status_code}"
                        failed += 1

                except Exception as e:
                    yield f"  ✗ {workflow_file.name} error: {str(e)}"
                    failed += 1

            yield ""
            yield "=" * 60
            yield f"Import Summary: {success} succeeded, {failed} failed"
            yield "=" * 60

        except Exception as e:
            yield f"ERROR: API restore failed: {str(e)}"

    def _prepare_workflow_for_api(self, workflow_data: dict) -> dict:
        """Prepare workflow data for n8n v2 API"""
        # Only keep allowed fields
        allowed_fields = ['name', 'nodes', 'connections', 'settings', 'staticData']
        clean_workflow = {
            key: value for key, value in workflow_data.items()
            if key in allowed_fields
        }

        # Ensure required fields
        if 'name' not in clean_workflow or not clean_workflow['name']:
            clean_workflow['name'] = 'Imported Workflow'
        if 'nodes' not in clean_workflow:
            clean_workflow['nodes'] = []
        if 'connections' not in clean_workflow:
            clean_workflow['connections'] = {}
        if 'settings' not in clean_workflow or not isinstance(clean_workflow.get('settings'), dict):
            clean_workflow['settings'] = {}

        return clean_workflow

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
        """Remove ANSI color codes and other escape sequences from text"""
        import re
        # Standard regex for ANSI escape sequences
        ansi_escape = re.compile(r'(?:\x1B[@-_][0-?]*[ -/]*[@-~])')
        return ansi_escape.sub('', text).strip()

    def _restore_remote(self, backup_name: str, restore_type: str, container_name: Optional[str], 
                       recreate_container: bool, api_key: Optional[str], n8n_url: str, 
                       host_id: str) -> Generator[str, None, None]:
        """Handle restoration to a remote host"""
        yield f"INFO: Starting remote restore to host {host_id} (Zero-Install Mode)..."
        
        # 1. Identify backup file
        backup_file = None
        for ext in ['', '.tar.gz', '.zip']:
            path = self.backups_dir / f"{backup_name}{ext}"
            if path.exists() and path.is_file():
                backup_file = path
                break
        
        if not backup_file:
            yield f"ERROR: Backup file {backup_name} not found or is a directory"
            return

        remote_backup_path = f"/tmp/{backup_file.name}"
        
        # 2. Upload scripts and backup to remote
        yield f"INFO: Uploading restore scripts to remote host..."
        
        scripts_to_upload = ['restore_n8n.sh', 'docker_restore.sh']
        for script_name in scripts_to_upload:
            local_script = self.scripts_dir / script_name
            if local_script.exists():
                # Read with universal newlines and write as LF
                with open(local_script, 'r', encoding='utf-8', errors='ignore') as f:
                    content = f.read()
                
                # Convert to LF
                content = content.replace('\r\n', '\n')
                
                # Create a temporary file for the normalized script
                with tempfile.NamedTemporaryFile(mode='w', suffix='.sh', delete=False, newline='\n', encoding='utf-8') as tf:
                    tf.write(content)
                    temp_path = tf.name
                
                try:
                    self.remote_host_service.upload_file(host_id, temp_path, f"/tmp/{script_name}")
                finally:
                    if os.path.exists(temp_path):
                        os.unlink(temp_path)
        
        yield f"INFO: Uploading backup {backup_file.name} to remote host..."
        upload_result = self.remote_host_service.upload_file(host_id, str(backup_file), remote_backup_path)
        if not upload_result.get('success'):
            yield f"ERROR: Failed to upload backup: {upload_result.get('error')}"
            return
        yield "SUCCESS: Backup uploaded successfully."

        # 3. Build remote command
        # On remote hosts (usually Linux), we use .sh scripts
        backup_name_no_ext = backup_file.name
        if backup_name_no_ext.endswith('.tar.gz'):
            backup_name_no_ext = backup_name_no_ext[:-7]
        elif backup_name_no_ext.endswith('.zip'):
            backup_name_no_ext = backup_name_no_ext[:-4]

        # Make scripts executable and run from /tmp using N8N_BACKUP_DIR override
        setup_cmd = "chmod +x /tmp/restore_n8n.sh /tmp/docker_restore.sh"
        
        if restore_type == 'enhanced':
            script = "docker_restore.sh"
            restore_cmd = f"N8N_BACKUP_DIR=/tmp bash /tmp/{script} {backup_name_no_ext} --non-interactive"
            if container_name:
                restore_cmd += f" {container_name}"
            if recreate_container:
                restore_cmd += " --recreate-container"
        else:
            script = "restore_n8n.sh"
            restore_cmd = f"N8N_BACKUP_DIR=/tmp bash /tmp/{script} --non-interactive {restore_type} {backup_name_no_ext}"
            if container_name:
                restore_cmd += f" {container_name}"
        
        full_cmd = f"{setup_cmd} && {restore_cmd}"

        yield f"INFO: Executing remote restore command: {full_cmd}"
        
        # 4. Execute remote restore
        result = self.remote_host_service.execute_remote_command(host_id, full_cmd, timeout=300)
        
        if result.get('output'):
            for line in result['output'].split('\n'):
                clean_line = self._strip_ansi(line.strip())
                if clean_line: yield clean_line
                
        if result.get('error'):
            for line in result['error'].split('\n'):
                clean_line = self._strip_ansi(line.strip())
                if clean_line: yield f"REMOTE ERROR: {clean_line}"

        if result.get('success'):
            yield "SUCCESS: Remote restore completed successfully!"
        else:
            yield f"ERROR: Remote restore failed with exit code {result.get('exit_code')}"
            
        # Cleanup remote /tmp
        cleanup_cmd = f"rm {remote_backup_path} /tmp/restore_n8n.sh /tmp/docker_restore.sh"
        self.remote_host_service.execute_remote_command(host_id, cleanup_cmd)

    def _backup_remote(self, host_id: str, backup_type: str,
                      container_name: Optional[str] = None,
                      include_volumes: bool = False,
                      include_logs: bool = False) -> Generator[str, None, None]:
        """Handle backup from a remote host"""
        yield f"INFO: Starting remote backup from host {host_id}..."
        
        # 1. Upload scripts to remote
        yield f"INFO: Uploading backup scripts to remote host..."
        
        scripts_to_upload = ['backup_n8n.sh', 'docker_backup.sh']
        for script_name in scripts_to_upload:
            local_script = self.scripts_dir / script_name
            if local_script.exists():
                with open(local_script, 'r', encoding='utf-8', errors='ignore') as f:
                    content = f.read()
                
                # Convert to LF
                content = content.replace('\r\n', '\n')
                
                with tempfile.NamedTemporaryFile(mode='w', suffix='.sh', delete=False, newline='\n', encoding='utf-8') as tf:
                    tf.write(content)
                    temp_path = tf.name
                
                try:
                    self.remote_host_service.upload_file(host_id, temp_path, f"/tmp/{script_name}")
                finally:
                    if os.path.exists(temp_path):
                        os.unlink(temp_path)

        # 2. Build remote command
        setup_cmd = "chmod +x /tmp/backup_n8n.sh /tmp/docker_backup.sh"
        
        if backup_type == 'enhanced':
            script = "docker_backup.sh"
            backup_cmd = f"N8N_BACKUP_DIR=/tmp bash /tmp/{script} {container_name or 'n8n'}"
            if include_volumes: backup_cmd += " --include-volumes"
            if include_logs: backup_cmd += " --include-logs"
        else:
            script = "backup_n8n.sh"
            backup_cmd = f"N8N_BACKUP_DIR=/tmp bash /tmp/{script} {backup_type}"
            if container_name and backup_type == 'docker':
                backup_cmd += f" {container_name}"
        
        full_cmd = f"{setup_cmd} && {backup_cmd}"
        
        yield f"INFO: Executing remote backup command: {full_cmd}"
        
        # 3. Execute remote backup
        result = self.remote_host_service.execute_remote_command(host_id, full_cmd, timeout=300)
        
        backup_filename = None
        if result.get('output'):
            for line in result['output'].split('\n'):
                clean_line = self._strip_ansi(line.strip())
                if clean_line: 
                    yield clean_line
                    # Try to find the backup filename
                    if "Backup compressed to:" in clean_line:
                        backup_filename = clean_line.split("Backup compressed to:")[1].strip()
                    elif "Enhanced backup compressed to:" in clean_line:
                        backup_filename = clean_line.split("Enhanced backup compressed to:")[1].strip()

        if result.get('error'):
            for line in result['error'].split('\n'):
                clean_line = self._strip_ansi(line.strip())
                if clean_line: yield f"REMOTE ERROR: {clean_line}"

        if not result.get('success') or not backup_filename:
            yield f"ERROR: Remote backup failed (exit code: {result.get('exit_code')})"
            return

        # 4. Download backup from remote
        remote_backup_path = f"/tmp/{backup_filename}"
        local_backup_path = self.backups_dir / backup_filename
        
        yield f"INFO: Downloading backup {backup_filename} from remote host..."
        download_result = self.remote_host_service.download_file(host_id, remote_backup_path, str(local_backup_path))
        
        if download_result.get('success'):
            yield f"SUCCESS: Backup downloaded to {local_backup_path}"
        else:
            yield f"ERROR: Failed to download backup: {download_result.get('error')}"

        # 5. Cleanup remote host
        yield "INFO: Cleaning up remote temporary files..."
        cleanup_cmd = f"rm {remote_backup_path} /tmp/backup_n8n.sh /tmp/docker_backup.sh"
        self.remote_host_service.execute_remote_command(host_id, cleanup_cmd)
        
        if download_result.get('success'):
            yield "SUCCESS: Remote backup process completed!"
