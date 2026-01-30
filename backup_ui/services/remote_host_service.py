"""
Remote Host Service
Manages remote n8n hosts via SSH for backup/restore operations
"""
import os
import json
import uuid
import base64
from pathlib import Path
from typing import List, Dict, Optional
from datetime import datetime
import paramiko
from cryptography.fernet import Fernet


class RemoteHostService:
    """Service for managing remote n8n hosts"""

    def __init__(self):
        self.config_dir = Path(__file__).parent.parent.parent / 'config'
        self.config_dir.mkdir(exist_ok=True)

        self.config_file = self.config_dir / 'remote_hosts.json'
        self.secrets_file = self.config_dir / '.remote_secrets'
        self.key_file = self.config_dir / '.encryption_key'

        # Initialize encryption key
        self._init_encryption_key()

        # Initialize config file if not exists
        if not self.config_file.exists():
            self._save_config({'hosts': []})

    def _init_encryption_key(self):
        """Initialize or load encryption key"""
        if self.key_file.exists():
            with open(self.key_file, 'rb') as f:
                self.encryption_key = f.read()
        else:
            # Generate new key
            self.encryption_key = Fernet.generate_key()
            with open(self.key_file, 'wb') as f:
                f.write(self.encryption_key)
            # Secure the key file (Unix-like systems)
            try:
                os.chmod(self.key_file, 0o600)
            except:
                pass  # Windows doesn't support chmod

        self.cipher = Fernet(self.encryption_key)

    def _load_config(self) -> Dict:
        """Load hosts configuration"""
        try:
            with open(self.config_file, 'r', encoding='utf-8') as f:
                return json.load(f)
        except (FileNotFoundError, json.JSONDecodeError):
            return {'hosts': []}

    def _save_config(self, config: Dict):
        """Save hosts configuration"""
        with open(self.config_file, 'w', encoding='utf-8') as f:
            json.dump(config, f, indent=2)

    def _load_secrets(self) -> Dict:
        """Load and decrypt secrets"""
        if not self.secrets_file.exists():
            return {}

        try:
            with open(self.secrets_file, 'rb') as f:
                encrypted_data = f.read()

            if not encrypted_data:
                return {}

            decrypted_data = self.cipher.decrypt(encrypted_data)
            return json.loads(decrypted_data.decode('utf-8'))
        except Exception:
            return {}

    def _save_secrets(self, secrets: Dict):
        """Encrypt and save secrets"""
        secrets_json = json.dumps(secrets)
        encrypted_data = self.cipher.encrypt(secrets_json.encode('utf-8'))

        with open(self.secrets_file, 'wb') as f:
            f.write(encrypted_data)

        # Secure the secrets file (Unix-like systems)
        try:
            os.chmod(self.secrets_file, 0o600)
        except:
            pass  # Windows doesn't support chmod

    def list_hosts(self) -> List[Dict]:
        """List all configured remote hosts"""
        config = self._load_config()
        hosts = config.get('hosts', [])

        # Remove sensitive data from response
        safe_hosts = []
        for host in hosts:
            safe_host = {k: v for k, v in host.items() if k not in ['password', 'ssh_key', 'api_key']}
            safe_host['has_password'] = host.get('auth_type') == 'password'
            safe_host['has_ssh_key'] = host.get('auth_type') == 'key'
            safe_host['has_api_key'] = 'api_key' in host
            safe_hosts.append(safe_host)

        return safe_hosts

    def get_host(self, host_id: str) -> Optional[Dict]:
        """Get a specific host configuration"""
        config = self._load_config()
        for host in config.get('hosts', []):
            if host.get('id') == host_id:
                # Load secrets
                secrets = self._load_secrets()
                host_secrets = secrets.get(host_id, {})

                # Don't include raw secrets in response
                safe_host = {k: v for k, v in host.items()}
                safe_host['has_password'] = bool(host_secrets.get('password'))
                safe_host['has_ssh_key_path'] = bool(host_secrets.get('ssh_key_path'))
                safe_host['has_api_key'] = bool(host_secrets.get('api_key'))

                return safe_host
        return None

    def add_host(self, host_data: Dict) -> Dict:
        """Add a new remote host"""
        config = self._load_config()
        secrets = self._load_secrets()

        # Generate unique ID
        host_id = str(uuid.uuid4())

        # Extract secrets
        host_secrets = {}
        if 'password' in host_data:
            host_secrets['password'] = host_data.pop('password')
        if 'ssh_key_path' in host_data:
            host_secrets['ssh_key_path'] = host_data.pop('ssh_key_path')
        if 'api_key' in host_data:
            host_secrets['api_key'] = host_data.pop('api_key')

        # Create host config
        host_config = {
            'id': host_id,
            'name': host_data.get('name', 'Unnamed Host'),
            'type': host_data.get('type', 'ssh'),
            'host': host_data.get('host'),
            'port': host_data.get('port', 22),
            'username': host_data.get('username'),
            'auth_type': host_data.get('auth_type', 'password'),
            'n8n_url': host_data.get('n8n_url', f"http://{host_data.get('host')}:5678"),
            'default_instance': host_data.get('default_instance', 'n8n'),
            'manager_path': host_data.get('manager_path', '~/n8n-manager'),
            'enabled': host_data.get('enabled', True),
            'created_at': datetime.utcnow().isoformat() + 'Z'
        }

        # Save config
        config['hosts'].append(host_config)
        self._save_config(config)

        # Save secrets
        secrets[host_id] = host_secrets
        self._save_secrets(secrets)

        return {'success': True, 'host_id': host_id, 'message': 'Host added successfully'}

    def update_host(self, host_id: str, host_data: Dict) -> Dict:
        """Update an existing host"""
        config = self._load_config()
        secrets = self._load_secrets()

        # Find host
        host_index = None
        for i, host in enumerate(config.get('hosts', [])):
            if host.get('id') == host_id:
                host_index = i
                break

        if host_index is None:
            return {'success': False, 'error': 'Host not found'}

        # Extract new secrets if provided
        host_secrets = secrets.get(host_id, {})
        if 'password' in host_data:
            host_secrets['password'] = host_data.pop('password')
        if 'ssh_key_path' in host_data:
            host_secrets['ssh_key_path'] = host_data.pop('ssh_key_path')
        if 'api_key' in host_data:
            host_secrets['api_key'] = host_data.pop('api_key')

        # Update host config (preserve ID and created_at)
        existing_host = config['hosts'][host_index]
        updated_host = {
            'id': host_id,
            'name': host_data.get('name', existing_host.get('name')),
            'type': host_data.get('type', existing_host.get('type')),
            'host': host_data.get('host', existing_host.get('host')),
            'port': host_data.get('port', existing_host.get('port')),
            'username': host_data.get('username', existing_host.get('username')),
            'auth_type': host_data.get('auth_type', existing_host.get('auth_type')),
            'n8n_url': host_data.get('n8n_url', existing_host.get('n8n_url')),
            'default_instance': host_data.get('default_instance', existing_host.get('default_instance')),
            'manager_path': host_data.get('manager_path', existing_host.get('manager_path', '~/n8n-manager')),
            'enabled': host_data.get('enabled', existing_host.get('enabled')),
            'created_at': existing_host.get('created_at')
        }

        config['hosts'][host_index] = updated_host
        self._save_config(config)

        # Update secrets
        secrets[host_id] = host_secrets
        self._save_secrets(secrets)

        return {'success': True, 'message': 'Host updated successfully'}

    def delete_host(self, host_id: str) -> Dict:
        """Delete a remote host"""
        config = self._load_config()
        secrets = self._load_secrets()

        # Find and remove host
        original_count = len(config.get('hosts', []))
        config['hosts'] = [h for h in config.get('hosts', []) if h.get('id') != host_id]

        if len(config['hosts']) == original_count:
            return {'success': False, 'error': 'Host not found'}

        # Save config
        self._save_config(config)

        # Remove secrets
        if host_id in secrets:
            del secrets[host_id]
            self._save_secrets(secrets)

        return {'success': True, 'message': 'Host deleted successfully'}

    def test_connection(self, host_id: str) -> Dict:
        """Test SSH connection to a remote host"""
        host_config = self.get_host(host_id)
        if not host_config:
            return {'success': False, 'error': 'Host not found'}

        secrets = self._load_secrets()
        host_secrets = secrets.get(host_id, {})

        try:
            ssh = self._get_ssh_client(host_config, host_secrets)

            # Test command
            stdin, stdout, stderr = ssh.exec_command('echo "Connection successful"')
            output = stdout.read().decode('utf-8').strip()

            ssh.close()

            return {
                'success': True,
                'message': 'Connection successful',
                'output': output
            }
        except Exception as e:
            return {
                'success': False,
                'error': f'Connection failed: {str(e)}'
            }

    def get_remote_instances(self, host_id: str) -> Dict:
        """List n8n Docker instances on remote host"""
        host_config = self.get_host(host_id)
        if not host_config:
            return {'success': False, 'error': 'Host not found'}

        secrets = self._load_secrets()
        host_secrets = secrets.get(host_id, {})

        try:
            ssh = self._get_ssh_client(host_config, host_secrets)

            # List running containers with 'n8n' in name
            command = "docker ps --format '{{.Names}}' | grep -i n8n || echo 'No n8n containers found'"
            stdin, stdout, stderr = ssh.exec_command(command)
            output = stdout.read().decode('utf-8').strip()

            ssh.close()

            if output and output != 'No n8n containers found':
                instances = [name.strip() for name in output.split('\n') if name.strip()]
            else:
                instances = []

            return {
                'success': True,
                'instances': instances
            }
        except Exception as e:
            return {
                'success': False,
                'error': f'Failed to list instances: {str(e)}'
            }

    def upload_file(self, host_id: str, local_path: str, remote_path: str) -> Dict:
        """Upload a file to remote host via SFTP"""
        host_config = self.get_host(host_id)
        if not host_config:
            return {'success': False, 'error': 'Host not found'}

        secrets = self._load_secrets()
        host_secrets = secrets.get(host_id, {})

        try:
            ssh = self._get_ssh_client(host_config, host_secrets)
            sftp = ssh.open_sftp()
            
            sftp.put(local_path, remote_path)
            
            sftp.close()
            ssh.close()

            return {
                'success': True,
                'message': f'File uploaded successfully to {remote_path}'
            }
        except Exception as e:
            return {
                'success': False,
                'error': f'Upload failed: {str(e)}'
            }

    def download_file(self, host_id: str, remote_path: str, local_path: str) -> Dict:
        """Download a file from remote host via SFTP"""
        host_config = self.get_host(host_id)
        if not host_config:
            return {'success': False, 'error': 'Host not found'}

        secrets = self._load_secrets()
        host_secrets = secrets.get(host_id, {})

        try:
            ssh = self._get_ssh_client(host_config, host_secrets)
            sftp = ssh.open_sftp()
            
            # Ensure local directory exists
            os.makedirs(os.path.dirname(local_path), exist_ok=True)
            
            sftp.get(remote_path, local_path)
            
            sftp.close()
            ssh.close()

            return {
                'success': True,
                'message': f'File downloaded successfully to {local_path}'
            }
        except Exception as e:
            return {
                'success': False,
                'error': f'Download failed: {str(e)}'
            }

    def execute_remote_command(self, host_id: str, command: str, timeout: int = 30) -> Dict:
        """Execute a command on remote host"""
        host_config = self.get_host(host_id)
        if not host_config:
            return {'success': False, 'error': 'Host not found'}

        secrets = self._load_secrets()
        host_secrets = secrets.get(host_id, {})

        try:
            ssh = self._get_ssh_client(host_config, host_secrets)

            stdin, stdout, stderr = ssh.exec_command(command, timeout=timeout)
            output = stdout.read().decode('utf-8')
            error_output = stderr.read().decode('utf-8')
            exit_code = stdout.channel.recv_exit_status()

            ssh.close()

            return {
                'success': exit_code == 0,
                'exit_code': exit_code,
                'output': output,
                'error': error_output
            }
        except Exception as e:
            return {
                'success': False,
                'error': f'Command execution failed: {str(e)}'
            }

    def _get_ssh_client(self, host_config: Dict, host_secrets: Dict) -> paramiko.SSHClient:
        """Create and configure SSH client"""
        ssh = paramiko.SSHClient()
        ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())

        auth_type = host_config.get('auth_type', 'password')

        # Prepare connection parameters
        connect_params = {
            'hostname': host_config.get('host'),
            'port': host_config.get('port', 22),
            'username': host_config.get('username'),
            'timeout': 10
        }

        # Add authentication
        if auth_type == 'password':
            connect_params['password'] = host_secrets.get('password')
        elif auth_type == 'key':
            key_path = host_secrets.get('ssh_key_path')
            if key_path:
                connect_params['key_filename'] = key_path

        # Connect
        ssh.connect(**connect_params)

        return ssh

    def get_host_api_key(self, host_id: str) -> Optional[str]:
        """Get API key for a host (used internally)"""
        secrets = self._load_secrets()
        host_secrets = secrets.get(host_id, {})
        return host_secrets.get('api_key')
